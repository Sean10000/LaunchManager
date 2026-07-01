# Design: Services 模块 — 本地开发环境控制中心

**日期:** 2026-07-02  
**状态:** 待 review  
**范围:** v1 — 发现 + 识别 + 只读管理 + Kill

## 背景

LaunchManager 当前专注 launchd LaunchAgent/Daemon 管理。随着开发项目复杂度增加，开发者日常面临：

- 不清楚哪些本地服务已启动
- 端口被占用但不知道归属
- 无法快速识别 `node` / `python` 进程的实际框架
- 难以一键关闭占用端口的进程

**Services** 模块将 LaunchManager 扩展为本地开发环境的统一观察与控制入口，v1 聚焦「看见」和「Kill」，不做启动编排。

## 目标

| 目标 | v1 |
|------|-----|
| 自动发现监听端口与进程 | ✅ |
| 智能识别（Next.js、FastAPI、Redis…） | ✅ |
| 健康状态展示 | ✅ 进程+端口 |
| Open / Copy URL / Reveal / Kill | ✅ |
| Start / Restart / Workspace | ❌ v2 |
| HTTP 健康探测 | ❌ v2 |
| Docker API | ❌ v2 |
| Linux / Windows | ❌ macOS only |

## 方案选择

| 决策 | 选择 | 理由 |
|------|------|------|
| 导航 | 并列扩展，Services 在侧边栏底部 | 改动最小，老用户零学习成本 |
| 架构 | Pipeline Resolver + Shell 发现 | 可测试、v2 可扩展 HTTP/StartCommand |
| 发现机制 | `lsof` + `ps`（v1） | 复用 ShellRunner，快速落地 |
| 过滤 | 智能过滤 + 「显示全部」 | 避免系统服务噪声 |
| 健康 | 进程 + 端口 | 不做 HTTP 探测 |
| Kill | 确认 + SIGTERM → 5s → SIGKILL | 安全且有效 |
| 快捷操作 | Open / Copy / Reveal / Kill | 其余 v2 |

## 架构

### 侧边栏

在现有 `SidebarView` 底部（Login Items 下方）新增 **Services** 入口。Launchd 相关导航不变。

```
LaunchAgent · 用户级
LaunchAgent · 全局
LaunchDaemon · 系统
Login Items
─────────────────
⚡ Services
```

`SidebarSelection` 新增 `.services` case。

### 模块结构

```
LaunchManager/
├── Models/
│   ├── Service.swift
│   ├── ServiceHealth.swift
│   └── ListeningProcess.swift
├── Services/
│   ├── ProcessDiscoveryService.swift
│   ├── ServiceClassifier.swift
│   ├── ServiceResolvers/
│   │   ├── ExecutableResolver.swift
│   │   ├── CommandLineResolver.swift
│   │   └── ProjectResolver.swift
│   ├── DevServiceFilter.swift
│   └── ProcessKillService.swift
├── Store/
│   └── ServiceStore.swift
└── Views/
    ├── ServicesListView.swift
    ├── ServiceRowView.swift
    └── KillConfirmSheet.swift
```

### 数据流

```
Timer (3s, foreground only)
  → ProcessDiscoveryService.scan()     [Task.detached]
  → ServiceClassifier.enrich()         [Resolver pipeline]
  → DevServiceFilter.apply(showAll:)
  → ServiceStore.services              [diff 更新]
  → ServicesListView
```

`ServiceStore` 与 `AgentStore` 独立，不耦合。Launchd job 若正在跑 dev server，在 Services 里作为普通进程出现。

## 数据模型

### ListeningProcess（扫描原始数据）

```swift
struct ListeningProcess: Identifiable, Hashable {
    var id: String { "\(pid)-\(port)-\(`protocol`)" }
    let pid: Int32
    let port: Int
    let `protocol`: String          // "tcp" | "udp"
    let command: String
    let executable: String
    let workingDirectory: String?
}
```

**扫描命令（macOS）：**

```bash
lsof -iTCP -sTCP:LISTEN -nP -F pcn
ps -p <pid> -o command=
```

扫描间隔 3 秒。切到 Services 页时立即 trigger 一次 scan。

### Service（业务模型）

```swift
struct Service: Identifiable, Hashable {
    var id: String                  // "\(pid)-\(port)"
    var displayName: String         // "Next.js" | "PostgreSQL"
    var subtitle: String?           // 项目名
    var category: ServiceCategory
    var health: ServiceHealth
    let port: Int
    let host: String                // 默认 "localhost"
    let pid: Int32
    let executable: String
    let command: String
    let workingDirectory: String?
    let url: URL?
}

enum ServiceCategory: String {
    case web, database, cache, ai, proxy, other
}

enum ServiceHealth: String {
    case healthy    // 🟢 端口在听 + 进程存活
    case down       // 🔴 端口不在听或进程不存在
    case unknown    // ⚪ 无法判断
}
```

**v1 健康状态说明：**

- 仅 🟢 healthy / 🔴 down / ⚪ unknown 三态
- 不含 🟡 Starting（需 HTTP 探测，v2）
- 进程消失即从列表移除，不保留 Stopped 历史条目

**稳定 ID：** `"\(pid)-\(port)"`。进程重启后 PID 变化视为新服务（v2 可用 cwd+port 做持久关联）。

## 识别管道

四层设计，v1 实现 L1–L3，L4 HTTP 留 v2。

| 层 | 输入 | 规则示例 | 输出 |
|----|------|---------|------|
| L1 Executable | executable | redis-server→Redis, postgres→PostgreSQL, ollama→Ollama | 基础名称 + category |
| L2 CommandLine | command argv | next dev→Next.js, vite→Vite, uvicorn→FastAPI | 精确框架名 |
| L3 Project | workingDirectory | package.json name, pyproject.toml, Cargo.toml | subtitle |

