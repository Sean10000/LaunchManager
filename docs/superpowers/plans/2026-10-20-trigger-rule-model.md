# Trigger Rule Model Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Toggle-based trigger editing with a `[TriggerRule]` projection over a preserved plist root document, so presets are editable without inventing fields or breaking round-trips.

**Architecture:** Keep the on-disk plist dictionary as the source of truth. `NativeTriggers` parses calendar entries / interval / watch paths with diagnostics. `TriggerCompiler` projects `TriggerRule`s (with `sourceRefs`) for UI. Saves apply a change set onto the root snapshot—never rebuild the whole plist from rules. Unknown keys stay on the root and remain visible as passthrough.

**Tech Stack:** Swift 5.10, SwiftUI, XCTest, xcodebuild

**Spec:** `docs/superpowers/specs/2026-10-20-trigger-rule-model-design.md`

---

## File Map

| 操作 | 文件 | 职责 |
|------|------|------|
| Create | `LaunchManager/Models/TriggerModels.swift` | `ParseIssue`, `CalendarEntry`, `NativeTriggers`, `SourceRef`, `TriggerRule` |
| Create | `LaunchManager/Services/TriggerCompiler.swift` | Parse entries, recognize presets, project rules, compile edited presets |
| Create | `LaunchManager/Services/TriggerDocumentSession.swift` | Root snapshot, dirty detection, apply change set, external-change check |
| Modify | `LaunchManager/Services/PlistService.swift` | Stop defaulting `Minute`; drop multi-WatchPaths XML force; save via session when editing |
| Modify | `LaunchManager/Models/LaunchItem.swift` | Summary lines from projection; keep derived convenience fields |
| Modify | `LaunchManager/Views/EditAgentSheet.swift` | Rule list UI; remove Toggle / every-N-months interval-as-calendar hacks |
| Modify | `LaunchManager/Views/AgentRowView.swift` | Only if summary API changes |
| Modify | `LaunchManager/Localizable.xcstrings` | New copy (independent rules, RunAtLoad, WatchPaths caveats, …) |
| Modify | `LaunchManagerTests/LaunchManagerTests.swift` | Compiler + session + regression |

Xcode uses `PBXFileSystemSynchronizedRootGroup` — new files under `LaunchManager/` / `LaunchManagerTests/` are picked up automatically.

---

### Task 1: TriggerModels + CalendarEntry parse (no Minute default)

**Files:**
- Create: `LaunchManager/Models/TriggerModels.swift`
- Create: `LaunchManagerTests/TriggerCompilerTests.swift` (test target auto-sync)
- Modify: `LaunchManager/Services/PlistService.swift` (only if needed later; this task stays in new types)

- [ ] **Step 1: Write failing tests for entry parse**

Create `LaunchManagerTests/TriggerCompilerTests.swift`:

```swift
import XCTest
@testable import LaunchManager

final class TriggerCompilerTests: XCTestCase {
    func test_parseEntry_missingMinute_staysNil() {
        let entry = TriggerCompiler.parseEntry(["Hour": 9])
        XCTAssertEqual(entry.hour, 9)
        XCTAssertNil(entry.minute)
        XCTAssertTrue(entry.diagnostics.isEmpty)
        XCTAssertEqual(entry.raw["Hour"] as? Int, 9)
        XCTAssertNil(entry.raw["Minute"])
    }

    func test_parseEntry_invalidHour_isDiagnostic() {
        let entry = TriggerCompiler.parseEntry(["Hour": "9", "Minute": 0])
        XCTAssertNil(entry.hour)
        XCTAssertEqual(entry.minute, 0)
        XCTAssertFalse(entry.diagnostics.isEmpty)
    }

    func test_parseEntry_outOfRangeHour_isDiagnostic() {
        let entry = TriggerCompiler.parseEntry(["Hour": 99, "Minute": 0])
        XCTAssertNil(entry.hour)
        XCTAssertFalse(entry.diagnostics.isEmpty)
    }
}
```

- [ ] **Step 2: Run tests — expect FAIL (types missing)**

```bash
xcodebuild test -project LaunchManager.xcodeproj -scheme LaunchManager -destination 'platform=macOS' \
  -only-testing:LaunchManagerTests/TriggerCompilerTests 2>&1 | grep -E "error:|FAIL|PASS|BUILD"
```

