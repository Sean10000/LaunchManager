# Plist 工作流增强 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add XML plist editing, import, clone, and Services→Launch Agent prefill so users can manage launchd jobs without terminal `cp`/`plutil` workflows.

**Architecture:** Extend `PlistService` with raw XML validate/save/clone; add optional `workingDirectory` to `LaunchItem`; dual-mode `EditAgentSheet` (Form | XML); toolbar import + row clone + Service prefill bridge via `LaunchAgentDraft`.

**Tech Stack:** Swift 6, SwiftUI, macOS, XCTest, PropertyListSerialization, existing `AgentStore` / `PrivilegeService`.

**Spec:** `docs/superpowers/specs/2026-07-04-plist-xml-and-launch-bridge-design.md`

---

## File Map

| File | Responsibility |
|------|----------------|
| `Models/LaunchItem.swift` | Add `workingDirectory: String?` |
| `Models/LaunchAgentDraft.swift` | **Create** — prefilled values for new agents (Services bridge, XML paste) |
| `Services/PlistService.swift` | validateXml, readXml, saveRawXml, clonePlist; WorkingDirectory parse/save |
| `Utilities/CommandLineParser.swift` | **Create** — split shell command into argv |
| `Store/AgentStore.swift` | importPlist, cloneItem, saveRawXml wrapper |
| `Views/EditAgentSheet.swift` | Form \| XML segmented editor; draft init |
| `Views/CloneAgentSheet.swift` | **Create** — new label + scope |
| `Views/AgentRowView.swift` | Copy… action |
| `Views/AgentListView.swift` | Import toolbar; New menu XML paste |
| `Views/ServiceRowView.swift` | Create Launch Agent button |
| `ContentView.swift` | Sheet state for XML-paste new + service prefill |
| `LaunchManagerTests/LaunchManagerTests.swift` | PlistService, CommandLineParser, clone tests |
| `Localizable.xcstrings` | New strings |
| `CHANGELOG.md` | Unreleased entries |

---

### Task 1: WorkingDirectory on LaunchItem

**Files:**
- Modify: `LaunchManager/Models/LaunchItem.swift`
- Modify: `LaunchManager/Services/PlistService.swift`
- Modify: `LaunchManagerTests/LaunchManagerTests.swift`
- Modify: all `LaunchItem(` call sites (tests, previews) — add `workingDirectory: nil` or value

- [ ] **Step 1: Write failing test**

Add to `PlistServiceTests` in `LaunchManagerTests/LaunchManagerTests.swift`:

```swift
func test_parsePlist_workingDirectory() throws {
    let plist = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict>
        <key>Label</key><string>com.test.cwd</string>
        <key>Program</key><string>/bin/echo</string>
        <key>WorkingDirectory</key><string>/Users/sean/project</string>
    </dict></plist>
    """
    let url = tmpDir.appendingPathComponent("com.test.cwd.plist")
    try plist.write(to: url, atomically: true, encoding: .utf8)
    let item = svc.parsePlist(at: url, scope: .userAgent)
    XCTAssertEqual(item?.workingDirectory, "/Users/sean/project")
}

func test_roundtrip_workingDirectory() throws {
    var original = LaunchItem(
        label: "com.test.cwd",
        plistURL: tmpDir.appendingPathComponent("com.test.cwd.plist"),
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
        workingDirectory: "/tmp/work",
        isLoaded: false,
        pid: nil,
        lastExitCode: nil
    )
    try svc.save(original, privilege: PrivilegeService())
    let parsed = svc.parsePlist(at: original.plistURL, scope: .userAgent)
    XCTAssertEqual(parsed?.workingDirectory, "/tmp/work")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd LaunchManager && xcodebuild test -scheme LaunchManager -destination 'platform=macOS' -only-testing:LaunchManagerTests/PlistServiceTests/test_parsePlist_workingDirectory 2>&1 | tail -20`

Expected: FAIL — `workingDirectory` member missing

- [ ] **Step 3: Implement**

In `LaunchItem.swift`, after `standardErrorPath`:

