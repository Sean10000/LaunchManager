# Invalid Plist 内联显示与删除 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将无法解析的 plist 文件内联显示在对应 scope 列表中，替代底部 warning 栏，让用户可以直接删除它们。

**Architecture:** 引入独立的 `InvalidPlist` 模型，`PlistService.scanAll()` 同时返回有效和无效条目，`AgentStore` 持有两个列表。UI 层用新的 `InvalidPlistRowView` 在主列表末尾渲染无效条目，warning 栏整个移除。

**Tech Stack:** Swift 5.10, SwiftUI, XCTest（@testable import LaunchManager）

---

## File Map

| 操作 | 文件 | 职责 |
|------|------|------|
| Create | `LaunchManager/Models/InvalidPlist.swift` | InvalidPlist 数据模型 |
| Modify | `LaunchManager/Services/PlistService.swift` | scanAll 返回 invalid 数组 |
| Modify | `LaunchManager/Store/AgentStore.swift` | 替换 warnings → invalidItems，新增 deleteInvalid |
| Create | `LaunchManager/Views/InvalidPlistRowView.swift` | 无效条目行视图 |
| Modify | `LaunchManager/Views/AgentListView.swift` | 接受 invalidItems，移除 warning 栏 |
| Modify | `LaunchManager/ContentView.swift` | 新增 filteredInvalidItems，传入 AgentListView |
| Modify | `LaunchManagerTests/LaunchManagerTests.swift` | 新增 InvalidPlist 相关测试 |

---

### Task 1: InvalidPlist 模型 + PlistService 更新

**Files:**
- Create: `LaunchManager/Models/InvalidPlist.swift`
- Modify: `LaunchManager/Services/PlistService.swift`
- Modify: `LaunchManagerTests/LaunchManagerTests.swift`

- [ ] **Step 1: 写失败测试 — 空 plist 应被归入 invalid**

在 `LaunchManagerTests/LaunchManagerTests.swift` 末尾的 `PlistServiceTests` class 里追加：

```swift
func test_parsePlist_emptyDict_returnsNil() throws {
    let plist = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict/></plist>
    """
    let url = tmpDir.appendingPathComponent("empty.plist")
    try plist.write(to: url, atomically: true, encoding: .utf8)
    XCTAssertNil(svc.parsePlist(at: url, scope: .userAgent))
}

func test_scanAll_separatesInvalidItems() throws {
    // 有效 plist
    let validPlist = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict>
        <key>Label</key><string>com.test.valid</string>
        <key>Program</key><string>/bin/echo</string>
    </dict></plist>
    """
    // 无效 plist（空 dict）
    let emptyPlist = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict/></plist>
    """
    let validURL = tmpDir.appendingPathComponent("com.test.valid.plist")
    let emptyURL = tmpDir.appendingPathComponent("com.test.empty.plist")
    try validPlist.write(to: validURL, atomically: true, encoding: .utf8)
    try emptyPlist.write(to: emptyURL, atomically: true, encoding: .utf8)

    // scanAll 只扫描 tmpDir，需要用 scanDirectory 辅助方法
    let (items, invalid) = svc.scanDirectory(tmpDir, scope: .userAgent)
    XCTAssertEqual(items.count, 1)
    XCTAssertEqual(items[0].label, "com.test.valid")
    XCTAssertEqual(invalid.count, 1)
    XCTAssertEqual(invalid[0].url, emptyURL)
    XCTAssertEqual(invalid[0].scope, .userAgent)
}
```

- [ ] **Step 2: 运行测试，确认失败**

```bash
cd /Users/sean/LaunchManager/LaunchManager
xcodebuild test -project LaunchManager.xcodeproj -scheme LaunchManager -destination 'platform=macOS' -only-testing:LaunchManagerTests/PlistServiceTests/test_parsePlist_emptyDict_returnsNil 2>&1 | grep -E "PASS|FAIL|error:"
```

预期：`test_parsePlist_emptyDict_returnsNil` 会 PASS（现有行为已支持），`test_scanAll_separatesInvalidItems` 会 FAIL（`scanDirectory` 未定义）。

- [ ] **Step 3: 创建 InvalidPlist 模型**

新建 `LaunchManager/Models/InvalidPlist.swift`：

