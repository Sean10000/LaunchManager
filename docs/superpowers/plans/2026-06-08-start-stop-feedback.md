# Start / Stop 点击反馈 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 Start / Stop / 载入 / 移除 操作提供即时 pending 反馈（spinner + 文案 + 状态点脉冲 + 整行锁定），异步执行 launchctl，防止连点误操作。

**Architecture:** `AgentStore` 集中维护 `[label: PendingOperation]` pending map；点击后立即设 pending 并重绘 UI，`Task` 内在后台（或 MainActor for privilege）执行 launchctl，完成后 refresh 并清除 pending。`AgentRowView` 读取 pending 状态渲染过渡 UI，错误仍通过现有 `errorMessage` Binding 弹出 alert。

**Tech Stack:** Swift 5.10, SwiftUI, XCTest, String Catalog (`.xcstrings`), macOS 14+

**Spec:** `docs/superpowers/specs/2026-06-08-start-stop-feedback-design.md`

---

## File Map

| 操作 | 文件 | 职责 |
|------|------|------|
| Create | `LaunchManager/Models/PendingOperation.swift` | pending 枚举 + 本地化 label |
| Modify | `LaunchManager/Store/AgentStore.swift` | pending map、async 操作、DI init |
| Modify | `LaunchManager/Views/AgentRowView.swift` | pending UI、整行禁用、状态点动画 |
| Modify | `LaunchManager/Localizable.xcstrings` | 4 条 pending 文案 en 译文 |
| Modify | `LaunchManagerTests/LaunchManagerTests.swift` | AgentStore pending / 防重复点击测试 |

> 项目使用 `PBXFileSystemSynchronizedRootGroup`，新建 Swift 文件放入 `LaunchManager/` 目录即可，无需手动改 `project.pbxproj`。

---

### Task 1: PendingOperation 模型与本地化字符串

**Files:**
- Create: `LaunchManager/Models/PendingOperation.swift`
- Modify: `LaunchManager/Localizable.xcstrings`

- [ ] **Step 1: 创建 PendingOperation.swift**

```swift
import SwiftUI

enum PendingOperation: Equatable {
    case starting
    case stopping
    case loading
    case unloading

    var localizedLabel: LocalizedStringKey {
        switch self {
        case .starting:  return "启动中…"
        case .stopping:  return "停止中…"
        case .loading:   return "载入中…"
        case .unloading: return "移除中…"
        }
    }
}
```

- [ ] **Step 2: 在 Localizable.xcstrings 添加 4 条 en 译文**

在 `"strings"` 对象中按字母序插入（紧挨 `"启动"` 条目附近），格式与现有条目一致：

```json
"启动中…" : {
  "localizations" : {
    "en" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "Starting…"
      }
    }
  }
},
"停止中…" : {
  "localizations" : {
    "en" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "Stopping…"
      }
    }
  }
},
"载入中…" : {
  "localizations" : {
    "en" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "Loading…"
      }
    }
  }
},
"移除中…" : {
  "localizations" : {
    "en" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "Unloading…"
      }
    }
  }
}
```

- [ ] **Step 3: 编译确认无语法错误**

```bash
cd /Users/sean/LaunchManager/LaunchManager
xcodebuild build -project LaunchManager.xcodeproj -scheme LaunchManager -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```

预期：`BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add LaunchManager/Models/PendingOperation.swift LaunchManager/Localizable.xcstrings
git commit -m "feat: add PendingOperation model and localized pending labels"
```

---

### Task 2: AgentStore 异步操作与 pending 状态

**Files:**
- Modify: `LaunchManager/Store/AgentStore.swift`
- Modify: `LaunchManagerTests/LaunchManagerTests.swift`

- [ ] **Step 1: 写失败测试 — pending 防重复点击**

在 `LaunchManagerTests/LaunchManagerTests.swift` 末尾追加：