Expected: compile error / FAIL — `TriggerCompiler` undefined.

- [ ] **Step 3: Add models + minimal parse**

Create `LaunchManager/Models/TriggerModels.swift`:

```swift
import Foundation

enum ParseIssue: Hashable, Equatable {
    case invalidType(key: String, expected: String)
    case outOfRange(key: String, value: Int)
    case unknownKey(String)
}

struct CalendarEntry: Equatable {
    var weekday: Int?
    var month: Int?
    var day: Int?
    var hour: Int?
    var minute: Int?
    var raw: [String: Any]
    var diagnostics: [ParseIssue]
    var sessionId: UUID

    static func == (lhs: CalendarEntry, rhs: CalendarEntry) -> Bool {
        lhs.sessionId == rhs.sessionId
            && lhs.weekday == rhs.weekday
            && lhs.month == rhs.month
            && lhs.day == rhs.day
            && lhs.hour == rhs.hour
            && lhs.minute == rhs.minute
            && lhs.diagnostics == rhs.diagnostics
            && NSDictionary(dictionary: lhs.raw).isEqual(to: rhs.raw)
    }
}

struct NativeTriggers: Equatable {
    var calendarEntries: [CalendarEntry]
    var startInterval: Int?
    var startIntervalIssue: ParseIssue?
    var watchPaths: [String]
    /// Presence of key vs empty — derived at parse from root, not inventing persistence.
    var calendarKeyPresent: Bool
    var calendarIsArray: Bool
    var watchPathsKeyPresent: Bool
}

enum SourceRef: Hashable {
    case calendarEntry(UUID)
    case watchPath(UUID)
    case startInterval
}

enum TriggerRuleKind: Equatable {
    case daily(hour: Int, minute: Int)
    case weekly(weekdays: [Int], hour: Int, minute: Int) // launchd Weekday values
    case monthly(day: Int, hour: Int, minute: Int, months: Set<Int>?) // nil = all months
    case yearly(month: Int, day: Int, hour: Int, minute: Int)
    case interval(seconds: Int)
    case watchPath(String)
    case customCalendar(summary: String, isMalformed: Bool)
}

struct TriggerRule: Identifiable, Equatable {
    var id: UUID
    var kind: TriggerRuleKind
    var sourceRefs: [SourceRef]
    var isModified: Bool
}
```

Create `LaunchManager/Services/TriggerCompiler.swift` with parse helpers only:

```swift
import Foundation

enum TriggerCompiler {
    static let knownCalendarKeys: Set<String> = [
        "Weekday", "Month", "Day", "Hour", "Minute"
    ]

    static func parseEntry(_ dict: [String: Any], sessionId: UUID = UUID()) -> CalendarEntry {
        var diagnostics: [ParseIssue] = []
        for key in dict.keys where !knownCalendarKeys.contains(key) {
            diagnostics.append(.unknownKey(key))
        }

        func parseInt(_ key: String, range: ClosedRange<Int>) -> Int? {
            guard let any = dict[key] else { return nil }
            let value: Int?
            if let i = any as? Int { value = i }
            else if let n = any as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() {
                value = n.intValue
            } else {
                diagnostics.append(.invalidType(key: key, expected: "Int"))
                return nil
            }
            guard let value else { return nil }
            guard range.contains(value) else {
                diagnostics.append(.outOfRange(key: key, value: value))
                return nil
            }
            return value
        }

        return CalendarEntry(
            weekday: parseInt("Weekday", range: 0...7),
            month: parseInt("Month", range: 1...12),
            day: parseInt("Day", range: 1...31),
            hour: parseInt("Hour", range: 0...23),
            minute: parseInt("Minute", range: 0...59),
            raw: dict,
            diagnostics: diagnostics,
            sessionId: sessionId
        )
    }

    static func parseNative(from root: [String: Any]) -> NativeTriggers {
        var entries: [CalendarEntry] = []
        var calendarKeyPresent = false
        var calendarIsArray = false
        if let value = root["StartCalendarInterval"] {
            calendarKeyPresent = true
            if let dict = value as? [String: Any] {
                entries = [parseEntry(dict)]
            } else if let array = value as? [Any] {
                calendarIsArray = true
                entries = array.compactMap { el in
                    guard let d = el as? [String: Any] else { return nil }
                    return parseEntry(d)
                }
            }
        }

        var startInterval: Int?
        var startIntervalIssue: ParseIssue?
        if let any = root["StartInterval"] {
            if let i = any as? Int { startInterval = i }
            else if let n = any as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() {
                startInterval = n.intValue
            } else {
                startIntervalIssue = .invalidType(key: "StartInterval", expected: "Int")
            }
        }

        let watchPathsKeyPresent = root["WatchPaths"] != nil
        let watchPaths = root["WatchPaths"] as? [String] ?? []

        return NativeTriggers(
            calendarEntries: entries,
            startInterval: startInterval,
            startIntervalIssue: startIntervalIssue,
            watchPaths: watchPaths,
            calendarKeyPresent: calendarKeyPresent,
            calendarIsArray: calendarIsArray,
            watchPathsKeyPresent: watchPathsKeyPresent
        )
    }
}
```