```swift
import Foundation

struct InvalidPlist: Identifiable {
    var id: URL { url }
    let url: URL
    let scope: LaunchItem.Scope
}
```

- [ ] **Step 4: 更新 PlistService**

修改 `LaunchManager/Services/PlistService.swift`，将 `scanAll()` 拆分，提取可测试的 `scanDirectory`，并更新返回类型：

```swift
import Foundation

struct PlistService {

    func scanAll() -> (items: [LaunchItem], invalid: [InvalidPlist]) {
        var items: [LaunchItem] = []
        var invalid: [InvalidPlist] = []
        for scope in LaunchItem.Scope.allCases {
            let (scopeItems, scopeInvalid) = scanDirectory(scope.directoryURL, scope: scope)
            items.append(contentsOf: scopeItems)
            invalid.append(contentsOf: scopeInvalid)
        }
        return (items, invalid)
    }

    func scanDirectory(_ dir: URL, scope: LaunchItem.Scope) -> (items: [LaunchItem], invalid: [InvalidPlist]) {
        var items: [LaunchItem] = []
        var invalid: [InvalidPlist] = []
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ) else { return (items, invalid) }
        for url in contents where url.pathExtension == "plist" {
            if let item = parsePlist(at: url, scope: scope) {
                items.append(item)
            } else {
                invalid.append(InvalidPlist(url: url, scope: scope))
            }
        }
        return (items, invalid)
    }

    func parsePlist(at url: URL, scope: LaunchItem.Scope) -> LaunchItem? {
        guard let data = try? Data(contentsOf: url),
              let raw = try? PropertyListSerialization.propertyList(
                  from: data, options: [], format: nil),
              let dict = raw as? [String: Any],
              let label = dict["Label"] as? String
        else { return nil }

        var program = ""
        var programArguments: [String] = []
        if let args = dict["ProgramArguments"] as? [String], !args.isEmpty {
            program = args[0]
            programArguments = Array(args.dropFirst())
        } else if let prog = dict["Program"] as? String {
            program = prog
        }

        var triggerType: LaunchItem.TriggerType = .atLoad
        var calendarInterval: LaunchItem.CalendarInterval?
        var startInterval: Int?
        var watchPaths: [String] = []

        if let ci = dict["StartCalendarInterval"] as? [String: Int] {
            triggerType = .calendar
            calendarInterval = LaunchItem.CalendarInterval(
                weekday: ci["Weekday"],
                hour: ci["Hour"],
                minute: ci["Minute"] ?? 0
            )
        } else if let si = dict["StartInterval"] as? Int {
            triggerType = .interval
            startInterval = si
        } else if let wp = dict["WatchPaths"] as? [String] {
            triggerType = .watchPath
            watchPaths = wp
        }

        return LaunchItem(
            label: label, plistURL: url, scope: scope,
            program: program, programArguments: programArguments,
            triggerType: triggerType, calendarInterval: calendarInterval,
            startInterval: startInterval, watchPaths: watchPaths,
            runAtLoad: dict["RunAtLoad"] as? Bool ?? false,
            keepAlive: dict["KeepAlive"] as? Bool ?? false,
            standardOutPath: dict["StandardOutPath"] as? String,
            standardErrorPath: dict["StandardErrorPath"] as? String,
            isLoaded: false, pid: nil, lastExitCode: nil
        )
    }

    func toDictionary(_ item: LaunchItem) -> [String: Any] {
        var dict: [String: Any] = ["Label": item.label]
        if item.programArguments.isEmpty {
            dict["Program"] = item.program
        } else {
            dict["ProgramArguments"] = [item.program] + item.programArguments
        }
        switch item.triggerType {
        case .calendar:
            if let ci = item.calendarInterval {
                var d: [String: Int] = ["Minute": ci.minute]
                if let w = ci.weekday { d["Weekday"] = w }
                if let h = ci.hour    { d["Hour"] = h }
                dict["StartCalendarInterval"] = d
            }
        case .interval:
            if let si = item.startInterval { dict["StartInterval"] = si }
        case .watchPath:
            if !item.watchPaths.isEmpty { dict["WatchPaths"] = item.watchPaths }
        case .atLoad:
            break
        }
        if item.runAtLoad  { dict["RunAtLoad"]  = true }
        if item.keepAlive  { dict["KeepAlive"]  = true }
        if let o = item.standardOutPath   { dict["StandardOutPath"]   = o }
        if let e = item.standardErrorPath { dict["StandardErrorPath"] = e }
        return dict
    }

    func save(_ item: LaunchItem, privilege: PrivilegeService) throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: toDictionary(item), format: .xml, options: 0)
        if item.scope.requiresPrivilege {
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent(item.plistURL.lastPathComponent)
            try data.write(to: tmp)
            try privilege.run("mv \(tmp.path) \(item.plistURL.path)")
        } else {
            try data.write(to: item.plistURL)
        }
    }

    func delete(_ item: LaunchItem,
                launchctl: LaunchctlService,
                privilege: PrivilegeService) throws {
        try? launchctl.unload(item.plistURL, privileged: item.scope.requiresPrivilege)
        if item.scope.requiresPrivilege {
            try privilege.run("rm \(item.plistURL.path)")
        } else {
            try FileManager.default.removeItem(at: item.plistURL)
        }
    }
}
```