```swift
var workingDirectory: String?
```

In `PlistService.parsePlist`, add to return:

```swift
workingDirectory: dict["WorkingDirectory"] as? String,
```

In `toDictionary`:

```swift
if let wd = item.workingDirectory { dict["WorkingDirectory"] = wd }
```

Fix all `LaunchItem(` initializers project-wide (compiler will guide).

In `EditAgentSheet.saveItem()`, pass `workingDirectory` from new `@State private var workingDirectory: String` (empty → nil). Add form field in Task 6.

- [ ] **Step 4: Run tests**

Run: `xcodebuild test -scheme LaunchManager -destination 'platform=macOS' -only-testing:LaunchManagerTests/PlistServiceTests 2>&1 | tail -20`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add LaunchManager/Models/LaunchItem.swift LaunchManager/Services/PlistService.swift LaunchManagerTests/LaunchManagerTests.swift
git commit -m "feat: add WorkingDirectory support to LaunchItem and PlistService"
```

---

### Task 2: Plist XML validation and raw save

**Files:**
- Modify: `LaunchManager/Services/PlistService.swift`
- Modify: `LaunchManagerTests/LaunchManagerTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
func test_validateXml_valid() {
    let xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict>
        <key>Label</key><string>com.test.xml</string>
        <key>Program</key><string>/bin/echo</string>
        <key>EnvironmentVariables</key>
        <dict><key>FOO</key><string>bar</string></dict>
    </dict></plist>
    """
    let result = svc.validateXml(xml)
    guard case .success(let dict) = result else {
        return XCTFail("expected success")
    }
    XCTAssertEqual(dict["Label"] as? String, "com.test.xml")
    XCTAssertNotNil(dict["EnvironmentVariables"])
}

func test_validateXml_missingLabel() {
    let xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict><key>Program</key><string>/bin/echo</string></dict></plist>
    """
    guard case .failure(PlistValidationError.missingLabel) = svc.validateXml(xml) else {
        XCTFail("expected missingLabel")
    }
}