- [ ] **Step 4: Run tests — expect PASS**

```bash
xcodebuild test -project LaunchManager.xcodeproj -scheme LaunchManager -destination 'platform=macOS' \
  -only-testing:LaunchManagerTests/TriggerCompilerTests 2>&1 | grep -E "Test Case|passed|failed|error:"
```

- [ ] **Step 5: Commit**

```bash
git add LaunchManager/Models/TriggerModels.swift LaunchManager/Services/TriggerCompiler.swift \
  LaunchManagerTests/TriggerCompilerTests.swift
git commit -m "feat: add CalendarEntry parse without inventing Minute"
```

---

### Task 2: Preset recognition + rule projection (with sourceRefs)

**Files:**
- Modify: `LaunchManager/Services/TriggerCompiler.swift`
- Modify: `LaunchManagerTests/TriggerCompilerTests.swift`

- [ ] **Step 1: Write failing projection tests**

```swift
func test_project_hourMinute_isDaily() {
    let native = TriggerCompiler.parseNative(from: [
        "StartCalendarInterval": ["Hour": 9, "Minute": 0]
    ])
    let rules = TriggerCompiler.project(native)
    guard case .daily(let h, let m) = rules[0].kind else {
        return XCTFail("expected daily")
    }
    XCTAssertEqual(h, 9)
    XCTAssertEqual(m, 0)
    XCTAssertEqual(rules[0].sourceRefs.count, 1)
}

func test_project_hourOnly_isCustomNotDaily() {
    let native = TriggerCompiler.parseNative(from: [
        "StartCalendarInterval": ["Hour": 9]
    ])
    let rules = TriggerCompiler.project(native)
    guard case .customCalendar(_, let malformed) = rules[0].kind else {
        return XCTFail("expected custom")
    }
    XCTAssertFalse(malformed)
}

func test_project_mergesWeekdays_keepsSourceRefs() {
    let native = TriggerCompiler.parseNative(from: [
        "StartCalendarInterval": [
            ["Weekday": 1, "Hour": 9, "Minute": 0], // Sunday in launchd? use 2=Mon if needed
            ["Hour": 18, "Minute": 0],
            ["Weekday": 3, "Hour": 9, "Minute": 0],
        ] as [[String: Int]]
    ])
    // Re-parse with Any arrays if needed — ensure A and C share one weekly rule.
    let rules = TriggerCompiler.project(native)
    let weekly = rules.first { if case .weekly = $0.kind { return true }; return false }
    XCTAssertNotNil(weekly)
    XCTAssertEqual(weekly?.sourceRefs.count, 2)
    XCTAssertTrue(rules.contains { if case .daily = $0.kind { return true }; return false })
}

func test_project_dayWeekday_isCustom() {
    let native = TriggerCompiler.parseNative(from: [
        "StartCalendarInterval": ["Day": 1, "Weekday": 2, "Hour": 9, "Minute": 0]
    ])
    let rules = TriggerCompiler.project(native)
    guard case .customCalendar = rules[0].kind else {
        return XCTFail("expected custom")
    }
}

func test_project_invalidHour_isMalformedCustom() {
    let native = TriggerCompiler.parseNative(from: [
        "StartCalendarInterval": ["Hour": 99, "Minute": 0]
    ])
    let rules = TriggerCompiler.project(native)
    guard case .customCalendar(_, let malformed) = rules[0].kind else {
        return XCTFail("expected custom")
    }
    XCTAssertTrue(malformed)
}
```