- [ ] **Step 5: 运行测试，确认全部通过**

```bash
cd /Users/sean/LaunchManager/LaunchManager
xcodebuild test -project LaunchManager.xcodeproj -scheme LaunchManager -destination 'platform=macOS' -only-testing:LaunchManagerTests/PlistServiceTests 2>&1 | grep -E "PASS|FAIL|error:|Test Suite"
```

预期：所有 PlistServiceTests 全部 PASS。

- [ ] **Step 6: Commit**

```bash
git add LaunchManager/Models/InvalidPlist.swift LaunchManager/Services/PlistService.swift LaunchManagerTests/LaunchManagerTests.swift
git commit -m "feat: add InvalidPlist model and update PlistService.scanAll to return invalid items"
```

---

### Task 2: 更新 AgentStore

**Files:**
- Modify: `LaunchManager/Store/AgentStore.swift`

- [ ] **Step 1: 替换 warnings，新增 invalidItems 和 deleteInvalid**

将 `LaunchManager/Store/AgentStore.swift` 完整替换为：

```swift
import Foundation

@MainActor
final class AgentStore: ObservableObject {
    @Published var items: [LaunchItem] = []
    @Published var invalidItems: [InvalidPlist] = []

    private let plistService     = PlistService()
    private let launchctlService = LaunchctlService()
    private let privilegeService = PrivilegeService()

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

    func load(_ item: LaunchItem) throws {
        try launchctlService.load(item.plistURL, privileged: item.scope.requiresPrivilege)
        refresh()
    }

    func unload(_ item: LaunchItem) throws {
        try launchctlService.unload(item.plistURL, privileged: item.scope.requiresPrivilege)
        refresh()
    }

    func start(_ item: LaunchItem) throws {
        try launchctlService.start(item.label, privileged: item.scope.requiresPrivilege)
        refresh()
    }

    func stop(_ item: LaunchItem) throws {
        try launchctlService.stop(item.label, privileged: item.scope.requiresPrivilege)
        refresh()
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
}
```

- [ ] **Step 2: 确认编译通过**

```bash
cd /Users/sean/LaunchManager/LaunchManager
xcodebuild build -project LaunchManager.xcodeproj -scheme LaunchManager -destination 'platform=macOS' 2>&1 | grep -E "error:|warning:|BUILD"
```

预期：`BUILD SUCCEEDED`（可能有 warnings，但无 errors）。

- [ ] **Step 3: Commit**

```bash
git add LaunchManager/Store/AgentStore.swift
git commit -m "feat: replace warnings with invalidItems in AgentStore, add deleteInvalid"
```

---

### Task 3: 新建 InvalidPlistRowView

**Files:**
- Create: `LaunchManager/Views/InvalidPlistRowView.swift`

- [ ] **Step 1: 创建视图文件**

新建 `LaunchManager/Views/InvalidPlistRowView.swift`：