```swift
// MARK: - AgentStore Pending Tests

private final class KickstartCountingShell: ShellRunner, @unchecked Sendable {
    private(set) var kickstartCount = 0
    private let lock = NSLock()

    func run(_ path: String, arguments: [String]) throws -> String {
        if path == "/bin/launchctl" {
            if arguments.first == "kickstart" {
                lock.lock()
                kickstartCount += 1
                lock.unlock()
                Thread.sleep(forTimeInterval: 0.15)
            }
            if arguments.first == "list" {
                return "PID\tStatus\tLabel\n"
            }
        }
        return ""
    }
}

@MainActor
final class AgentStorePendingTests: XCTestCase {
    private func makeItem(label: String = "com.test.pending") -> LaunchItem {
        LaunchItem(
            label: label,
            plistURL: URL(fileURLWithPath: "/tmp/\(label).plist"),
            scope: .userAgent,
            program: "/bin/echo",
            programArguments: [],
            triggerType: .atLoad,
            calendarInterval: nil,
            startInterval: nil,
            watchPaths: [],
            runAtLoad: true,
            keepAlive: false,
            standardOutPath: nil,
            standardErrorPath: nil,
            isLoaded: true,
            pid: nil,
            lastExitCode: 0
        )
    }

    func test_start_setsPendingImmediately() {
        let shell = KickstartCountingShell()
        let store = AgentStore(launchctlService: LaunchctlService(shell: shell))
        let item = makeItem()

        store.start(item)

        XCTAssertEqual(store.pendingOperations[item.label], .starting)
    }

    func test_duplicateStartWhilePending_ignored() async throws {
        let shell = KickstartCountingShell()
        let store = AgentStore(launchctlService: LaunchctlService(shell: shell))
        let item = makeItem()

        store.start(item)
        store.start(item)

        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(shell.kickstartCount, 1)
        XCTAssertNil(store.pendingOperations[item.label])
    }

    func test_startFailure_clearsPending() async throws {
        struct FailingShell: ShellRunner {
            func run(_ path: String, arguments: [String]) throws -> String {
                if arguments.first == "kickstart" {
                    throw ShellError.nonZeroExit(code: 1, output: "kickstart failed")
                }
                return "PID\tStatus\tLabel\n"
            }
        }
        let store = AgentStore(launchctlService: LaunchctlService(shell: FailingShell()))
        let item = makeItem()
        var capturedError: String?

        store.start(item) { capturedError = $0 }

        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertNil(store.pendingOperations[item.label])
        XCTAssertNotNil(capturedError)
    }
}
```

- [ ] **Step 2: 运行测试，确认 FAIL（AgentStore 尚无 pending / DI）**

```bash
cd /Users/sean/LaunchManager/LaunchManager
xcodebuild test -project LaunchManager.xcodeproj -scheme LaunchManager -destination 'platform=macOS' -only-testing:LaunchManagerTests/AgentStorePendingTests 2>&1 | grep -E "passed|failed|error:|BUILD"
```

预期：编译失败或测试 FAIL（`pendingOperations` / init 不存在）

- [ ] **Step 3: 重写 AgentStore.swift**

完整替换 `LaunchManager/Store/AgentStore.swift`：