Note: launchd Weekday: 0 and 7 = Sunday, 1 = Monday … 6 = Saturday (confirm against Apple man page while implementing; tests must use the same mapping as UI labels).

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement `project` + helpers**

Add to `TriggerCompiler`:

```swift
static func presentKeys(_ entry: CalendarEntry) -> Set<String> {
    Set(entry.raw.keys)
}

static func isPresetCandidate(_ entry: CalendarEntry) -> Bool {
    entry.diagnostics.isEmpty && presentKeys(entry).isSubset(of: knownCalendarKeys)
}

static func classifySingleton(_ entry: CalendarEntry) -> TriggerRuleKind? {
    guard isPresetCandidate(entry) else {
        return .customCalendar(
            summary: summary(for: entry),
            isMalformed: !entry.diagnostics.isEmpty
        )
    }
    let keys = presentKeys(entry)
    switch keys {
    case ["Hour", "Minute"]:
        return .daily(hour: entry.hour!, minute: entry.minute!)
    case ["Weekday", "Hour", "Minute"]:
        return .weekly(weekdays: [entry.weekday!], hour: entry.hour!, minute: entry.minute!)
    case ["Day", "Hour", "Minute"]:
        return .monthly(day: entry.day!, hour: entry.hour!, minute: entry.minute!, months: nil)
    case ["Month", "Day", "Hour", "Minute"]:
        return .yearly(month: entry.month!, day: entry.day!, hour: entry.hour!, minute: entry.minute!)
    default:
        if keys.contains("Day") && keys.contains("Weekday") {
            return .customCalendar(summary: summary(for: entry), isMalformed: false)
        }
        return .customCalendar(summary: summary(for: entry), isMalformed: false)
    }
}

static func project(_ native: NativeTriggers) -> [TriggerRule] {
    var rules: [TriggerRule] = []
    var consumed: Set<UUID> = []

    // 1) Merge weekly same hour/minute
    // 2) Merge yearly same day/hour/minute different months → monthly(months:)
    // 3) Remaining singletons
    // 4) interval + watchPaths (each path gets UUID sourceRef stored alongside — see session)

    // Implementation detail: when projecting watch paths, allocate UUID per index and
    // keep parallel `[UUID]` on a projection context OR encode path index into session
    // via TriggerDocumentSession (Task 4). For pure project from NativeTriggers alone,
    // attach `SourceRef.watchPath(UUID())` and have session rebind on load.

    return rules
}

static func summary(for entry: CalendarEntry) -> String {
    knownCalendarKeys.sorted().compactMap { key -> String? in
        guard let v = entry.raw[key] else { return nil }
        return "\(key)=\(v)"
    }.joined(separator: " ")
}
```

Implement merge carefully:

- Weekly merge: same `Hour`+`Minute`, only `Weekday` differs, all preset-candidates → one `.weekly` with multiple `sourceRefs`.
- Month merge: same `Day`+`Hour`+`Minute`, only `Month` differs → one `.monthly(..., months: Set)`. Do **not** strip months when set.count == 12.
- Do not reorder `calendarEntries` array; only group for display order (stable: first occurrence order).

Watch path / interval projection:

```swift
if let seconds = native.startInterval {
    rules.append(TriggerRule(id: UUID(), kind: .interval(seconds: seconds),
                             sourceRefs: [.startInterval], isModified: false))
}
for path in native.watchPaths {
    let id = UUID()
    rules.append(TriggerRule(id: UUID(), kind: .watchPath(path),
                             sourceRefs: [.watchPath(id)], isModified: false))
}
```

(Session in Task 4 must persist the path UUID ↔ index mapping for write-back.)

- [ ] **Step 4: Run tests — PASS**

- [ ] **Step 5: Commit**

```bash
git add LaunchManager/Services/TriggerCompiler.swift LaunchManagerTests/TriggerCompilerTests.swift
git commit -m "feat: project TriggerRules with preset recognition and merges"
```

---

### Task 3: Compile edited presets + apply calendar change set

**Files:**
- Modify: `LaunchManager/Services/TriggerCompiler.swift`
- Modify: `LaunchManagerTests/TriggerCompilerTests.swift`

- [ ] **Step 1: Failing tests for compile + patch**

