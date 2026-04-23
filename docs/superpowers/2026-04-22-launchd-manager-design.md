# LaunchManager — 设计文档

**日期：** 2026-04-22  
**状态：** 待实现  
**目标：** 一个免费开源的 macOS launchd 可视化管理工具，功能对标 Lingon X

---

## 背景

macOS 上管理 LaunchAgent / LaunchDaemon 的 GUI 工具均为付费软件（Lingon X ~$10、LaunchControl ~$25）。本项目提供同等核心功能的开源替代品。

---

## 技术选型

| 项目 | 选择 |
|------|------|
| 语言 | Swift 5.9+ |
| UI 框架 | SwiftUI |
| 最低系统版本 | macOS 13 Ventura |
| 特权操作 | osascript `do shell script ... with administrator privileges` |
| 第三方依赖 | 无 |

---

## 功能范围

| 功能 | 说明 |
|------|------|
| 列出 | 扫描三个目录，显示所有 agent/daemon 及运行状态 |
| 启用/禁用 | `launchctl load` / `unload` |
| 手动启停 | `launchctl start` / `stop` |
| 新建 | 表单填写，生成并写入 plist |
| 编辑 | 修改已有 plist 参数 |
| 删除 | 先 unload，再删除 plist 文件 |
| 查看日志 | 读取 plist 配置的 stdout/stderr 文件；同时用 `log show` 拉取系统日志 |

**覆盖范围：**
- `~/Library/LaunchAgents`（用户 Agent，无需授权）
- `/Library/LaunchAgents`（系统 Agent，写操作需管理员密码）
- `/Library/LaunchDaemons`（系统 Daemon，写操作需管理员密码）

---

## 项目结构

```
LaunchManager/
├── LaunchManagerApp.swift
├── Models/
│   └── LaunchItem.swift
├── Services/
│   ├── LaunchctlService.swift
│   ├── PlistService.swift
│   └── PrivilegeService.swift
├── Views/
│   ├── ContentView.swift
│   ├── SidebarView.swift
│   ├── AgentListView.swift
│   ├── AgentRowView.swift
│   ├── EditAgentSheet.swift
│   └── LogViewerSheet.swift
└── Assets.xcassets
```

---

## 数据模型

```swift
struct LaunchItem: Identifiable, Hashable {
    var id: String { label }
    var label: String
    var plistURL: URL
    var scope: Scope

    // 程序
    var program: String
    var programArguments: [String]

    // 触发方式（四选一）
    var triggerType: TriggerType
    var calendarInterval: CalendarInterval?
    var startInterval: Int?          // 秒
    var watchPaths: [String]

    // 行为开关
    var runAtLoad: Bool
    var keepAlive: Bool

    // 可选日志路径
    var standardOutPath: String?
    var standardErrorPath: String?

    // 运行时状态（不持久化，来自 launchctl list）
    var isLoaded: Bool
    var pid: Int?
    var lastExitCode: Int?

    enum Scope {
        case userAgent      // ~/Library/LaunchAgents
        case systemAgent    // /Library/LaunchAgents
        case systemDaemon   // /Library/LaunchDaemons
    }

    enum TriggerType { case calendar, interval, atLoad, watchPath }

    struct CalendarInterval {
        var weekday: Int?   // 1=周一…7=周日，nil=每天
        var hour: Int?      // nil=每小时
        var minute: Int
    }
}
```

---

## 状态管理

`AgentStore` 是全局 `@StateObject`，持有所有 `LaunchItem`，驱动整个 UI：

```swift
@MainActor
class AgentStore: ObservableObject {
    @Published var items: [LaunchItem] = []
    @Published var warnings: [String] = []  // 解析失败的 plist 文件名

    func refresh()  // 重新扫描 + 注入运行时状态
}
```

---

## Services 层

### LaunchctlService

负责所有 `launchctl` CLI 交互。

```swift
func listAll() -> [String: (pid: Int?, exitCode: Int?)]
// 解析 `launchctl list` 的 tabular 输出

func load(_ url: URL, privileged: Bool) throws
func unload(_ url: URL, privileged: Bool) throws
func start(_ label: String, privileged: Bool) throws
func stop(_ label: String, privileged: Bool) throws
```

