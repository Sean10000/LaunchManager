# Design: Start / Stop 点击反馈与防误触

**日期:** 2026-06-08  
**状态:** 已批准

## 背景

用户反馈点击「启动」「停止」后界面无即时反馈，误以为未点击而重复点击，导致 start→stop 等误操作。根因：

1. `AgentRowView` 点击后直接同步调用 `store.start()` / `store.stop()`，按钮无任何 pending 状态
2. `AgentStore` 在 `@MainActor` 上同步执行 `launchctl` shell + 全量 `refresh()`，主线程阻塞
3. 按钮文案仅在 `refresh()` 后 `item.pid` 变化时才切换；start/stop 另有 800ms / 400ms 延迟二次 refresh
4. 无防重复点击机制

同类问题也存在于「载入」「移除」（bootstrap / bootout）。

## 目标

- 点击后 **立即** 给出三层反馈：按钮 spinner + 进行中文案 + 状态点过渡动画
- **整行锁定**，防止连点引发误操作
- **异步执行** launchctl，保持 UI 流畅（spinner 可正常动画）
- pending 文案 **跟随系统语言**（String Catalog，zh-Hans + en）
- 范围：Start / Stop + 载入 / 移除；不含删除流程

## 方案选择

| 决策 | 选择 |
|------|------|
| 反馈样式 | D：Spinner + 文案 + 状态点过渡 + 整行禁用 |
| 操作范围 | B：Start / Stop + bootstrap / bootout |
| 执行模型 | B：pending UI + 后台异步 launchctl |
| 状态管理 | Store 集中管理 `pendingOperations`（推荐方案 1） |

## 架构

### 新增类型

```swift
enum PendingOperation: Equatable {
    case starting   // kickstart
    case stopping   // kill SIGTERM
    case loading    // bootstrap
    case unloading  // bootout
}
```

### AgentStore 变更

- 新增 `@Published var pendingOperations: [String: PendingOperation] = [:]`，key 为 `LaunchItem.label`
- `start` / `stop` / `bootstrap` / `bootout` 改为 fire-and-forget async：
  1. `guard pendingOperations[label] == nil else { return }` — 吞掉重复点击
  2. 设置 `pendingOperations[label]`
  3. `Task { ... }` 内执行 launchctl → `refresh()` → 可选延迟二次 refresh（start 800ms / stop 400ms 保留）→ 清除 pending
  4. 失败时清除 pending 并设置 `errorMessage`（沿用现有 alert）
- 失败时清除 pending，通过现有 `errorMessage: Binding<String?>` 传给 View 显示 alert（保持 ContentView → AgentRowView 现有模式，不迁移到 Store）

### 异步执行规则

| 操作 | 执行上下文 |
|------|-----------|
| User Agent shell（`DefaultShellRunner`） | `Task.detached` 或 nonisolated 后台 |
| System Agent/Daemon（`PrivilegeService`） | `MainActor`（`NSAppleScript` admin 弹窗必须在主线程） |
| `refresh()` | `@MainActor` |
| 延迟二次 refresh | `@MainActor` + `Task.sleep` |

### 数据流

```
User tap → Store sets pending → UI redraws immediately
         → Task runs launchctl (BG or MainActor for privilege)
         → refresh()
         → optional delayed refresh (start/stop only)
         → clear pending → UI shows real state
```

## UI 行为（AgentRowView）

### Pending 状态外观

| 元素 | Pending 行为 |
|------|-------------|
| 状态点 | 黄色 + 脉冲动画（覆盖正常运行/停止色） |
| 主按钮 | `ProgressView` + 进行中文案，`.disabled(true)` |
| 编辑 / 删除 / 展开 chevron | 禁用 |
| 展开区内「移除」「查看日志」 | 禁用 |

### 主按钮文案映射

| PendingOperation | 按钮文案 (zh-Hans key) |
|------------------|------------------------|
| `.starting` | `启动中…` |
| `.stopping` | `停止中…` |
| `.loading` | `载入中…` |
| `.unloading` | `移除中…` |

View 通过 `store.pendingOperations[item.label]` 判断 pending 类型；无 pending 时保持现有逻辑（启动 / 停止 / 载入）。

### 读取 pending

```swift
// AgentRowView
private var pending: PendingOperation? {
    store.pendingOperations[item.label]
}
```

主按钮 `@ViewBuilder` 优先渲染 pending 分支，再 fallback 到现有 pid / isLoaded 分支。

## 本地化

所有 pending 文案加入 `LaunchManager/Localizable.xcstrings`，与现有「启动」「停止」「载入」一致：

| Key (zh-Hans) | English |
|---------------|---------|
| `启动中…` | `Starting…` |
| `停止中…` | `Stopping…` |
| `载入中…` | `Loading…` |
| `移除中…` | `Unloading…` |

代码使用 `LocalizedStringKey` / `String(localized:)` / `Text("启动中…")`，不写硬编码英文字符串。系统语言为英文时自动显示英文。

## 错误与边界

| 场景 | 行为 |
|------|------|
| launchctl 失败 | 清除 pending，弹出已有错误 alert |
| 用户取消 admin 密码（`-128`） | 清除 pending，不弹错误（`PrivilegeError.cancelled`） |
| 同一 label 重复点击 | 忽略（guard pending） |
| 不同 label 并行操作 | 允许 |
| `refresh()` 更新 items | 不影响 pending map（key 为 label，与 item 实例无关） |
| admin 弹窗期间 | pending 保持，按钮继续显示「停止中…」等 |

## 不在本次范围

- 删除确认流程的 pending 状态
- 乐观 UI（立即切换 pid / 按钮，失败回滚）
- toolbar「刷新」按钮 pending
- Operation Actor 队列（YAGNI）

## 改动文件

| 文件 | 改动 |
|------|------|
| `Store/AgentStore.swift` | pending map、async 操作、错误出口 |
| `Views/AgentRowView.swift` | pending UI、整行禁用、状态点动画 |
| `Localizable.xcstrings` | 4 条 pending 文案 + en 译文 |
| `LaunchManagerTests/LaunchManagerTests.swift` | pending guard、async 行为单元测试（可选但建议） |

## 验收标准

1. 点击启动/停止/载入/移除后 **100ms 内** 可见 spinner + 文案变化 + 状态点变黄
2. pending 期间同一行所有操作按钮不可点击；连点不触发第二次 launchctl
3. 操作完成后 UI 恢复真实状态；失败时 alert 正常、pending 清除
4. 系统语言切英文时，pending 文案显示 Starting… / Stopping… 等
5. System Agent/Daemon 弹 admin 密码期间，行保持 pending 锁定
