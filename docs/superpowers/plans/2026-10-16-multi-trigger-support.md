# Multi-Trigger Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Support multiple launchd triggers at once (calendar × N, interval, watch paths) in parse/save, form editing, and list display; fold former “登录时” into `RunAtLoad`.

**Architecture:** Replace single `triggerType` with a set model (`calendarIntervals`, optional `startInterval`, `watchPaths`, `runAtLoad`). `PlistService` parses/writes all present keys independently; form uses three toggles; list uses `LaunchItem.triggerSummaryLines`.

**Tech Stack:** Swift 5.10, SwiftUI, XCTest, xcodebuild

**Spec:** `docs/superpowers/specs/2026-10-16-multi-trigger-support-design.md`

---

## File Map

| 操作 | 文件 | 职责 |
|------|------|------|
| Modify | `LaunchManager/Models/LaunchItem.swift` | 集合模型；删 `TriggerType`；加 `triggerSummaryLines` |
| Modify | `LaunchManager/Models/LaunchAgentDraft.swift` | 去掉 `triggerType` |
| Modify | `LaunchManager/Services/PlistService.swift` | 多触发解析/写入；多路径强制 XML；去掉多触发强制 XML |
| Modify | `LaunchManager/Views/EditAgentSheet.swift` | Toggle 多选 + 多日历行 |
| Modify | `LaunchManager/Views/AgentRowView.swift` | 多行触发摘要 |
| Modify | `LaunchManagerTests/LaunchManagerTests.swift` | 新测试 + 全量 API 迁移 |

---

### Task 1: LaunchItem 集合模型 + triggerSummaryLines

**Files:**
- Modify: `LaunchManager/Models/LaunchItem.swift`
- Modify: `LaunchManager/Models/LaunchAgentDraft.swift`
- Modify: `LaunchManagerTests/LaunchManagerTests.swift`（先改构造调用使工程可编译的测试会在 Task 2–4 补全；本任务只改模型与 draft，随后立刻改所有 `LaunchItem(` / `triggerType` 引用以免卡住）

- [ ] **Step 1: 改 `LaunchItem` 字段**

将 `LaunchManager/Models/LaunchItem.swift` 顶部属性中：

```swift
    var triggerType: TriggerType
    var calendarInterval: CalendarInterval?
```

替换为：

```swift
    var calendarIntervals: [CalendarInterval]
```

删除整个 `enum TriggerType`（约原 93–107 行）。

在 `CalendarInterval` 结构体之后追加：

```swift
    /// 列表/详情用的触发摘要行（固定顺序）。
    var triggerSummaryLines: [String] {
        var lines: [String] = []
        for ci in calendarIntervals {
            let day = ci.weekday.map { String(localized: "周\($0)") }
                ?? String(localized: "每天")
            let h = ci.hour.map { String(format: "%02d", $0) } ?? "**"
            lines.append("\(day) \(h):\(String(format: "%02d", ci.minute))")
        }
        if let si = startInterval {
            lines.append(String(localized: "每 \(si) 秒"))
        }
        for path in watchPaths {
            lines.append(String(localized: "监视路径：\(path)"))
        }
        if runAtLoad {
            lines.append(String(localized: "加载时运行"))
        }
        if lines.isEmpty {
            lines.append(String(localized: "无自动触发"))
        }
        return lines
    }
```

- [ ] **Step 2: 改 `LaunchAgentDraft`**

`LaunchManager/Models/LaunchAgentDraft.swift`：删除 `var triggerType: LaunchItem.TriggerType`，并删除 `from(service:)` 里的 `triggerType: .atLoad` 参数。

- [ ] **Step 3: 批量更新仓库内所有 `LaunchItem(` 调用与 `triggerType` / `calendarInterval` 引用**

规则：