### PlistService

负责扫描目录、解析 plist、序列化写入。

```swift
func scanAll() -> [LaunchItem]
// 依次扫描三个目录，解析每个 .plist 文件
// 解析失败的文件跳过并记录警告

func save(_ item: LaunchItem, privileged: Bool) throws
// 将 LaunchItem 序列化为 PropertyListSerialization 字典并写入

func delete(_ item: LaunchItem, privileged: Bool) throws
// 先 unload，再删除 plist 文件
```

### PrivilegeService

osascript 授权包装。

```swift
func run(_ shellCommand: String) throws
// 执行：osascript -e 'do shell script "<cmd>" with administrator privileges'
// 用户取消 → 抛 PrivilegeError.cancelled
// 密码错误 → 抛 PrivilegeError.denied
```

**授权规则：** `item.scope == .userAgent` 时 `privileged = false`，否则为 `true`。

---

## UI 结构

### 主窗口

```
NavigationSplitView
├── Sidebar（SidebarView）
│   ├── 用户 Agents
│   ├── 系统 Agents
│   └── 系统 Daemons
└── Detail（AgentListView）
    └── AgentRowView × N（可展开）
工具栏：[刷新] [新建]
```

### AgentRowView 展开状态

```
折叠：[状态色] [label]              [启动/停止] [编辑] [删除]
展开：
      程序     /usr/bin/open -a Syncthing
      触发     每天 08:00
      路径     ~/Library/LaunchAgents/com.syncthing.start.plist
      [查看日志]
```

状态色：绿 = 运行中（有 PID）、灰 = 已停止、黄 = 异常（lastExitCode ≠ 0）

### LogViewerSheet

点击「查看日志」后以 Sheet 弹出，分两个 Tab：

**文件日志 Tab**
- 读取 plist 中配置的 `StandardOutPath` / `StandardErrorPath` 文件内容
- 如果未配置路径，显示提示"未配置日志文件路径"
- 支持「清空」按钮（截断文件）

**系统日志 Tab**
- 执行 `log show --predicate 'subsystem == "<label>"' --last 1h` 拉取最近 1 小时系统日志
- 以等宽字体展示，支持按关键字过滤（本地 filter，不重新执行命令）

### EditAgentSheet（单页 Sheet）

字段：
- Label（必填）
- 程序路径（必填）+ 文件选择器
- 参数（多行，每行一个）
- 触发方式：定时 / 间隔 / 登录时 / 监视路径
  - 定时：星期 toggle group + HH:MM
  - 间隔：秒数输入
  - 监视路径：路径输入
- 加载时自动运行（Toggle）
- 保持存活（Toggle）
- 标准输出日志路径（可选）

---

## 数据流

```
App 启动
  PlistService.scanAll() → [LaunchItem]
  LaunchctlService.listAll() → 注入运行状态
  → @StateObject AgentStore 驱动 UI

用户操作（启停/载入/卸载/保存/删除）
  → Service 方法（根据 scope 决定是否走 PrivilegeService）
  → 操作完成后调用 AgentStore.refresh()
```

---

## 错误处理

| 场景 | 处理方式 |
|------|----------|
| 用户取消授权 | Alert 提示，操作取消，不崩溃 |
| plist 解析失败 | 跳过文件，列表中显示警告行 |
| launchctl 返回非零 | Alert 展示错误输出 |
| 文件写入失败 | Alert 提示具体错误 |

---

## 测试策略

- `LaunchctlService` / `PlistService`：`XCTest` 单元测试，mock shell 命令输出
- Views：Xcode Previews 覆盖折叠/展开/新建等状态
- 手动测试：针对用户级 agent 的完整 CRUD 流程

---

## 不在范围内

- App Store 分发（需要 Hardened Runtime + 额外权限）
- `/System/Library/` 下的 Apple 系统 agent（只读，不显示）
- Launch Constraints（macOS 13+ 新特性，暂不支持）
- 菜单栏常驻图标