```swift
func test_compileDaily_writesOnlyHourMinute() {
    let dicts = TriggerCompiler.compileCalendarDicts(
        kind: .daily(hour: 9, minute: 30)
    )
    XCTAssertEqual(dicts.count, 1)
    XCTAssertEqual(dicts[0] as NSDictionary, ["Hour": 9, "Minute": 30] as NSDictionary)
}

func test_applyChange_unmodifiedKeepsRaw() {
    var root: [String: Any] = [
        "Label": "t",
        "StartCalendarInterval": ["Hour": 9] // missing Minute — custom
    ]
    let native = TriggerCompiler.parseNative(from: root)
    let rules = TriggerCompiler.project(native)
    // no modifications
    let out = TriggerCompiler.applyTriggers(
        to: root,
        native: native,
        rules: rules,
        pathIdsInOrder: []
    )
    XCTAssertEqual((out["StartCalendarInterval"] as? [String: Any])?["Hour"] as? Int, 9)
    XCTAssertNil((out["StartCalendarInterval"] as? [String: Any])?["Minute"])
}

func test_applyChange_editMergedWeek_onlyTouchesRefs() {
    // Build array [Mon 9:00, daily 18:00, Tue 9:00]; edit weekly time to 10:00;
    // assert middle daily unchanged; A/C become Hour 10.
}
```

- [ ] **Step 2: Run — FAIL**

- [ ] **Step 3: Implement compile + apply**

```swift
static func compileCalendarDicts(kind: TriggerRuleKind) -> [[String: Any]] {
    switch kind {
    case .daily(let h, let m):
        return [["Hour": h, "Minute": m]]
    case .weekly(let days, let h, let m):
        return days.sorted().map { ["Weekday": $0, "Hour": h, "Minute": m] }
    case .monthly(let day, let h, let m, let months):
        if let months, !months.isEmpty {
            return months.sorted().map {
                ["Month": $0, "Day": day, "Hour": h, "Minute": m]
            }
        }
        return [["Day": day, "Hour": h, "Minute": m]]
    case .yearly(let month, let day, let h, let m):
        return [["Month": month, "Day": day, "Hour": h, "Minute": m]]
    default:
        return []
    }
}

/// Rebuild StartCalendarInterval / StartInterval / WatchPaths from rules + native.
/// Unmodified calendar rules copy `raw` from referenced entries in original relative order.
/// Modified rules replace their refs with freshly compiled dicts (insert new weekday/month
/// entries immediately after the last ref of that rule).
static func applyTriggers(
    to root: [String: Any],
    native: NativeTriggers,
    rules: [TriggerRule],
    pathIdsInOrder: [UUID]
) -> [String: Any] {
    var result = root
    // 1. Build new calendar list without reordering untouched entries.
    // 2. Interval: if any interval rule modified/removed/added, set or remove key.
    // 3. WatchPaths: rebuild from watchPath rules in list order when any watch rule dirty
    //    or count/order changed; else leave key untouched (preserve missing vs []).
    return result
}
```

Exact algorithm for calendar rebuild:

1. Map `sessionId → CalendarEntry` from `native.calendarEntries`.
2. Walk original entries in order; skip those whose sessionId is in a **deleted** rule’s sourceRefs.
3. When hitting a sourceRef of a **modified** rule: replace that slot with the compiled dict matching the native entry’s Weekday (weekly) or Month (monthly-with-months); other kinds take the next remaining compiled dict. After the last ref of that rule, insert any extra compiled dicts (new weekdays/months not matched to a native ref). Drop native refs whose weekday/month was removed from the edited kind.
4. When hitting an **unmodified** ref, emit `entry.raw`.
5. Append brand-new rules (empty sourceRefs or refs not in native) at end.
6. Write shape: if key was absent and no calendar rules remain → omit key; if `count == 1` and original was single dict → keep single dict (even when touched); use array when `count != 1` or original was array.

- [ ] **Step 4: Tests PASS**

- [ ] **Step 5: Commit**

```bash
git commit -am "feat: compile presets and apply trigger change sets"
```

---

### Task 4: TriggerDocumentSession (root snapshot, no-op save, external change)

**Files:**
- Create: `LaunchManager/Services/TriggerDocumentSession.swift`
- Modify: `LaunchManagerTests/TriggerCompilerTests.swift` or new `TriggerDocumentSessionTests.swift`