- `triggerType: .atLoad, calendarInterval: nil` → `calendarIntervals: []`
- `triggerType: .calendar, calendarInterval: X` → `calendarIntervals: [X]`（若 `X` 非可选）或 `calendarIntervals: X.map { [$0] } ?? []`
- `triggerType: .interval` → `calendarIntervals: []`，保留 `startInterval`
- `triggerType: .watchPath` → `calendarIntervals: []`，保留 `watchPaths`
- 断言 `item?.triggerType == .calendar` → `XCTAssertEqual(item?.calendarIntervals.count, 1)` 等
- `draft?.triggerType` 断言删除，改为确认 `runAtLoad == true`（已有）

涉及文件：`PlistService.swift`、`EditAgentSheet.swift`、`AgentRowView.swift`、`LaunchManagerTests.swift`。本步可先用占位实现让编译通过（例如 `PlistService` 仍只读第一个触发），完整行为在后续 Task 实现。

最小可编译的 `PlistService.parsePlist` 触发段：

```swift
        var calendarIntervals: [LaunchItem.CalendarInterval] = []
        var startInterval: Int?
        var watchPaths: [String] = []

        if let ci = dict["StartCalendarInterval"] as? [String: Int] {
            calendarIntervals = [
                LaunchItem.CalendarInterval(
                    weekday: ci["Weekday"],
                    hour: ci["Hour"],
                    minute: ci["Minute"] ?? 0
                )
            ]
        } else if let si = dict["StartInterval"] as? Int {
            startInterval = si
        } else if let wp = dict["WatchPaths"] as? [String] {
            watchPaths = wp
        }

        return LaunchItem(
            label: label, plistURL: url, scope: scope,
            program: program, programArguments: programArguments,
            calendarIntervals: calendarIntervals,
            startInterval: startInterval, watchPaths: watchPaths,
            runAtLoad: dict["RunAtLoad"] as? Bool ?? false,
            keepAlive: dict["KeepAlive"] as? Bool ?? false,
            standardOutPath: dict["StandardOutPath"] as? String,
            standardErrorPath: dict["StandardErrorPath"] as? String,
            workingDirectory: dict["WorkingDirectory"] as? String,
            environmentVariables: parseEnvironmentVariables(dict["EnvironmentVariables"]),
            isLoaded: false, isDisabledByOverride: false, pid: nil, lastExitCode: nil
        )
```

最小可编译的 `toDictionary` 触发段：

```swift
        if item.calendarIntervals.count == 1, let ci = item.calendarIntervals.first {
            var d: [String: Int] = ["Minute": ci.minute]
            if let w = ci.weekday { d["Weekday"] = w }
            if let h = ci.hour { d["Hour"] = h }
            dict["StartCalendarInterval"] = d
        } else if item.calendarIntervals.count >= 2 {
            dict["StartCalendarInterval"] = item.calendarIntervals.map { ci -> [String: Int] in
                var d: [String: Int] = ["Minute": ci.minute]
                if let w = ci.weekday { d["Weekday"] = w }
                if let h = ci.hour { d["Hour"] = h }
                return d
            }
        }
        if let si = item.startInterval { dict["StartInterval"] = si }
        if !item.watchPaths.isEmpty { dict["WatchPaths"] = item.watchPaths }
```

`AgentRowView.triggerDescription` 临时改为：

```swift
    private var triggerDescription: String {
        item.triggerSummaryLines.joined(separator: "\n")
    }
```

`EditAgentSheet`：本步引入 Task 4 同名的 `@State`（`useCalendar` / `calendarRows` / `useInterval` / `useWatchPath` / `watchPath`），表单 Section 可先只绑定这些字段的最小 UI（例如三个 Toggle + 旧的单行日历控件），完整多日历 UI 在 Task 4 替换。

- [ ] **Step 4: 编译确认**

```bash
cd /Users/sean/LaunchManager/LaunchManager
xcodebuild build -project LaunchManager.xcodeproj -scheme LaunchManager -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```