```swift
import Foundation

@MainActor
final class AgentStore: ObservableObject {
    @Published var items: [LaunchItem] = []
    @Published var invalidItems: [InvalidPlist] = []
    @Published var pendingOperations: [String: PendingOperation] = [:]

    private let plistService: PlistService
    private let launchctlService: LaunchctlService
    private let privilegeService: PrivilegeService

    init(plistService: PlistService = PlistService(),
         launchctlService: LaunchctlService = LaunchctlService(),
         privilegeService: PrivilegeService = PrivilegeService()) {
        self.plistService = plistService
        self.launchctlService = launchctlService
        self.privilegeService = privilegeService
    }

    func refresh() {
        let (scanned, invalid) = plistService.scanAll()
        let statuses = (try? launchctlService.listAll()) ?? [:]
        items = scanned.map { item in
            var copy = item
            if let s = statuses[item.label] {
                copy.isLoaded     = true
                copy.pid          = s.pid
                copy.lastExitCode = s.exitCode
            }
            return copy
        }
        invalidItems = invalid
    }

    func bootstrap(_ item: LaunchItem, onError: @escaping (String) -> Void = { _ in }) {
        runPending(item.label, .loading, onError: onError) {
            try await self.runLaunchctl(scope: item.scope) {
                try self.launchctlService.bootstrap(item.plistURL, scope: item.scope)
            }
            await self.refresh()
        }
    }

    func bootout(_ item: LaunchItem, onError: @escaping (String) -> Void = { _ in }) {
        runPending(item.label, .unloading, onError: onError) {
            try await self.runLaunchctl(scope: item.scope) {
                try self.launchctlService.bootout(item.plistURL, scope: item.scope)
            }
            await self.refresh()
        }
    }

    func start(_ item: LaunchItem, onError: @escaping (String) -> Void = { _ in }) {
        runPending(item.label, .starting, onError: onError) {
            try await self.runLaunchctl(scope: item.scope) {
                try self.launchctlService.start(item.label, scope: item.scope)
            }
            await self.refresh()
            try? await Task.sleep(nanoseconds: 800_000_000)
            await self.refresh()
        }
    }

    func stop(_ item: LaunchItem, onError: @escaping (String) -> Void = { _ in }) {
        runPending(item.label, .stopping, onError: onError) {
            try await self.runLaunchctl(scope: item.scope) {
                try self.launchctlService.stop(item.label, scope: item.scope)
            }
            await self.refresh()
            try? await Task.sleep(nanoseconds: 400_000_000)
            await self.refresh()
        }
    }

    func save(_ item: LaunchItem) throws {
        try plistService.save(item, privilege: privilegeService)
        refresh()
    }

    func delete(_ item: LaunchItem) throws {
        try plistService.delete(item, launchctl: launchctlService, privilege: privilegeService)
        refresh()
    }

    func deleteInvalid(_ item: InvalidPlist) throws {
        if item.scope.requiresPrivilege {
            try privilegeService.run("rm \(item.url.path)")
        } else {
            try FileManager.default.removeItem(at: item.url)
        }
        refresh()
    }

    // MARK: - Private

    private func runPending(
        _ label: String,
        _ operation: PendingOperation,
        onError: @escaping (String) -> Void,
        work: @escaping () async throws -> Void
    ) {
        guard pendingOperations[label] == nil else { return }
        pendingOperations[label] = operation
        Task {
            defer { pendingOperations.removeValue(forKey: label) }
            do {
                try await work()
            } catch PrivilegeError.cancelled {
                // user dismissed admin dialog — no alert
            } catch {
                onError(error.localizedDescription)
            }
        }
    }

    private func runLaunchctl(
        scope: LaunchItem.Scope,
        _ block: @Sendable () throws -> Void
    ) async throws {
        if scope.requiresPrivilege {
            try await MainActor.run { try block() }
        } else {
            try await Task.detached { try block() }.value
        }
    }
}
```

- [ ] **Step 4: 运行测试，确认 PASS**

```bash
cd /Users/sean/LaunchManager/LaunchManager
xcodebuild test -project LaunchManager.xcodeproj -scheme LaunchManager -destination 'platform=macOS' -only-testing:LaunchManagerTests/AgentStorePendingTests 2>&1 | grep -E "Test case|passed|failed|error:"
```

预期：3 个测试全部 `passed`

- [ ] **Step 5: 运行全部单元测试**

```bash
cd /Users/sean/LaunchManager/LaunchManager
xcodebuild test -project LaunchManager.xcodeproj -scheme LaunchManager -destination 'platform=macOS' -only-testing:LaunchManagerTests 2>&1 | grep -E "Test Suite|passed|failed"
```

预期：全部 PASS

- [ ] **Step 6: Commit**

```bash
git add LaunchManager/Store/AgentStore.swift LaunchManagerTests/LaunchManagerTests.swift
git commit -m "feat: async launchctl operations with pending state guard"
```

---

### Task 3: AgentRowView pending UI

**Files:**
- Modify: `LaunchManager/Views/AgentRowView.swift`

- [ ] **Step 1: 添加 pending 计算属性与状态点动画**

在 `AgentRowView` 内、`statusColor` 之前添加：

```swift
private var pending: PendingOperation? {
    store.pendingOperations[item.label]
}

private var isRowLocked: Bool {
    pending != nil
}
```

将 `statusColor` 替换为：

```swift
var statusColor: Color {
    if pending != nil { return .yellow }
    if item.pid != nil { return .green }
    if let code = item.lastExitCode {
        if code == 0  { return .blue.opacity(0.7) }
        if code > 0   { return .yellow }
    }
    return Color(nsColor: .tertiaryLabelColor)
}
```

在状态点 `Circle()` 上添加脉冲动画（替换 body 中第 36 行的 Circle）：

```swift
Circle()
    .fill(statusColor)
    .frame(width: 8, height: 8)
    .opacity(isRowLocked ? (pulseOpacity ? 1.0 : 0.35) : 1.0)
    .animation(
        isRowLocked ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default,
        value: pulseOpacity
    )
    .onAppear { pulseOpacity = true }
    .onChange(of: isRowLocked) { _, locked in
        pulseOpacity = locked
    }
    .help(statusTooltip)
```