func test_saveRawXml_preservesExtraKeys() throws {
    let xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict>
        <key>Label</key><string>com.test.extra</string>
        <key>Program</key><string>/bin/echo</string>
        <key>EnvironmentVariables</key>
        <dict><key>PORT</key><string>3000</string></dict>
    </dict></plist>
    """
    let url = tmpDir.appendingPathComponent("com.test.extra.plist")
    try svc.saveRawXml(xml, to: url, scope: .userAgent, privilege: PrivilegeService())
    let data = try Data(contentsOf: url)
    let dict = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as! [String: Any]
    XCTAssertNotNil(dict["EnvironmentVariables"])
}
```

- [ ] **Step 2: Run tests — expect FAIL**

- [ ] **Step 3: Implement**

Add to `PlistService.swift`:

```swift
enum PlistValidationError: Error, Equatable {
    case invalidFormat(String)
    case missingLabel
}

extension PlistService {
    func validateXml(_ string: String) -> Result<[String: Any], PlistValidationError> {
        guard let data = string.data(using: .utf8) else {
            return .failure(.invalidFormat("Invalid UTF-8"))
        }
        do {
            guard let dict = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
                return .failure(.invalidFormat("Root must be a dictionary"))
            }
            guard dict["Label"] is String else {
                return .failure(.missingLabel)
            }
            return .success(dict)
        } catch {
            return .failure(.invalidFormat(error.localizedDescription))
        }
    }

    func readXml(from url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let xmlData = try PropertyListSerialization.data(fromPropertyList:
            try PropertyListSerialization.propertyList(from: data, options: [], format: nil),
            format: .xml,
            options: 0)
        guard let string = String(data: xmlData, encoding: .utf8) else {
            throw PlistValidationError.invalidFormat("Cannot encode XML")
        }
        return string
    }

    func saveRawXml(_ string: String, to url: URL, scope: LaunchItem.Scope, privilege: PrivilegeService) throws {
        let validated = validateXml(string)
        guard case .success(let dict) = validated else {
            if case .failure(let err) = validated { throw err }
            return
        }
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        if scope.requiresPrivilege {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
            try data.write(to: tmp)
            let dest = shellQuote(url.path)
            let src = shellQuote(tmp.path)
            try privilege.run("mv \(src) \(dest) && chown root:wheel \(dest) && chmod 644 \(dest)")
        } else {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
    }
}
```

Make `PlistValidationError` conform to `LocalizedError` for UI messages.

- [ ] **Step 4: Run PlistServiceTests — PASS**

- [ ] **Step 5: Commit**

```bash
git commit -m "feat: add PlistService XML validate and raw save"
```

---

### Task 3: Clone plist

**Files:**
- Modify: `LaunchManager/Services/PlistService.swift`
- Modify: `LaunchManagerTests/LaunchManagerTests.swift`

- [ ] **Step 1: Write failing test**

```swift
func test_clonePlist_changesLabel() throws {
    let source = tmpDir.appendingPathComponent("com.test.source.plist")
    let xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict>
        <key>Label</key><string>com.test.source</string>
        <key>Program</key><string>/bin/echo</string>
        <key>RunAtLoad</key><true/>
    </dict></plist>
    """
    try xml.write(to: source, atomically: true, encoding: .utf8)
    let dest = svc.clonePlist(from: source, newLabel: "com.test.copy", targetScope: .userAgent, targetDirectory: tmpDir)
    XCTAssertEqual(dest.lastPathComponent, "com.test.copy.plist")
    let item = svc.parsePlist(at: dest, scope: .userAgent)
    XCTAssertEqual(item?.label, "com.test.copy")
}
```

Note: add `targetDirectory: URL` parameter to `clonePlist` for testability (default to `scope.directoryURL` in production call).

- [ ] **Step 2–4: Implement, test, pass**

```swift
func clonePlist(from sourceURL: URL, newLabel: String, targetScope: LaunchItem.Scope, targetDirectory: URL? = nil) throws -> URL {
    let xml = try readXml(from: sourceURL)
    guard case .success(var dict) = validateXml(xml) else {
        throw PlistValidationError.missingLabel
    }
    dict["Label"] = newLabel
    let dir = targetDirectory ?? targetScope.directoryURL
    let dest = dir.appendingPathComponent("\(newLabel).plist")
    let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
    let destString = String(data: data, encoding: .utf8)!
    try saveRawXml(destString, to: dest, scope: targetScope, privilege: PrivilegeService())
    return dest
}
```

For tests, pass `PrivilegeService()` with user scope only (tmpDir).

- [ ] **Step 5: Commit**

```bash
git commit -m "feat: add PlistService clonePlist"
```

---

### Task 4: CommandLineParser

**Files:**
- Create: `LaunchManager/Utilities/CommandLineParser.swift`
- Modify: `LaunchManager.xcodeproj/project.pbxproj` (add file to target)
- Modify: `LaunchManagerTests/LaunchManagerTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
final class CommandLineParserTests: XCTestCase {
    func test_simpleCommand() {
        XCTAssertEqual(CommandLineParser.parse("node server.js"), ["node", "server.js"])
    }