预期：`BUILD SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add LaunchManager/Models/LaunchItem.swift LaunchManager/Models/LaunchAgentDraft.swift \
  LaunchManager/Services/PlistService.swift LaunchManager/Views/EditAgentSheet.swift \
  LaunchManager/Views/AgentRowView.swift LaunchManagerTests/LaunchManagerTests.swift
git commit -m "$(cat <<'EOF'
refactor: replace single triggerType with trigger set model

EOF
)"
```

---

### Task 2: PlistService 多触发解析 / 写入 / 表单兼容

**Files:**
- Modify: `LaunchManager/Services/PlistService.swift`
- Modify: `LaunchManagerTests/LaunchManagerTests.swift`

- [ ] **Step 1: 写失败测试**

在 `PlistServiceTests` 中追加：

```swift
    func test_parsePlist_multipleTriggers() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
            <key>Label</key><string>com.test.multi</string>
            <key>Program</key><string>/bin/echo</string>
            <key>StartCalendarInterval</key>
            <dict><key>Hour</key><integer>8</integer><key>Minute</key><integer>0</integer></dict>
            <key>StartInterval</key><integer>300</integer>
            <key>WatchPaths</key>
            <array><string>/tmp/watch</string></array>
            <key>RunAtLoad</key><true/>
        </dict></plist>
        """
        let url = tmpDir.appendingPathComponent("com.test.multi.plist")
        try plist.write(to: url, atomically: true, encoding: .utf8)
        let item = svc.parsePlist(at: url, scope: .userAgent)
        XCTAssertEqual(item?.calendarIntervals.count, 1)
        XCTAssertEqual(item?.calendarIntervals.first?.hour, 8)
        XCTAssertEqual(item?.startInterval, 300)
        XCTAssertEqual(item?.watchPaths, ["/tmp/watch"])
        XCTAssertEqual(item?.runAtLoad, true)
    }

    func test_parsePlist_calendarIntervalArray() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
            <key>Label</key><string>com.test.calarray</string>
            <key>Program</key><string>/bin/echo</string>
            <key>StartCalendarInterval</key>
            <array>
                <dict><key>Weekday</key><integer>1</integer><key>Hour</key><integer>8</integer><key>Minute</key><integer>0</integer></dict>
                <dict><key>Weekday</key><integer>5</integer><key>Hour</key><integer>18</integer><key>Minute</key><integer>30</integer></dict>
            </array>
        </dict></plist>
        """
        let url = tmpDir.appendingPathComponent("com.test.calarray.plist")
        try plist.write(to: url, atomically: true, encoding: .utf8)
        let item = svc.parsePlist(at: url, scope: .userAgent)
        XCTAssertEqual(item?.calendarIntervals.count, 2)
        XCTAssertEqual(item?.calendarIntervals[0].weekday, 1)
        XCTAssertEqual(item?.calendarIntervals[0].hour, 8)
        XCTAssertEqual(item?.calendarIntervals[1].weekday, 5)
        XCTAssertEqual(item?.calendarIntervals[1].minute, 30)
    }

    func test_toDictionary_multipleCalendars_writesArray() {
        let item = LaunchItem(
            label: "com.test.calout",
            plistURL: tmpDir.appendingPathComponent("com.test.calout.plist"),
            scope: .userAgent,
            program: "/bin/echo",
            programArguments: [],
            calendarIntervals: [
                .init(weekday: 1, hour: 8, minute: 0),
                .init(weekday: nil, hour: 12, minute: 15),
            ],
            startInterval: 60,
            watchPaths: ["/tmp/a"],
            runAtLoad: false,
            keepAlive: false,
            standardOutPath: nil,
            standardErrorPath: nil,
            workingDirectory: nil,
            isLoaded: false,
            pid: nil,
            lastExitCode: nil
        )
        let dict = svc.toDictionary(item)
        let cal = dict["StartCalendarInterval"] as? [[String: Int]]
        XCTAssertEqual(cal?.count, 2)
        XCTAssertEqual(dict["StartInterval"] as? Int, 60)
        XCTAssertEqual(dict["WatchPaths"] as? [String], ["/tmp/a"])
    }

    func test_formIncompatibility_allowsMultipleTriggerTypes() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
            <key>Label</key><string>com.test.okmulti</string>
            <key>Program</key><string>/bin/echo</string>
            <key>StartInterval</key><integer>10</integer>
            <key>WatchPaths</key><array><string>/tmp/x</string></array>
        </dict></plist>
        """
        let url = tmpDir.appendingPathComponent("com.test.okmulti.plist")
        try plist.write(to: url, atomically: true, encoding: .utf8)
        let dict = try svc.readDictionary(from: url)
        XCTAssertNil(svc.formIncompatibilityReason(for: dict))
    }

    func test_formIncompatibility_multipleWatchPaths() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
            <key>Label</key><string>com.test.multipath</string>
            <key>Program</key><string>/bin/echo</string>
            <key>WatchPaths</key>
            <array><string>/tmp/a</string><string>/tmp/b</string></array>
        </dict></plist>
        """
        let url = tmpDir.appendingPathComponent("com.test.multipath.plist")
        try plist.write(to: url, atomically: true, encoding: .utf8)
        let dict = try svc.readDictionary(from: url)
        let reason = svc.formIncompatibilityReason(for: dict)
        XCTAssertNotNil(reason)
        XCTAssertTrue(reason?.contains("WatchPaths") == true || reason?.contains("路径") == true)
    }

    func test_triggerSummaryLines_order() {
        let item = LaunchItem(
            label: "com.test.summary",
            plistURL: URL(fileURLWithPath: "/tmp/x.plist"),
            scope: .userAgent,
            program: "/bin/echo",
            programArguments: [],
            calendarIntervals: [.init(weekday: nil, hour: 8, minute: 0)],
            startInterval: 300,
            watchPaths: ["/tmp/w"],
            runAtLoad: true,
            keepAlive: false,
            standardOutPath: nil,
            standardErrorPath: nil,
            workingDirectory: nil,
            isLoaded: false,
            pid: nil,
            lastExitCode: nil
        )
        let lines = item.triggerSummaryLines
        XCTAssertEqual(lines.count, 4)
        XCTAssertTrue(lines[0].contains("08:00"))
        XCTAssertTrue(lines[1].contains("300"))
        XCTAssertTrue(lines[2].contains("/tmp/w"))
        XCTAssertEqual(lines[3], String(localized: "加载时运行"))
    }
```