- [ ] **Step 1: Failing tests**

```swift
func test_session_noChanges_shouldNotWrite() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("lm-session-\(UUID().uuidString).plist")
    let root: [String: Any] = [
        "Label": "a.b",
        "Program": "/bin/echo",
        "StartCalendarInterval": ["Hour": 9],
    ]
    let data = try PropertyListSerialization.data(fromPropertyList: root, format: .xml, options: 0)
    try data.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let session = try TriggerDocumentSession(url: url)
    XCTAssertFalse(session.triggersDirty)
    XCTAssertFalse(try session.fileChangedOnDisk())
    XCTAssertFalse(session.rootLogicallyChanged)
}

func test_session_detectsExternalChange() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("lm-session-\(UUID().uuidString).plist")
    let root: [String: Any] = ["Label": "a.b", "Program": "/bin/echo"]
    try PropertyListSerialization.data(fromPropertyList: root, format: .xml, options: 0)
        .write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let session = try TriggerDocumentSession(url: url)
    var changed = root
    changed["RunAtLoad"] = true
    try PropertyListSerialization.data(fromPropertyList: changed, format: .xml, options: 0)
        .write(to: url)
    XCTAssertTrue(try session.fileChangedOnDisk())
}
```

- [ ] **Step 2: Implement session**

```swift
struct TriggerDocumentSession {
    let url: URL
    private(set) var root: [String: Any]
    private let openedFileDate: Date?
    private let openedContentHash: Data // content hash of file at open

    var native: NativeTriggers
    var rules: [TriggerRule]
    var pathIdsInOrder: [UUID]
    // also track edits to Label/Program/… via separate managed fields OR full form state

    init(url: URL) throws {
        let data = try Data(contentsOf: url)
        self.openedContentHash = Self.hash(data)
        self.openedFileDate = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let root = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as! [String: Any]
        self.url = url
        self.root = root
        self.native = TriggerCompiler.parseNative(from: root)
        let projected = TriggerCompiler.project(native)
        // bind path UUIDs
        self.rules = projected
        self.pathIdsInOrder = []
    }

    var triggersDirty: Bool { rules.contains(where: \.isModified) /* or structural add/delete */ }

    func fileChangedOnDisk() throws -> Bool {
        let data = try Data(contentsOf: url)
        return Self.hash(data) != openedContentHash
    }

    mutating func applyTriggerRulesToRoot() {
        root = TriggerCompiler.applyTriggers(
            to: root, native: native, rules: rules, pathIdsInOrder: pathIdsInOrder
        )
    }
}
```

Form-managed non-trigger keys (Label, Program, …) still update `root` in place in the editor; session tracks `rootDirty` via deep compare to opened snapshot.

- [ ] **Step 3: Tests PASS + commit**

```bash
git add LaunchManager/Services/TriggerDocumentSession.swift LaunchManagerTests/*.swift
git commit -m "feat: add TriggerDocumentSession with external-change detection"
```

---

### Task 5: Wire PlistService save + relax form incompatibility

**Files:**
- Modify: `LaunchManager/Services/PlistService.swift`
- Modify: `LaunchManagerTests/LaunchManagerTests.swift`

- [ ] **Step 1: Update incompatibility tests**

Remove / invert `test_formIncompatibility_multipleWatchPaths` — multi WatchPaths must be form-compatible.

Change `formIncompatibilityReason` to **not** reject extra keys (passthrough retained by root session). Keep KeepAlive non-Bool → incompatible (or show read-only + XML for that key only — v1: still force XML if KeepAlive is non-Bool).

```swift
func formIncompatibilityReason(for dict: [String: Any]) -> String? {
    if let keepAlive = dict["KeepAlive"], keepAlive is Bool == false {
        return String(localized: "KeepAlive 使用了表单不支持的格式，请使用 XML 模式编辑。")
    }
    return nil
}
```

- [ ] **Step 2: Add save API that writes root dictionary**

```swift
func saveRoot(
    _ root: [String: Any],
    to url: URL,
    scope: LaunchItem.Scope,
    privilege: PrivilegeService,
    skipWriteIfUnchangedFrom openedHash: Data?
) throws {
    let data = try PropertyListSerialization.data(fromPropertyList: root, format: .xml, options: 0)
    if let openedHash, Self.hash(data) == openedHash { return } // careful: XML regeneration may change bytes even if logically equal — prefer logical equality against opened root via NSDictionary.isEqual
    // privilege write same as save(_ item:)
}
```