**优先级：** L2 > L1 > L3（displayName）；L3 仅提供 subtitle。

**URL 生成：** category == `.web` 或 L2 识别为 HTTP 框架时，生成 `http://localhost:{port}`。

### L1 可执行文件规则（部分）

| executable | displayName | category |
|------------|-------------|----------|
| node | Node.js | web |
| python, python3 | Python | web |
| redis-server | Redis | cache |
| postgres | PostgreSQL | database |
| mongod | MongoDB | database |
| ollama | Ollama | ai |
| nginx | Nginx | proxy |
| docker-proxy | Docker | proxy |

### L2 命令行规则（部分）

| argv 匹配 | displayName |
|-----------|-------------|
| next dev / next start | Next.js |
| vite | Vite |
| nuxt dev | Nuxt |
| uvicorn | FastAPI |
| gunicorn | Flask |
| manage.py runserver | Django |
| cargo run | Rust |
| go run | Go |

### L3 项目检测

按 workingDirectory 检测文件并读取 name：

| 文件 | 字段 |
|------|------|
| package.json | `"name"` |
| pyproject.toml | `[project].name` |
| Cargo.toml | `[package].name` |
| go.mod | module path 最后一段 |

## 智能过滤（DevServiceFilter）

默认只显示开发相关服务。`@AppStorage("servicesShowAll")` 控制「显示全部」。

**默认显示（满足任一）：**

1. 已知 dev 可执行文件：node, python, python3, go, java, ruby, nginx, docker-proxy 等
2. 已知 dev 端口：3000–3010, 4000, 4173, 5000–5001, 5173, 5432, 6379, 8000–8008, 8080, 8443, 9000, 11434, 27017
3. L2 识别命中 dev 框架

**默认隐藏：** mDNS (5353)、AirPlay、系统代理等。

「显示全部」时列出所有 TCP LISTEN 进程，仍走识别管道。

## 健康判定

每次扫描：

```
端口 LISTEN + kill(pid, 0) 成功 → .healthy
否则                          → .down（或不出现在列表）
```

## UI 设计

### ServicesListView

与 `AgentListView` 风格一致：`ScrollView` + `LazyVStack` + toolbar。

**Toolbar：**

- 「显示全部」Toggle
- 刷新按钮（立即 scan）
- `.searchable`：匹配 displayName、subtitle、端口、executable

**空状态：**

```
ContentUnavailableView(
  "没有发现开发服务",
  systemImage: "bolt.slash",
  description: "尝试启动 dev server，或开启「显示全部」"
)
```

### ServiceRowView

| 元素 | 内容 |
|------|------|
| 状态点 | 🟢 / 🔴，`help` 显示 PID |
| 主标题 | displayName |
| 副标题 | subtitle（.caption .secondary） |
| 地址 | localhost:port 或 URL（.monospaced） |
| 主按钮 | 有 URL → Open；无 URL → Copy |
| ··· 菜单 | Open in Browser / Copy URL / Reveal in Finder / Kill Process… |

无展开 chevron。PID、command 在 tooltip 和 Kill Sheet 中展示。

### KillConfirmSheet

展示：displayName、地址、PID、workingDirectory。  
「终止进程」为 destructive button。

### ContentView 集成

- Services 页启用 searchable
- `ServiceStore` 在 app 前台运行 scan timer；切离 Services 不停止 timer
- `scenePhase != .active` 时暂停 timer

## Kill 流程

```
用户确认 Kill
  → pendingKillIDs.insert(service.id)
  → Task.detached: kill(pid, SIGTERM)
  → 轮询 5s（每 500ms）
  → 仍存活 → kill(pid, SIGKILL)
  → 清除 pending，立即 rescan
```

**权限：**

- 当前用户进程：直接 kill
- 其他用户/root 进程：alert「权限不足」，不弹 admin 密码

**docker-proxy：** Kill 仅终止代理进程，不 stop 容器。tooltip 标注「Docker 代理进程」。

## 错误处理

| 场景 | 处理 |
|------|------|
| lsof/ps 失败 | 保留上次结果，toolbar 警告 icon |
| cwd 获取失败 | workingDirectory = nil，Reveal disabled |
| 同端口多 PID | 每个 PID 独立一行 |
| Kill 时进程已退出 | 静默成功 |
| Kill 权限不足 | Alert |

## 扫描性能

- scan 在 Task.detached，不阻塞 UI
- ServiceStore diff 更新，避免整表重绘
- 仅 app 前台运行 timer

## v2 延后

| 功能 | 说明 |
|------|------|
| Start / Stop / Restart | 需推断启动命令 |
| Workspace 分组 + 批量启停 | 依赖 Start/Stop |
| HTTP 健康探测 + 🟡 Starting | Layer 4 |
| View Logs / Terminal / VS Code | 扩展快捷操作 |
| Docker API | 容器级管理 |
| libproc 原生发现 | 性能优化 |
| LaunchAgent 关联 | 跨模块链接 |

## 测试策略

| 层 | 方法 |
|----|------|
| DevServiceFilter | 单元测试 mock Service 列表 |
| ServiceResolvers (L1/L2/L3) | 单元测试 mock command/cwd |
| ProcessDiscoveryService | fixture mock lsof 输出解析 |
| ServiceStore | mock discovery + classifier |
| ProcessKillService | mock kill 时序 SIGTERM→SIGKILL |

不新增 UI 测试。

## 本地化

新增 String Catalog keys（zh-Hans + en），遵循现有 `Localizable.xcstrings` 模式。