同时把既有测试里对 `triggerType` / 单 `calendarInterval` 的断言改成新字段（若 Task 1 未改完）。

- [ ] **Step 2: 运行新测试，确认失败**

```bash
cd /Users/sean/LaunchManager/LaunchManager
xcodebuild test -project LaunchManager.xcodeproj -scheme LaunchManager -destination 'platform=macOS' \
  -only-testing:LaunchManagerTests/PlistServiceTests/test_parsePlist_multipleTriggers \
  -only-testing:LaunchManagerTests/PlistServiceTests/test_parsePlist_calendarIntervalArray \
  -only-testing:LaunchManagerTests/PlistServiceTests/test_formIncompatibility_multipleWatchPaths \
  2>&1 | grep -E "passed|failed|error:"
```

预期：`test_parsePlist_multipleTriggers` 或 array 测试 **failed**（旧 if/else 只取日历）；`multipleWatchPaths` 可能 failed（尚未检查多路径）。

- [ ] **Step 3: 实现解析辅助与完整 parse/write/compat**

在 `PlistService` 中新增私有/内部辅助（可 `fileprivate` 或内部方法）：

```swift
    func parseCalendarIntervals(from value: Any?) -> [LaunchItem.CalendarInterval] {
        if let dict = value as? [String: Any] {
            return [calendarInterval(from: dict)].compactMap { $0 }
        }
        if let dict = value as? [String: Int] {
            return [
                LaunchItem.CalendarInterval(
                    weekday: dict["Weekday"],
                    hour: dict["Hour"],
                    minute: dict["Minute"] ?? 0
                )
            ]
        }
        if let array = value as? [Any] {
            return array.compactMap { el -> LaunchItem.CalendarInterval? in
                if let d = el as? [String: Any] { return calendarInterval(from: d) }
                if let d = el as? [String: Int] {
                    return LaunchItem.CalendarInterval(
                        weekday: d["Weekday"], hour: d["Hour"], minute: d["Minute"] ?? 0
                    )
                }
                return nil
            }
        }
        return []
    }

    private func calendarInterval(from dict: [String: Any]) -> LaunchItem.CalendarInterval? {
        func intVal(_ any: Any?) -> Int? {
            if let i = any as? Int { return i }
            if let n = any as? NSNumber { return n.intValue }
            return nil
        }
        // 任意 dict 都接受（launchd 允许空日历字典）
        return LaunchItem.CalendarInterval(
            weekday: intVal(dict["Weekday"]),
            hour: intVal(dict["Hour"]),
            minute: intVal(dict["Minute"]) ?? 0
        )
    }
```