在 struct 顶部 `@State` 区域添加：

```swift
@State private var pulseOpacity = false
```

- [ ] **Step 2: 重写 primaryActionButton 支持 pending**

```swift
@ViewBuilder
private var primaryActionButton: some View {
    if let pending {
        Button {} label: {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(pending.localizedLabel)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .disabled(true)
    } else if item.pid != nil {
        Button("停止") {
            store.stop(item) { errorMessage = $0 }
        }
        .buttonStyle(.borderedProminent).controlSize(.small)
    } else if item.isLoaded {
        Button("启动") {
            store.start(item) { errorMessage = $0 }
        }
        .buttonStyle(.bordered).controlSize(.small)
    } else {
        Button("载入") {
            store.bootstrap(item) { errorMessage = $0 }
        }
        .buttonStyle(.bordered).controlSize(.small)
    }
}
```

- [ ] **Step 3: 整行锁定 — 禁用编辑/删除/展开/展开区内按钮**

给编辑、删除、展开 chevron 按钮各加 `.disabled(isRowLocked)`：

```swift
Button { showingEdit = true } label: { Image(systemName: "pencil") }
    .buttonStyle(.borderless)
    .disabled(isRowLocked)
```

```swift
Button(role: .destructive) { showingDeleteConfirm = true } label: { Image(systemName: "trash") }
    .buttonStyle(.borderless)
    .disabled(isRowLocked)
```

```swift
Button { withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() } } label: { ... }
    .buttonStyle(.borderless)
    .disabled(isRowLocked)
```

展开区内按钮：

```swift
if item.isLoaded {
    Button("移除") { store.bootout(item) { errorMessage = $0 } }
        .buttonStyle(.bordered).controlSize(.small)
        .disabled(isRowLocked)
}
Button("查看日志") { showingLog = true }
    .buttonStyle(.bordered).controlSize(.small)
    .disabled(isRowLocked)
```

- [ ] **Step 4: 删除旧的 perform() 同步 wrapper**

删除 `private func perform(_ action: @escaping () throws -> Void)` 方法。删除确认对话框仍用同步 `store.delete(item)` — 在 `catch` 中设置 errorMessage：

```swift
Button("删除", role: .destructive) {
    do { try store.delete(item) }
    catch { errorMessage = error.localizedDescription }
}
```

- [ ] **Step 5: 编译并手动验证**

```bash
cd /Users/sean/LaunchManager/LaunchManager
xcodebuild build -project LaunchManager.xcodeproj -scheme LaunchManager -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```

手动验证清单（⌘R 运行 app）：
1. 点击「启动」→ 100ms 内按钮变 spinner +「启动中…」，状态点变黄脉冲
2. 连点「启动」→ 不触发第二次 kickstart，不出现 start→stop 误操作
3. 操作完成后按钮恢复真实状态
4. 「载入」「移除」同样 pending 反馈
5. pending 期间编辑/删除/展开不可点
6. 系统语言切 English → 显示 Starting… / Stopping… 等

- [ ] **Step 6: Commit**

```bash
git add LaunchManager/Views/AgentRowView.swift
git commit -m "feat: show pending spinner and row lock on start/stop/load/unload"
```

---

## Spec Coverage Checklist

| Spec 要求 | 对应 Task |
|-----------|-----------|
| PendingOperation 四种状态 | Task 1 |
| Store pending map + guard 重复点击 | Task 2 |
| 异步 launchctl（BG / MainActor privilege） | Task 2 `runLaunchctl` |
| start/stop 延迟二次 refresh | Task 2 |
| 错误 → onError → alert；cancelled 不弹 | Task 2 |
| Spinner + 文案 + 状态点脉冲 + 整行锁定 | Task 3 |
| 本地化 4 条 pending 文案 | Task 1 |
| 不含删除 pending | Task 3 仅改 delete 为 inline catch |

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-06-08-start-stop-feedback.md`. Two execution options:

**1. Subagent-Driven (recommended)** — 每个 task 派发独立 subagent，task 间 review，迭代快

**2. Inline Execution** — 在本 session 用 executing-plans 按 task 批量执行，checkpoint Review

Which approach?