Prefer: compare `NSDictionary(dictionary: root).isEqual(to: openedRoot)` before serialize; if equal, **return without writing**.

- [ ] **Step 3: Stop using `toDictionary(item)` as sole form save path in editor** (editor Task 7). Keep `toDictionary` for new-agent creation from blank template only, where there is no prior root.

- [ ] **Step 4: Fix `parseCalendarIntervals` used by LaunchItem list path — do not default Minute to 0** when building derived `CalendarInterval` for summary; prefer projecting via `TriggerCompiler` for summaries (Task 6).

- [ ] **Step 5: Tests + commit**

```bash
git commit -am "feat: save plist via root snapshot; allow multi WatchPaths in form"
```

---

### Task 6: LaunchItem.triggerSummaryLines from projection

**Files:**
- Modify: `LaunchManager/Models/LaunchItem.swift`
- Modify: `LaunchManagerTests/LaunchManagerTests.swift`

- [ ] **Step 1: Rewrite `triggerSummaryLines`**

Build a temporary native+project from item fields **or** store summary lines at parse time.

Preferred at `parsePlist`:

```swift
let native = TriggerCompiler.parseNative(from: dict)
let rules = TriggerCompiler.project(native)
// map rules → localized lines; append runAtLoad; passthrough count hint
```

Keep `calendarIntervals` / `startInterval` / `watchPaths` as **derived** convenience for older call sites, but:

- `CalendarInterval.minute` must become `Int?` **or** list code stops using incomplete entries as if Minute were 0.
- Spec: missing Minute ≠ 0. Update struct:

```swift
struct CalendarInterval: Hashable {
    var weekday: Int?
    var hour: Int?
    var minute: Int?   // was Int non-optional
    var day: Int?
    var month: Int?
}
```

Migrate all `CalendarInterval` call sites / tests.

Summary formatting examples:

- daily → `每天 09:00`
- weekly → `周一至周五 09:00` (localized weekday names; never 「工作日」)
- monthly all → `每月 1 日 09:00`
- monthly months → `每月 · 1,4,7,10 月 · 1 日 09:00`
- yearly → existing yearly format
- interval → `每 3600 秒` or friendly unit later
- watchPath → `监视路径：…`
- custom → `自定义日历：Hour=9` / `配置异常：…`
- passthrough keys among `QueueDirectories`, `StartOnMount`, … → `+N 其它启动条件` or list names

- [ ] **Step 2: Fix compile breaks in tests + EditAgentSheet temporarily** (sheet still on old toggles until Task 7 — adapt to `minute: Int?`).

- [ ] **Step 3: Commit**

```bash
git commit -am "feat: derive trigger summaries from TriggerRule projection"
```

---

### Task 7: EditAgentSheet — rule list UI

**Files:**
- Modify: `LaunchManager/Views/EditAgentSheet.swift`
- Modify: `LaunchManager/Localizable.xcstrings`

- [ ] **Step 1: Replace trigger Toggle section with rule list**

State:

```swift
@State private var document: TriggerDocumentSession?
@State private var rules: [TriggerRule]
@State private var showAddRule = false
```

On appear / init from url: `TriggerDocumentSession(url:)`.

UI structure:

1. Text banner: `以下触发规则独立生效，任一规则触发时均可启动任务。`
2. `ForEach(rules)` — editor per kind
3. Button `添加规则` → confirmationDialog types: 每日/每周/每月/每年/时间间隔/监视路径 (disable interval if one exists)
4. Section `其它启动条件` — keys on root not in form-managed trigger/options set that look like launch conditions (`QueueDirectories`, `StartOnMount`, `Sockets`, …) read-only
5. Options: rename RunAtLoad toggle label to `加载任务时运行一次`; keep KeepAlive

Per-kind editors:

| Kind | Controls |
|------|----------|
| daily | hour/minute steppers |
| weekly | weekday multi-select + time |
| monthly | day + time + month mode (all / multi / quarter / half-year shortcuts) |
| yearly | month/day/time |
| interval | amount + unit; caption for days → 86400s |
| watchPath | TextField path |
| custom | read-only summary; button to switch XML mode |