`parsePlist` 触发段改为（互不排斥）：

```swift
        let calendarIntervals = parseCalendarIntervals(from: dict["StartCalendarInterval"])
        let startInterval = dict["StartInterval"] as? Int
            ?? (dict["StartInterval"] as? NSNumber)?.intValue
        let watchPaths = dict["WatchPaths"] as? [String] ?? []
```

`toDictionary`：按 File Map Task 1 中的多日历逻辑；`startInterval` / `watchPaths` 有值即写（不再依赖 triggerType）。

`formIncompatibilityReason`：删除 `triggers > 1` 块；在 unknown keys / KeepAlive 检查之后加入：

```swift
        if let wp = dict["WatchPaths"] as? [Any], wp.count > 1 {
            return String(localized: "WatchPaths 包含多条路径，请使用 XML 模式编辑。")
        }
```

- [ ] **Step 4: 跑相关测试至通过**

```bash
xcodebuild test -project LaunchManager.xcodeproj -scheme LaunchManager -destination 'platform=macOS' \
  -only-testing:LaunchManagerTests/PlistServiceTests 2>&1 | grep -E "Test Case|passed|failed|BUILD"
```

预期：全部 `passed`

- [ ] **Step 5: Commit**

```bash
git add LaunchManager/Services/PlistService.swift LaunchManagerTests/LaunchManagerTests.swift
git commit -m "$(cat <<'EOF'
feat: parse and write multiple launchd triggers

EOF
)"
```

---

### Task 3: AgentRowView 多行触发展示

**Files:**
- Modify: `LaunchManager/Views/AgentRowView.swift`

- [ ] **Step 1: 使用 `triggerSummaryLines`**

将 `detailRow("触发", triggerDescription)` 保持，但确保 `triggerDescription` 为：

```swift
    private var triggerDescription: String {
        item.triggerSummaryLines.joined(separator: "\n")
    }
```

删除旧的 `switch item.triggerType` 实现（若仍存在）。

确认 `detailRow` 内的 `Text(value)` 可多行（SwiftUI `Text` 默认支持 `\n`）。无需改 `detailRow` 签名。

- [ ] **Step 2: 编译**

```bash
xcodebuild build -project LaunchManager.xcodeproj -scheme LaunchManager -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```

- [ ] **Step 3: Commit**

```bash
git add LaunchManager/Views/AgentRowView.swift
git commit -m "$(cat <<'EOF'
feat: show multi-line trigger summary in agent rows

EOF
)"
```

---

### Task 4: EditAgentSheet 多选触发表单

**Files:**
- Modify: `LaunchManager/Views/EditAgentSheet.swift`

- [ ] **Step 1: 替换触发相关 @State**

删除：

```swift
    @State private var triggerType: LaunchItem.TriggerType
    @State private var weekday: Int?
    @State private var hour: Int
    @State private var minute: Int
```

改为：