```swift
import SwiftUI

struct InvalidPlistRowView: View {
    let item: InvalidPlist
    @ObservedObject var store: AgentStore
    @Binding var errorMessage: String?

    @State private var isExpanded = false
    @State private var showingDeleteConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(nsColor: .tertiaryLabelColor))
                    .frame(width: 8, height: 8)
                Text(item.url.lastPathComponent)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text("⚠️ 无法解析")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if isExpanded {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 8) {
                        Text("路径")
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .leading)
                        Text(item.url.path)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .font(.caption)
                    Text("此文件为空或格式无效，无法作为 launchd 条目加载。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
        )
        .confirmationDialog(
            "确认删除 \(item.url.lastPathComponent)？",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                do { try store.deleteInvalid(item) }
                catch { errorMessage = error.localizedDescription }
            }
        } message: {
            Text("此操作将永久删除该 plist 文件，无法撤销。")
        }
    }
}
```

- [ ] **Step 2: 确认编译通过**

```bash
cd /Users/sean/LaunchManager/LaunchManager
xcodebuild build -project LaunchManager.xcodeproj -scheme LaunchManager -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD"
```

预期：`BUILD SUCCEEDED`。

- [ ] **Step 3: Commit**

```bash
git add LaunchManager/Views/InvalidPlistRowView.swift
git commit -m "feat: add InvalidPlistRowView for inline display of unparseable plists"
```

---

### Task 4: 接线 AgentListView 和 ContentView

**Files:**
- Modify: `LaunchManager/Views/AgentListView.swift`
- Modify: `LaunchManager/ContentView.swift`

- [ ] **Step 1: 更新 AgentListView**

将 `LaunchManager/Views/AgentListView.swift` 完整替换为：

```swift
import SwiftUI

struct AgentListView: View {
    let items: [LaunchItem]
    let invalidItems: [InvalidPlist]
    @ObservedObject var store: AgentStore
    @Binding var showingNewAgent: Bool
    @Binding var errorMessage: String?

    var body: some View {
        Group {
            if items.isEmpty && invalidItems.isEmpty {
                ContentUnavailableView(
                    "没有 Agent",
                    systemImage: "tray",
                    description: Text("此分类下暂无 LaunchAgent / Daemon")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(items) { item in
                            AgentRowView(item: item, store: store, errorMessage: $errorMessage)
                        }
                        ForEach(invalidItems) { item in
                            InvalidPlistRowView(item: item, store: store, errorMessage: $errorMessage)
                        }
                    }
                    .padding()
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingNewAgent = true } label: {
                    Label("新建", systemImage: "plus")
                }
            }
            ToolbarItem {
                Button { store.refresh() } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
            }
        }
    }
}
```

- [ ] **Step 2: 更新 ContentView**

将 `LaunchManager/ContentView.swift` 完整替换为：

```swift
import SwiftUI

struct ContentView: View {
    @StateObject private var store = AgentStore()
    @State private var selectedScope: LaunchItem.Scope? = .userAgent
    @State private var showingNewAgent = false
    @State private var errorMessage: String?

    var filteredItems: [LaunchItem] {
        guard let scope = selectedScope else { return store.items }
        return store.items.filter { $0.scope == scope }
    }

    var filteredInvalidItems: [InvalidPlist] {
        guard let scope = selectedScope else { return store.invalidItems }
        return store.invalidItems.filter { $0.scope == scope }
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(selectedScope: $selectedScope, store: store)
        } detail: {
            AgentListView(
                items: filteredItems,
                invalidItems: filteredInvalidItems,
                store: store,
                showingNewAgent: $showingNewAgent,
                errorMessage: $errorMessage
            )
        }
        .onAppear { store.refresh() }
        .sheet(isPresented: $showingNewAgent) {
            EditAgentSheet(
                existingItem: nil,
                defaultScope: selectedScope ?? .userAgent,
                store: store
            )
        }
        .alert("错误", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("确定") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }
}
```

- [ ] **Step 3: 运行全部测试**

```bash
cd /Users/sean/LaunchManager/LaunchManager
xcodebuild test -project LaunchManager.xcodeproj -scheme LaunchManager -destination 'platform=macOS' 2>&1 | grep -E "PASS|FAIL|error:|Test Suite.*passed|Test Suite.*failed"
```

预期：所有测试 PASS，`BUILD SUCCEEDED`。

- [ ] **Step 4: Commit**

```bash
git add LaunchManager/Views/AgentListView.swift LaunchManager/ContentView.swift
git commit -m "feat: wire up invalid plist inline display, remove warning bar"
```