Mark `isModified = true` on edit. Deleting a merged weekly rule shows confirmation: deletes all `sourceRefs`.

Remove: `useCalendar`, `CalendarFormRow` frequency enum that encoded every-N-months as interval, `IntervalUnit.months`.

- [ ] **Step 2: Save path**

```swift
if try session.fileChangedOnDisk() { /* alert reload */ return }
session.rules = rules
session.applyTriggerRulesToRoot()
// write Label/Program/options into session.root
try plistService.saveRoot(session.root, …)
```

New agent (no file): build blank root from fields + compiled rules; write once.

- [ ] **Step 3: Manual smoke + unit tests for save from sheet helpers if extracted**

- [ ] **Step 4: Commit**

```bash
git commit -am "feat: rule-list trigger editor with document session save"
```

---

### Task 8: Copy, help text, RunAtLoad unload warning

**Files:**
- Modify: `LaunchManager/Localizable.xcstrings`
- Modify: `LaunchManager/Views/EditAgentSheet.swift`

- [ ] **Step 1: Add strings (zh source + en)**

- `以下触发规则独立生效，任一规则触发时均可启动任务。`
- `顺序仅用于展示，不表示优先级或执行次序。`
- `加载任务时运行一次`
- `监视指定路径的变化。可能遗漏事件；触发不代表文件已写入完成。`
- `每 24 小时（86400 秒）`
- `配置异常`
- `自定义日历`
- `其它启动条件`
- `保存将重新加载任务，可能立即运行。` (show when runAtLoad && save will bootstrap)
- Interval / calendar help as in spec

- [ ] **Step 2: Commit**

```bash
git commit -am "i18n: trigger rule editor copy aligned with launchd semantics"
```

---

### Task 9: Regression + remove dead code

**Files:**
- Modify: `LaunchManagerTests/LaunchManagerTests.swift`
- Modify: `LaunchManager/Views/EditAgentSheet.swift` (delete unused private types)
- Modify: `docs/superpowers/specs/2026-10-16-multi-trigger-support-design.md` — add note at top: schedule UX superseded by 2026-10-20 for editor model; multi-trigger coexistence still in force.

- [ ] **Step 1: Update old tests**

- Any test expecting Minute default 0 for `{Hour:8}` → custom / nil minute  
- Multi WatchPaths form compatible  
- Round-trip: parse → save with no edits → file mtime/hash unchanged  
- Partial edit preserves passthrough `QueueDirectories`  
- Day 31 / Feb 29 unchanged  

- [ ] **Step 2: Full test suite**

```bash
xcodebuild test -project LaunchManager.xcodeproj -scheme LaunchManager -destination 'platform=macOS' \
  -only-testing:LaunchManagerTests 2>&1 | grep -E "Test Suite|passed|failed|error:|BUILD"
```

Expected: BUILD SUCCEEDED, all tests passed.

- [ ] **Step 3: Commit**

```bash
git commit -am "test: regress trigger rule model; drop obsolete calendar form helpers"
```

---

## Spec Coverage Checklist

| Spec requirement | Task |
|------------------|------|
| Two-layer / three-layer fidelity | 1–4 |
| No arbitrary every-N-months | 7 (removed), 2–3 (month set only) |
| Preset exact key sets | 2 |
| customCalendar + malformed | 2, 7 |
| sourceRefs merge write-back | 3, 7 |
| Month merge display-only; no strip Month | 2, 3 |
| Weekday 0/7 preserve when unmodified | 3 |
| Root document change set | 4–5 |
| No write if unchanged | 4–5 |
| Multi WatchPaths | 5, 7 |
| Passthrough visible + retained | 5, 7 |
| External change before save | 4, 7 |
| Independent rules copy | 8 |
| RunAtLoad wording | 8 |
| Day+Weekday never preset-generated | 2, 3 |
| Summary / list | 6 |

---

## Self-Review Notes

- No TBD steps; `applyTriggers` algorithm specified in Task 3.  
- Types consistent: `SourceRef`, `TriggerRuleKind`, `CalendarEntry.sessionId`.  
- `LaunchItem.CalendarInterval.minute` → `Int?` is a breaking change handled in Task 6.  
- Form no longer forces XML on extra keys — intentional per spec; KeepAlive non-Bool still blocked.