```swift
    @State private var useCalendar: Bool
    @State private var calendarRows: [CalendarFormRow]
    @State private var useInterval: Bool
    @State private var startInterval: Int
    @State private var useWatchPath: Bool
    @State private var watchPath: String
```

在文件末尾（`EnvVarRow` 旁）新增：

```swift
private struct CalendarFormRow: Identifiable, Equatable {
    let id: UUID
    var weekday: Int?
    var hour: Int
    var minute: Int

    init(
        id: UUID = UUID(),
        weekday: Int? = nil,
        hour: Int = 8,
        minute: Int = 0
    ) {
        self.id = id
        self.weekday = weekday
        self.hour = hour
        self.minute = minute
    }

    init(from interval: LaunchItem.CalendarInterval) {
        self.init(
            weekday: interval.weekday,
            hour: interval.hour ?? 8,
            minute: interval.minute
        )
    }

    var asInterval: LaunchItem.CalendarInterval {
        LaunchItem.CalendarInterval(weekday: weekday, hour: hour, minute: minute)
    }
}
```

`init` 中初始化（draft 无触发字段；仅 `existingItem` 预填触发）：

```swift
        let sourceIntervals = i?.calendarIntervals ?? []
        _useCalendar = State(initialValue: !sourceIntervals.isEmpty)
        _calendarRows = State(initialValue: sourceIntervals.map { CalendarFormRow(from: $0) })
        _useInterval = State(initialValue: i?.startInterval != nil)
        _startInterval = State(initialValue: i?.startInterval ?? 60)
        _useWatchPath = State(initialValue: !(i?.watchPaths.isEmpty ?? true))
        _watchPath = State(initialValue: i?.watchPaths.first ?? "")
```

新建（无 `existingItem`）时三个触发 Toggle 均为 false；`runAtLoad` / `keepAlive` 仍从 draft 读取。

- [ ] **Step 2: 重写「触发方式」Section**

```swift
            Section("触发方式") {
                Toggle("定时", isOn: $useCalendar)
                    .onChange(of: useCalendar) { _, on in
                        if on, calendarRows.isEmpty {
                            calendarRows = [CalendarFormRow()]
                        }
                        if !on { calendarRows = [] }
                    }
                if useCalendar {
                    ForEach($calendarRows) { $row in
                        HStack {
                            Text("星期")
                            Picker("", selection: $row.weekday) {
                                Text("每天").tag(Int?.none)
                                ForEach(1...7, id: \.self) { d in
                                    Text(["", "周一", "周二", "周三", "周四", "周五", "周六", "周日"][d])
                                        .tag(Int?.some(d))
                                }
                            }
                            .frame(width: 80)
                            Spacer()
                            Text("时间")
                            TextField("时", value: $row.hour, format: .number).frame(width: 44)
                            Text(":")
                            TextField("分", value: $row.minute, format: .number).frame(width: 44)
                            if calendarRows.count > 1 {
                                Button {
                                    calendarRows.removeAll { $0.id == row.id }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                    Button {
                        calendarRows.append(CalendarFormRow())
                    } label: {
                        Label("添加时段", systemImage: "plus")
                    }
                }

                Toggle("间隔", isOn: $useInterval)
                if useInterval {
                    HStack {
                        Text("每隔")
                        TextField("秒", value: $startInterval, format: .number).frame(width: 80)
                        Text("秒执行一次")
                    }
                }

                Toggle("监视路径", isOn: $useWatchPath)
                if useWatchPath {
                    TextField("监视路径", text: $watchPath)
                }
            }
```

选项区 Toggle 文案保持「加载时自动运行」（不要写「登录时」）。

- [ ] **Step 3: 更新 `formLaunchItem` / `applyFormFields` / `parseLaunchItem`**

`formLaunchItem()`：

```swift
            calendarIntervals: useCalendar ? calendarRows.map(\.asInterval) : [],
            startInterval: useInterval ? startInterval : nil,
            watchPaths: useWatchPath
                ? (watchPath.trimmingCharacters(in: .whitespaces).isEmpty ? [] : [watchPath])
                : [],
```