    func test_quotedPath() {
        XCTAssertEqual(
            CommandLineParser.parse(#"/usr/bin/node "/Users/sean/my app/server.js""#),
            ["/usr/bin/node", "/Users/sean/my app/server.js"]
        )
    }

    func test_npmRunDev() {
        let args = CommandLineParser.parse("npm run dev")
        XCTAssertEqual(args, ["npm", "run", "dev"])
    }

    func test_empty_returnsEmpty() {
        XCTAssertTrue(CommandLineParser.parse("").isEmpty)
    }
}
```

- [ ] **Step 2: Run — FAIL**

- [ ] **Step 3: Implement minimal parser**

```swift
enum CommandLineParser {
    static func parse(_ command: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inSingle = false
        var inDouble = false
        let chars = Array(command)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "'" && !inDouble {
                inSingle.toggle()
                i += 1
                continue
            }
            if c == "\"" && !inSingle {
                inDouble.toggle()
                i += 1
                continue
            }
            if c.isWhitespace && !inSingle && !inDouble {
                if !current.isEmpty {
                    result.append(current)
                    current = ""
                }
                i += 1
                continue
            }
            if c == "\\" && inDouble && i + 1 < chars.count {
                current.append(chars[i + 1])
                i += 2
                continue
            }
            current.append(c)
            i += 1
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
```

- [ ] **Step 4: PASS + commit**

```bash
git commit -m "feat: add CommandLineParser for service command splitting"
```

---

### Task 5: LaunchAgentDraft + Service prefill helper

**Files:**
- Create: `LaunchManager/Models/LaunchAgentDraft.swift`

- [ ] **Step 1: Create model**

```swift
import Foundation

struct LaunchAgentDraft: Equatable {
    var label: String
    var program: String
    var programArguments: [String]
    var workingDirectory: String?
    var runAtLoad: Bool
    var keepAlive: Bool
    var triggerType: LaunchItem.TriggerType

    static func from(service: Service) -> LaunchAgentDraft? {
        guard service.runtimeGroup == .instance, service.killAllowed else { return nil }
        let args = CommandLineParser.parse(service.command)
        let program: String
        let programArguments: [String]
        if args.isEmpty {
            program = service.executable
            programArguments = []
        } else {
            program = args[0]
            programArguments = Array(args.dropFirst())
        }
        let slug = service.displayName
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let suggestedLabel = "dev.\(service.port).\(slug.isEmpty ? "service" : slug)"
        return LaunchAgentDraft(
            label: suggestedLabel,
            program: program,
            programArguments: programArguments,
            workingDirectory: service.workingDirectory ?? service.processDirectory,
            runAtLoad: true,
            keepAlive: false,
            triggerType: .atLoad
        )
    }
}
```

- [ ] **Step 2: Unit test**

```swift
func test_launchAgentDraft_fromService() {
    let service = Service(/* instance with command node next dev, port 3000, cwd /proj */)
    let draft = LaunchAgentDraft.from(service: service)
    XCTAssertEqual(draft?.program, "node")
    XCTAssertEqual(draft?.workingDirectory, "/proj")
}
```

Use inline `Service(...)` like existing test helpers.

- [ ] **Step 3: Commit**

---

### Task 6: AgentStore import + clone

**Files:**
- Modify: `LaunchManager/Store/AgentStore.swift`

- [ ] **Step 1: Add methods**

```swift
func saveRawXml(_ xml: String, to url: URL, scope: LaunchItem.Scope) throws {
    try plistService.saveRawXml(xml, to: url, scope: scope, privilege: privilegeService)
    refresh()
}

func cloneItem(_ item: LaunchItem, newLabel: String, scope: LaunchItem.Scope) throws {
    let dest = scope.directoryURL.appendingPathComponent("\(newLabel).plist")
    if FileManager.default.fileExists(atPath: dest.path) {
        throw PlistValidationError.invalidFormat(String(localized: "Label 已存在"))
    }
    _ = try plistService.clonePlist(from: item.plistURL, newLabel: newLabel, targetScope: scope)
    refresh()
}

func importPlist(from sourceURL: URL, scope: LaunchItem.Scope, overwrite: Bool) throws -> LaunchItem {
    let xml = try plistService.readXml(from: sourceURL)
    guard case .success(let dict) = plistService.validateXml(xml),
          let label = dict["Label"] as? String else {
        throw PlistValidationError.missingLabel
    }
    let dest = scope.directoryURL.appendingPathComponent("\(label).plist")
    if FileManager.default.fileExists(atPath: dest.path) && !overwrite {
        throw PlistValidationError.invalidFormat(String(localized: "文件已存在"))
    }
    try plistService.saveRawXml(xml, to: dest, scope: scope, privilege: privilegeService)
    refresh()
    guard let item = items.first(where: { $0.label == label && $0.scope == scope }) else {
        throw PlistValidationError.invalidFormat("Import succeeded but item not found")
    }
    return item
}
```

- [ ] **Step 2: Commit**

---

### Task 7: EditAgentSheet dual mode (Form | XML)

**Files:**
- Modify: `LaunchManager/Views/EditAgentSheet.swift`

- [ ] **Step 1: Add editor mode enum and state**

```swift
private enum EditorMode: String, CaseIterable {
    case form, xml
}

@State private var editorMode: EditorMode = .form
@State private var xmlText: String = ""
@State private var xmlError: String?
@State private var formDisabledReason: String?
@State private var workingDirectory: String
```

Extend `init` to accept optional `draft: LaunchAgentDraft?` and optional `initialXml: String?`:

- If `initialXml != nil` → start in `.xml` mode with that text
- If `draft != nil` → prefill form fields from draft

- [ ] **Step 2: Add segmented picker above Form**

```swift
Picker("编辑模式", selection: $editorMode) {
    Text("表单").tag(EditorMode.form)
    Text("XML").tag(EditorMode.xml)
}
.pickerStyle(.segmented)
.padding(.horizontal)
.onChange(of: editorMode) { _, mode in
    switch mode {
    case .xml:
        if xmlText.isEmpty {
            if let existing = existingItem {
                xmlText = (try? PlistService().readXml(from: existing.plistURL)) ?? formGeneratedXml()
            } else {
                xmlText = formGeneratedXml()
            }
        }
    case .form:
        syncFormFromXmlIfPossible()
    }
}
```

- [ ] **Step 3: XML view branch**

When `editorMode == .xml`, show `TextEditor(text: $xmlText).font(.system(.body, design: .monospaced))` + validation caption. Disable Save when `validateXml` fails.

- [ ] **Step 4: Update saveItem()**

```swift
private func saveItem() {
    if editorMode == .xml {
        let scope = existingItem?.scope ?? defaultScope
        let url = existingItem?.plistURL ?? scope.directoryURL.appendingPathComponent("\(label).plist")
        do {
            try store.saveRawXml(xmlText, to: url, scope: scope)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        return
    }
    // existing form save, include workingDirectory
}
```

- [ ] **Step 5: Add WorkingDirectory field** in 基本信息 section (optional TextField).

- [ ] **Step 6: Manual smoke test** — edit existing agent, switch to XML, add `EnvironmentVariables`, save, reopen.

- [ ] **Step 7: Commit**

---

### Task 8: CloneAgentSheet + AgentRowView

**Files:**
- Create: `LaunchManager/Views/CloneAgentSheet.swift`
- Modify: `LaunchManager/Views/AgentRowView.swift`

- [ ] **Step 1: CloneAgentSheet**

Form with:
- TextField new label (default `\(item.label).copy`)
- Picker scope
- Save / Cancel
- On save: `try store.cloneItem(item, newLabel: trimmed, scope: selectedScope)`

- [ ] **Step 2: AgentRowView**

Add `@State private var showingClone = false` and in expanded HStack:

```swift
Button("复制…") { showingClone = true }
    .buttonStyle(.bordered).controlSize(.small)
```

`.sheet(isPresented: $showingClone) { CloneAgentSheet(item: item, store: store, errorMessage: $errorMessage) }`

- [ ] **Step 3: Commit**

---

### Task 9: Import plist + New from XML paste

**Files:**
- Modify: `LaunchManager/Views/AgentListView.swift`
- Modify: `LaunchManager/ContentView.swift`

- [ ] **Step 1: AgentListView bindings**

Add `@Binding var showingImport: Bool` and `@Binding var showingNewFromXml: Bool` (or single enum `NewAgentPresentation`).

Toolbar:

```swift
Button { showingImport = true } label: {
    Label("导入", systemImage: "square.and.arrow.down")
}
```

New menu item:

```swift
Button {
    newAgentScope = .userAgent
    showingNewFromXml = true
} label: {
    Label("从 XML 粘贴…", systemImage: "doc.on.clipboard")
}
```

- [ ] **Step 2: Import flow in ContentView or AgentListView**

Use `NSOpenPanel` + scope `confirmationDialog` or small sheet:

1. Pick file
2. Pick scope (segmented: 用户 / 全局 Agent / Daemon)
3. If file exists at dest → confirm overwrite
4. `store.importPlist(...)`
5. Optional alert: 「是否立即载入？」→ `store.bootstrap(item)`

- [ ] **Step 3: New from XML sheet**

Present `EditAgentSheet(existingItem: nil, defaultScope: newAgentScope, store: store, initialXml: "<?xml ...>\n")` with empty template dict containing only Label placeholder, OR start with clipboard:

```swift
initialXml: NSPasteboard.general.string(forType: .string) ?? defaultEmptyPlistXml
```

- [ ] **Step 4: Commit**

---

### Task 10: Services → Create Launch Agent

**Files:**
- Modify: `LaunchManager/Views/ServiceRowView.swift`
- Modify: `LaunchManager/Views/ServicesListView.swift` (pass binding)
- Modify: `LaunchManager/ContentView.swift`

- [ ] **Step 1: ContentView state**

```swift
@State private var serviceLaunchDraft: LaunchAgentDraft?
```

Sheet:

```swift
.sheet(item: $serviceLaunchDraft) { draft in
    EditAgentSheet(existingItem: nil, defaultScope: .userAgent, store: store, draft: draft)
}
```

Make `LaunchAgentDraft` conform to `Identifiable` (`id = label`).

- [ ] **Step 2: ServiceRowView button**

When `service.runtimeGroup == .instance && service.killAllowed`:

```swift
Button("创建 Launch Agent…") {
    if let draft = LaunchAgentDraft.from(service: service) {
        onCreateLaunchAgent(draft)
    }
}
```

Pass closure from `ServicesListView` → `ContentView`.

- [ ] **Step 3: Smoke test** — scan Services, expand Next.js row, create agent, verify prefill.

- [ ] **Step 4: Commit**

---

### Task 11: Localization + CHANGELOG

**Files:**
- Modify: `LaunchManager/Localizable.xcstrings`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Add strings** (zh-Hans + en): 表单, XML, 导入, 复制, 从 XML 粘贴, 创建 Launch Agent, WorkingDirectory label, validation errors, clone success, import overwrite confirm.

- [ ] **Step 2: CHANGELOG [Unreleased]**

```markdown
### Added
- **Plist XML editor** — Form | XML tabs in agent editor; paste XML to create new jobs; extra plist keys preserved in XML mode.
- **Import plist** — import external `.plist` into user/global Agent or LaunchDaemon directories.
- **Clone job** — duplicate an existing Launch Agent/Daemon with a new Label.
- **Services → Launch Agent** — prefill a new user Agent from a running local service (command, working directory).
- **WorkingDirectory** — optional field in agent form.
```

- [ ] **Step 3: Full test suite**

Run: `xcodebuild test -scheme LaunchManager -destination 'platform=macOS' 2>&1 | tail -30`

Expected: BUILD SUCCEEDED, all tests pass

- [ ] **Step 4: Commit**

```bash
git commit -m "docs: localize plist workflow features and update CHANGELOG"
```

---

## Spec Coverage Checklist

| Spec requirement | Task |
|------------------|------|
| Form \| XML dual mode | Task 7 |
| XML paste new | Task 9 |
| Import plist | Task 9 |
| Clone job | Task 3, 5, 8 |
| Services prefill | Task 4, 5, 10 |
| WorkingDirectory | Task 1, 7 |
| Extra keys preserved | Task 2 saveRawXml |
| No auto bootstrap on clone | Task 8 |
| Privilege paths | Task 2 saveRawXml |
| Tests | Tasks 1–4, 11 |

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-07-04-plist-xml-and-launch-bridge.md`.

**Two execution options:**

1. **Subagent-Driven (recommended)** — fresh subagent per task, review between tasks
2. **Inline Execution** — implement tasks in this session with checkpoints

Which approach?