`applyFormFields(from:)`：

```swift
        useCalendar = !item.calendarIntervals.isEmpty
        calendarRows = item.calendarIntervals.map { CalendarFormRow(from: $0) }
        useInterval = item.startInterval != nil
        startInterval = item.startInterval ?? 60
        useWatchPath = !item.watchPaths.isEmpty
        watchPath = item.watchPaths.first ?? ""
```

`parseLaunchItem(from:)`：删除 `triggerType`；使用：

```swift
        let calendarIntervals = plistService.parseCalendarIntervals(from: dict["StartCalendarInterval"])
        let startInterval = dict["StartInterval"] as? Int
            ?? (dict["StartInterval"] as? NSNumber)?.intValue
        let watchPaths = dict["WatchPaths"] as? [String] ?? []
```

因此 `parseCalendarIntervals` 必须是 `PlistService` 的内部可见方法（非 `private`，用默认 internal）。

- [ ] **Step 4: 编译**

```bash
xcodebuild build -project LaunchManager.xcodeproj -scheme LaunchManager -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```

预期：`BUILD SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add LaunchManager/Views/EditAgentSheet.swift LaunchManager/Services/PlistService.swift
git commit -m "$(cat <<'EOF'
feat: multi-select triggers in agent form editor

EOF
)"
```

---

### Task 5: 全量回归 + 文档勾选

**Files:**
- Modify: `LaunchManagerTests/LaunchManagerTests.swift`（若仍有旧 API）
- Modify: `docs/superpowers/plans/2026-10-16-multi-trigger-support.md`（勾选完成项，可选）

- [x] **Step 1: 跑全部单元测试**

```bash
cd /Users/sean/LaunchManager/LaunchManager
xcodebuild test -project LaunchManager.xcodeproj -scheme LaunchManager -destination 'platform=macOS' \
  -only-testing:LaunchManagerTests 2>&1 | grep -E "Test Suite|passed|failed|error:|BUILD"
```

预期：`TEST SUCCEEDED`，无 failed。

- [x] **Step 2: 手动冒烟清单（实现者勾选）**

- [x] 新建 Agent：只勾 RunAtLoad → plist 仅有 `RunAtLoad`（单元测试 `test_toDictionary_runAtLoadOnly_omitsStartKeys`；GUI 新建流程需人工）
- [x] 勾定时两条 + 间隔 → XML 中日历为 array，且有 `StartInterval`（`test_toDictionary_multipleCalendars_writesArray`）
- [ ] 打开含多触发的现有 plist → 表单可用且字段填满（需人工 GUI）
- [x] 含 2 条 WatchPaths 的 plist → 提示 XML（`test_formIncompatibility_multipleWatchPaths`）
- [x] 列表展开行显示多行触发（`test_triggerSummaryLines_order`；列表 UI 渲染需人工）

- [x] **Step 3: 最终 commit（若有测试/小修）**

```bash
git add -A
git status
git commit -m "$(cat <<'EOF'
test: cover multi-trigger parse, form compat, and summaries

EOF
)"
```

（若工作区无变更则跳过 commit。）

---

## Spec Coverage Checklist

| Spec 要求 | Task |
|-----------|------|
| 集合模型，删 `triggerType` / `.atLoad` | Task 1 |
| 解析多类型 + 日历 array | Task 2 |
| 写入单 dict / 多 array | Task 2 |
| 去掉多触发强制 XML | Task 2 |
| 多 WatchPaths → XML | Task 2 |
| 表单三 Toggle + 多日历 | Task 4 |
| RunAtLoad 文案、无「登录时」类型 | Task 4 |
| 列表多行摘要 | Task 1 (`triggerSummaryLines`) + Task 3 |
| 测试计划条目 | Task 2 + Task 5 |

## Out of Scope (do not implement)

- 表单多路径 WatchPaths 编辑器
- `QueueDirectories` / `StartOnMount` / `Sockets`
- bootstrap / kickstart 行为变更
