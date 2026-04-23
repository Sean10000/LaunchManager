# LaunchManager Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 构建一个免费开源的 macOS SwiftUI 应用，可视化管理 LaunchAgents / LaunchDaemons（列出、启停、新建、编辑、删除、查看日志）。

**Architecture:** NavigationSplitView 两栏布局（侧边栏分类 + 可展开列表行）。Services 层（LaunchctlService / PlistService / PrivilegeService）与 UI 完全解耦，通过 `AgentStore` ObservableObject 驱动视图。系统级写操作经 osascript 授权。

**Tech Stack:** Swift 5.9+, SwiftUI, macOS 13+, XCTest, 无第三方依赖

---

## 文件清单

| 文件 | 职责 |
|------|------|
| `LaunchManager/LaunchManagerApp.swift` | @main 入口，配置窗口 |
| `LaunchManager/Models/LaunchItem.swift` | 核心数据模型 |
| `LaunchManager/Services/PrivilegeService.swift` | osascript 授权包装 |
| `LaunchManager/Services/ShellRunner.swift` | Shell 执行协议 + 默认实现（可 mock） |
| `LaunchManager/Services/LaunchctlService.swift` | launchctl CLI 包装 |
| `LaunchManager/Services/PlistService.swift` | plist 扫描/解析/写入/删除 |
| `LaunchManager/Store/AgentStore.swift` | @MainActor ObservableObject，持有所有状态 |
| `LaunchManager/Views/ContentView.swift` | NavigationSplitView 根视图 |
| `LaunchManager/Views/SidebarView.swift` | 左侧分类栏 |
| `LaunchManager/Views/AgentListView.swift` | 右侧列表容器 + 工具栏 |
| `LaunchManager/Views/AgentRowView.swift` | 可展开行 |
| `LaunchManager/Views/EditAgentSheet.swift` | 新建/编辑 Sheet |
| `LaunchManager/Views/LogViewerSheet.swift` | 日志查看 Sheet |
| `LaunchManagerTests/LaunchctlServiceTests.swift` | 解析逻辑单元测试 |
| `LaunchManagerTests/PlistServiceTests.swift` | plist 解析/序列化单元测试 |

---

## Task 1: Xcode 项目初始化

**Files:**
- Create: Xcode project at `LaunchManager/`

- [ ] **Step 1: 在 Xcode 创建项目**

  File → New → Project → macOS → App
  - Product Name: `LaunchManager`
  - Interface: SwiftUI
  - Language: Swift
  - Include Tests: ✓
  - Deployment Target: macOS 13.0

- [ ] **Step 2: 关闭 App Sandbox**

  打开 `LaunchManager/LaunchManager.entitlements`，将 `com.apple.security.app-sandbox` 的值改为 `false`（或直接删除该 key）。

  原因：需要调用 `Process` 运行 `launchctl` 和 `osascript`，沙盒会阻断这些调用。

- [ ] **Step 3: 在 Info.plist 添加 AppleEvents 说明**

  在 `Info.plist` 中添加：
  ```xml
  <key>NSAppleEventsUsageDescription</key>
  <string>LaunchManager 需要管理员权限来修改系统级 LaunchDaemons。</string>
  ```

- [ ] **Step 4: 创建目录结构**

  在 Xcode 中右键项目 → New Group，创建：
  - `Models/`
  - `Services/`
  - `Store/`
  - `Views/`

- [ ] **Step 5: 删除 Xcode 生成的 ContentView 占位内容**

  保留文件，清空 body 内容，后续 Task 7 会填充。

- [ ] **Step 6: Commit**

  ```bash
  git init
  git add .
  git commit -m "feat: initial Xcode project setup"
  ```

---

## Task 2: LaunchItem 数据模型

**Files:**
- Create: `LaunchManager/Models/LaunchItem.swift`

- [ ] **Step 1: 创建 LaunchItem.swift**

  ```swift
  import Foundation

  struct LaunchItem: Identifiable, Hashable {
      var id: String { label }
      var label: String
      var plistURL: URL
      var scope: Scope
      var program: String
      var programArguments: [String]
      var triggerType: TriggerType
      var calendarInterval: CalendarInterval?
      var startInterval: Int?        // 秒，triggerType == .interval 时有效
      var watchPaths: [String]
      var runAtLoad: Bool
      var keepAlive: Bool
      var standardOutPath: String?
      var standardErrorPath: String?
      // 运行时状态，不写入 plist
      var isLoaded: Bool
      var pid: Int?
      var lastExitCode: Int?

      enum Scope: String, CaseIterable, Hashable {
          case userAgent    = "用户 Agents"
          case systemAgent  = "系统 Agents"
          case systemDaemon = "系统 Daemons"

          var directoryURL: URL {
              switch self {
              case .userAgent:
                  return FileManager.default.homeDirectoryForCurrentUser
                      .appendingPathComponent("Library/LaunchAgents")
              case .systemAgent:
                  return URL(fileURLWithPath: "/Library/LaunchAgents")
              case .systemDaemon:
                  return URL(fileURLWithPath: "/Library/LaunchDaemons")
              }
          }

          var requiresPrivilege: Bool { self != .userAgent }
      }

      enum TriggerType: String, CaseIterable, Hashable {
          case calendar  = "定时"
          case interval  = "间隔"
          case atLoad    = "登录时"
          case watchPath = "监视路径"
      }

      struct CalendarInterval: Hashable {
          var weekday: Int?  // nil = 每天；1=周一…7=周日
          var hour: Int?     // nil = 每小时
          var minute: Int
      }
  }
  ```

- [ ] **Step 2: Commit**

  ```bash
  git add LaunchManager/Models/LaunchItem.swift
  git commit -m "feat: add LaunchItem model"
  ```

---

## Task 3: PrivilegeService

**Files:**
- Create: `LaunchManager/Services/PrivilegeService.swift`

- [ ] **Step 1: 创建 PrivilegeService.swift**

  ```swift
  import Foundation

  enum PrivilegeError: LocalizedError {
      case cancelled
      case executionFailed(String)

      var errorDescription: String? {
          switch self {
          case .cancelled: return "操作已取消"
          case .executionFailed(let msg): return "执行失败：\(msg)"
          }
      }
  }

  struct PrivilegeService {
      func run(_ shellCommand: String) throws {
          let escaped = shellCommand
              .replacingOccurrences(of: "\\", with: "\\\\")
              .replacingOccurrences(of: "\"", with: "\\\"")
          let source = "do shell script \"\(escaped)\" with administrator privileges"
          var errorDict: NSDictionary?
          NSAppleScript(source: source)?.executeAndReturnError(&errorDict)
          guard let err = errorDict else { return }
          let code = err[NSAppleScript.errorNumber] as? Int ?? 0
          if code == -128 { throw PrivilegeError.cancelled }
          let msg = err[NSAppleScript.errorMessage] as? String ?? "\(err)"
          throw PrivilegeError.executionFailed(msg)
      }
  }
  ```

  > `NSAppleScript.errorNumber == -128` 表示用户点了「取消」。

- [ ] **Step 2: Commit**

  ```bash
  git add LaunchManager/Services/PrivilegeService.swift
  git commit -m "feat: add PrivilegeService (osascript wrapper)"
  ```

---

## Task 4: ShellRunner + LaunchctlService

**Files:**
- Create: `LaunchManager/Services/ShellRunner.swift`
- Create: `LaunchManager/Services/LaunchctlService.swift`
- Create: `LaunchManagerTests/LaunchctlServiceTests.swift`

- [ ] **Step 1: 写测试（先红）**

  新建 `LaunchManagerTests/LaunchctlServiceTests.swift`，加入测试目标：

  ```swift
  import XCTest
  @testable import LaunchManager

  final class LaunchctlServiceTests: XCTestCase {

      func test_parseListOutput_running() {
          let output = """
          PID\tStatus\tLabel
          636\t0\tcom.syncthing.start
          """
          let svc = LaunchctlService()
          let result = svc.parseListOutput(output)
          XCTAssertEqual(result["com.syncthing.start"]?.pid, 636)
          XCTAssertEqual(result["com.syncthing.start"]?.exitCode, 0)
      }

      func test_parseListOutput_stopped() {
          let output = """
          PID\tStatus\tLabel
          -\t0\tcom.syncthing.stop
          """
          let svc = LaunchctlService()
          let result = svc.parseListOutput(output)
          XCTAssertNil(result["com.syncthing.stop"]?.pid)
          XCTAssertEqual(result["com.syncthing.stop"]?.exitCode, 0)
      }

      func test_parseListOutput_failed() {
          let output = """
          PID\tStatus\tLabel
          -\t1\tcom.example.failed
          """
          let svc = LaunchctlService()
          let result = svc.parseListOutput(output)
          XCTAssertNil(result["com.example.failed"]?.pid)
          XCTAssertEqual(result["com.example.failed"]?.exitCode, 1)
      }

      func test_parseListOutput_emptyLines() {
          let output = "PID\tStatus\tLabel\n636\t0\tcom.foo\n\n"
          let svc = LaunchctlService()
          let result = svc.parseListOutput(output)
          XCTAssertEqual(result.count, 1)
      }
  }
  ```

- [ ] **Step 2: 运行测试，确认失败**

  Product → Test（⌘U）
  Expected: 编译失败（类型尚未定义）

- [ ] **Step 3: 创建 ShellRunner.swift**

  ```swift
  import Foundation

  enum ShellError: LocalizedError {
      case nonZeroExit(code: Int32, output: String)
      var errorDescription: String? {
          if case .nonZeroExit(_, let out) = self { return out }
          return nil
      }
  }

  protocol ShellRunner {
      func run(_ path: String, arguments: [String]) throws -> String
  }

  struct DefaultShellRunner: ShellRunner {
      func run(_ path: String, arguments: [String]) throws -> String {
          let process = Process()
          process.executableURL = URL(fileURLWithPath: path)
          process.arguments = arguments
          let outPipe = Pipe()
          let errPipe = Pipe()
          process.standardOutput = outPipe
          process.standardError = errPipe
          try process.run()
          process.waitUntilExit()
          let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
          if process.terminationStatus != 0 {
              let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
              throw ShellError.nonZeroExit(code: process.terminationStatus, output: err)
          }
          return out
      }
  }
  ```

- [ ] **Step 4: 创建 LaunchctlService.swift**

  ```swift
  import Foundation

  struct LaunchctlService {
      var shell: ShellRunner
      var privilege: PrivilegeService

      init(shell: ShellRunner = DefaultShellRunner(),
           privilege: PrivilegeService = PrivilegeService()) {
          self.shell = shell
          self.privilege = privilege
      }

      func listAll() throws -> [String: (pid: Int?, exitCode: Int?)] {
          let output = try shell.run("/bin/launchctl", arguments: ["list"])
          return parseListOutput(output)
      }

      func parseListOutput(_ output: String) -> [String: (pid: Int?, exitCode: Int?)] {
          var result: [String: (pid: Int?, exitCode: Int?)] = [:]
          let lines = output.components(separatedBy: "\n").dropFirst()
          for line in lines {
              let cols = line.components(separatedBy: "\t")
              guard cols.count == 3 else { continue }
              let pidStr  = cols[0].trimmingCharacters(in: .whitespaces)
              let codeStr = cols[1].trimmingCharacters(in: .whitespaces)
              let label   = cols[2].trimmingCharacters(in: .whitespaces)
              guard !label.isEmpty else { continue }
              result[label] = (pid: pidStr == "-" ? nil : Int(pidStr),
                               exitCode: Int(codeStr))
          }
          return result
      }

      func load(_ url: URL, privileged: Bool) throws {
          if privileged {
              try privilege.run("/bin/launchctl load \(url.path)")
          } else {
              _ = try shell.run("/bin/launchctl", arguments: ["load", url.path])
          }
      }

      func unload(_ url: URL, privileged: Bool) throws {
          if privileged {
              try privilege.run("/bin/launchctl unload \(url.path)")
          } else {
              _ = try shell.run("/bin/launchctl", arguments: ["unload", url.path])
          }
      }

      func start(_ label: String, privileged: Bool) throws {
          if privileged {
              try privilege.run("/bin/launchctl start \(label)")
          } else {
              _ = try shell.run("/bin/launchctl", arguments: ["start", label])
          }
      }

      func stop(_ label: String, privileged: Bool) throws {
          if privileged {
              try privilege.run("/bin/launchctl stop \(label)")
          } else {
              _ = try shell.run("/bin/launchctl", arguments: ["stop", label])
          }
      }
  }
  ```

- [ ] **Step 5: 运行测试，确认全部通过**

  Product → Test（⌘U）
  Expected: 4 tests passed

- [ ] **Step 6: Commit**

  ```bash
  git add LaunchManager/Services/ShellRunner.swift \
          LaunchManager/Services/LaunchctlService.swift \
          LaunchManagerTests/LaunchctlServiceTests.swift
  git commit -m "feat: add ShellRunner protocol and LaunchctlService with tests"
  ```

---

## Task 5: PlistService

**Files:**
- Create: `LaunchManager/Services/PlistService.swift`
- Create: `LaunchManagerTests/PlistServiceTests.swift`

- [ ] **Step 1: 写测试（先红）**

  ```swift
  import XCTest
  @testable import LaunchManager

  final class PlistServiceTests: XCTestCase {
      var tmpDir: URL!
      let svc = PlistService()

      override func setUp() {
          tmpDir = FileManager.default.temporaryDirectory
              .appendingPathComponent(UUID().uuidString)
          try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
      }

      override func tearDown() {
          try? FileManager.default.removeItem(at: tmpDir)
      }

      func test_parsePlist_calendarTrigger() throws {
          let plist = """
          <?xml version="1.0" encoding="UTF-8"?>
          <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
          <plist version="1.0">
          <dict>
              <key>Label</key><string>com.test.calendar</string>
              <key>ProgramArguments</key>
              <array><string>/usr/bin/open</string><string>-a</string><string>Syncthing</string></array>
              <key>StartCalendarInterval</key>
              <dict><key>Hour</key><integer>8</integer><key>Minute</key><integer>0</integer></dict>
              <key>RunAtLoad</key><false/>
          </dict>
          </plist>
          """
          let url = tmpDir.appendingPathComponent("com.test.calendar.plist")
          try plist.write(to: url, atomically: true, encoding: .utf8)

          let item = svc.parsePlist(at: url, scope: .userAgent)
          XCTAssertNotNil(item)
          XCTAssertEqual(item?.label, "com.test.calendar")
          XCTAssertEqual(item?.program, "/usr/bin/open")
          XCTAssertEqual(item?.programArguments, ["-a", "Syncthing"])
          XCTAssertEqual(item?.triggerType, .calendar)
          XCTAssertEqual(item?.calendarInterval?.hour, 8)
          XCTAssertEqual(item?.calendarInterval?.minute, 0)
          XCTAssertNil(item?.calendarInterval?.weekday)
      }

      func test_parsePlist_intervalTrigger() throws {
          let plist = """
          <?xml version="1.0" encoding="UTF-8"?>
          <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
          <plist version="1.0">
          <dict>
              <key>Label</key><string>com.test.interval</string>
              <key>Program</key><string>/usr/local/bin/mytool</string>
              <key>StartInterval</key><integer>300</integer>
          </dict>
          </plist>
          """
          let url = tmpDir.appendingPathComponent("com.test.interval.plist")
          try plist.write(to: url, atomically: true, encoding: .utf8)

          let item = svc.parsePlist(at: url, scope: .userAgent)
          XCTAssertEqual(item?.triggerType, .interval)
          XCTAssertEqual(item?.startInterval, 300)
          XCTAssertEqual(item?.program, "/usr/local/bin/mytool")
      }

      func test_roundtrip() throws {
          let original = LaunchItem(
              label: "com.test.roundtrip",
              plistURL: tmpDir.appendingPathComponent("com.test.roundtrip.plist"),
              scope: .userAgent,
              program: "/bin/echo",
              programArguments: ["hello"],
              triggerType: .calendar,
              calendarInterval: LaunchItem.CalendarInterval(weekday: nil, hour: 9, minute: 30),
              startInterval: nil,
              watchPaths: [],
              runAtLoad: true,
              keepAlive: false,
              standardOutPath: "/tmp/out.log",
              standardErrorPath: nil,
              isLoaded: false,
              pid: nil,
              lastExitCode: nil
          )

          try svc.save(original, privilege: PrivilegeService())
          let parsed = svc.parsePlist(at: original.plistURL, scope: .userAgent)

          XCTAssertEqual(parsed?.label, original.label)
          XCTAssertEqual(parsed?.program, original.program)
          XCTAssertEqual(parsed?.programArguments, original.programArguments)
          XCTAssertEqual(parsed?.triggerType, original.triggerType)
          XCTAssertEqual(parsed?.calendarInterval?.hour, 9)
          XCTAssertEqual(parsed?.calendarInterval?.minute, 30)
          XCTAssertEqual(parsed?.runAtLoad, true)
          XCTAssertEqual(parsed?.standardOutPath, "/tmp/out.log")
      }

      func test_parsePlist_invalidFile_returnsNil() throws {
          let url = tmpDir.appendingPathComponent("bad.plist")
          try "not a plist".write(to: url, atomically: true, encoding: .utf8)
          XCTAssertNil(svc.parsePlist(at: url, scope: .userAgent))
      }
  }
  ```

- [ ] **Step 2: 运行测试，确认失败**

  ⌘U → Expected: compile error（PlistService 未定义）

- [ ] **Step 3: 创建 PlistService.swift**

  ```swift
  import Foundation

  struct PlistService {

      func scanAll() -> (items: [LaunchItem], warnings: [String]) {
          var items: [LaunchItem] = []
          var warnings: [String] = []
          for scope in LaunchItem.Scope.allCases {
              let dir = scope.directoryURL
              guard let contents = try? FileManager.default.contentsOfDirectory(
                  at: dir, includingPropertiesForKeys: nil
              ) else { continue }
              for url in contents where url.pathExtension == "plist" {
                  if let item = parsePlist(at: url, scope: scope) {
                      items.append(item)
                  } else {
                      warnings.append(url.lastPathComponent)
                  }
              }
          }
          return (items, warnings)
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
                  if let h = ci.hour { d["Hour"] = h }
                  dict["StartCalendarInterval"] = d
              }
          case .interval:
              if let si = item.startInterval { dict["StartInterval"] = si }
          case .watchPath:
              if !item.watchPaths.isEmpty { dict["WatchPaths"] = item.watchPaths }
          case .atLoad:
              break
          }
          if item.runAtLoad { dict["RunAtLoad"] = true }
          if item.keepAlive { dict["KeepAlive"] = true }
          if let o = item.standardOutPath  { dict["StandardOutPath"]  = o }
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

- [ ] **Step 4: 运行测试，确认通过**

  ⌘U → Expected: 4 tests passed (LaunchctlServiceTests 4 + PlistServiceTests 4)

- [ ] **Step 5: Commit**

  ```bash
  git add LaunchManager/Services/PlistService.swift \
          LaunchManagerTests/PlistServiceTests.swift
  git commit -m "feat: add PlistService with parse/save/delete and tests"
  ```

---

## Task 6: AgentStore

**Files:**
- Create: `LaunchManager/Store/AgentStore.swift`

- [ ] **Step 1: 创建 AgentStore.swift**

  ```swift
  import Foundation

  @MainActor
  final class AgentStore: ObservableObject {
      @Published var items: [LaunchItem] = []
      @Published var warnings: [String] = []

      private let plistService    = PlistService()
      private let launchctlService = LaunchctlService()
      private let privilegeService = PrivilegeService()

      func refresh() {
          let (scanned, warns) = plistService.scanAll()
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
          warnings = warns
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
  }
  ```

- [ ] **Step 2: Commit**

  ```bash
  git add LaunchManager/Store/AgentStore.swift
  git commit -m "feat: add AgentStore ObservableObject"
  ```

---

## Task 7: ContentView + SidebarView

**Files:**
- Modify: `LaunchManager/Views/ContentView.swift`
- Create: `LaunchManager/Views/SidebarView.swift`

- [ ] **Step 1: 更新 LaunchManagerApp.swift**

  ```swift
  import SwiftUI

  @main
  struct LaunchManagerApp: App {
      var body: some Scene {
          WindowGroup {
              ContentView()
                  .frame(minWidth: 700, minHeight: 450)
          }
          .windowStyle(.titleBar)
          .windowToolbarStyle(.unified)
          .commands {
              CommandGroup(replacing: .newItem) { }
          }
      }
  }
  ```

- [ ] **Step 2: 创建 ContentView.swift**

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

      var body: some View {
          NavigationSplitView {
              SidebarView(selectedScope: $selectedScope, store: store)
          } detail: {
              AgentListView(
                  items: filteredItems,
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

- [ ] **Step 3: 创建 SidebarView.swift**

  ```swift
  import SwiftUI

  struct SidebarView: View {
      @Binding var selectedScope: LaunchItem.Scope?
      @ObservedObject var store: AgentStore

      var body: some View {
          List(LaunchItem.Scope.allCases, id: \.self, selection: $selectedScope) { scope in
              Label {
                  Text(scope.rawValue)
              } icon: {
                  Image(systemName: iconName(for: scope))
              }
              .badge(store.items.filter { $0.scope == scope }.count)
          }
          .listStyle(.sidebar)
          .navigationTitle("LaunchManager")
      }

      private func iconName(for scope: LaunchItem.Scope) -> String {
          switch scope {
          case .userAgent:    return "person.circle"
          case .systemAgent:  return "gearshape.circle"
          case .systemDaemon: return "server.rack"
          }
      }
  }
  ```

- [ ] **Step 4: Build 确认无编译错误**

  ⌘B → Expected: Build Succeeded（AgentListView / EditAgentSheet 占位符可先创建空结构体）

  如果 AgentListView / EditAgentSheet 尚不存在，先创建空占位：
  ```swift
  // AgentListView.swift
  import SwiftUI
  struct AgentListView: View {
      let items: [LaunchItem]
      @ObservedObject var store: AgentStore
      @Binding var showingNewAgent: Bool
      @Binding var errorMessage: String?
      var body: some View { Text("todo") }
  }

  // EditAgentSheet.swift
  import SwiftUI
  struct EditAgentSheet: View {
      let existingItem: LaunchItem?
      let defaultScope: LaunchItem.Scope
      @ObservedObject var store: AgentStore
      var body: some View { Text("todo") }
  }
  ```

- [ ] **Step 5: Commit**

  ```bash
  git add LaunchManager/LaunchManagerApp.swift \
          LaunchManager/Views/ContentView.swift \
          LaunchManager/Views/SidebarView.swift
  git commit -m "feat: add ContentView with NavigationSplitView and SidebarView"
  ```

---

## Task 8: AgentListView + AgentRowView

**Files:**
- Modify: `LaunchManager/Views/AgentListView.swift`
- Create: `LaunchManager/Views/AgentRowView.swift`

> LogViewerSheet / EditAgentSheet 在后面 Task 9/10 实现，这里先用空占位 Sheet。

- [ ] **Step 1: 创建 AgentRowView.swift**

  ```swift
  import SwiftUI

  struct AgentRowView: View {
      let item: LaunchItem
      @ObservedObject var store: AgentStore
      @Binding var errorMessage: String?

      @State private var isExpanded = false
      @State private var showingEdit = false
      @State private var showingLog  = false
      @State private var showingDeleteConfirm = false

      var statusColor: Color {
          if let code = item.lastExitCode, code != 0 { return .yellow }
          if item.pid != nil { return .green }
          return Color(nsColor: .tertiaryLabelColor)
      }

      var body: some View {
          VStack(alignment: .leading, spacing: 0) {
              // ── Collapsed header ──
              HStack(spacing: 8) {
                  Circle().fill(statusColor).frame(width: 8, height: 8)
                  Text(item.label)
                      .font(.system(.body, design: .monospaced))
                      .lineLimit(1)
                      .truncationMode(.middle)
                  Spacer()
                  primaryActionButton
                  Button { showingEdit = true } label: {
                      Image(systemName: "pencil")
                  }
                  .buttonStyle(.borderless)
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

              // ── Expanded detail ──
              if isExpanded {
                  Divider()
                  VStack(alignment: .leading, spacing: 4) {
                      detailRow("程序", ([item.program] + item.programArguments).joined(separator: " "))
                      detailRow("触发", triggerDescription)
                      detailRow("路径", item.plistURL.path)
                      HStack(spacing: 8) {
                          if item.isLoaded {
                              Button("卸载") { perform { try store.unload(item) } }
                                  .buttonStyle(.bordered)
                                  .controlSize(.small)
                          }
                          Button("查看日志") { showingLog = true }
                              .buttonStyle(.bordered)
                              .controlSize(.small)
                      }
                      .padding(.top, 4)
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
          .sheet(isPresented: $showingEdit) {
              EditAgentSheet(existingItem: item, defaultScope: item.scope, store: store)
          }
          .sheet(isPresented: $showingLog) {
              LogViewerSheet(item: item)
          }
          .confirmationDialog("确认删除 \(item.label)？", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
              Button("删除", role: .destructive) {
                  perform { try store.delete(item) }
              }
          } message: {
              Text("此操作将 unload 并永久删除 plist 文件，无法撤销。")
          }
      }

      @ViewBuilder
      private var primaryActionButton: some View {
          if item.pid != nil {
              Button("停止") { perform { try store.stop(item) } }
                  .buttonStyle(.borderedProminent).controlSize(.small)
          } else if item.isLoaded {
              Button("启动") { perform { try store.start(item) } }
                  .buttonStyle(.bordered).controlSize(.small)
          } else {
              Button("加载") { perform { try store.load(item) } }
                  .buttonStyle(.bordered).controlSize(.small)
          }
      }

      private func detailRow(_ label: String, _ value: String) -> some View {
          HStack(alignment: .top, spacing: 8) {
              Text(label)
                  .foregroundStyle(.secondary)
                  .frame(width: 36, alignment: .leading)
              Text(value)
                  .font(.system(.caption, design: .monospaced))
                  .textSelection(.enabled)
          }
          .font(.caption)
      }

      private var triggerDescription: String {
          switch item.triggerType {
          case .calendar:
              guard let ci = item.calendarInterval else { return "定时" }
              let day = ci.weekday.map { "周\($0)" } ?? "每天"
              let h   = ci.hour.map { String(format: "%02d", $0) } ?? "每小时"
              return "\(day) \(h):\(String(format: "%02d", ci.minute))"
          case .interval:
              return "每 \(item.startInterval ?? 0) 秒"
          case .atLoad:
              return "登录时"
          case .watchPath:
              return "监视路径：\(item.watchPaths.first ?? "")"
          }
      }

      private func perform(_ action: @escaping () throws -> Void) {
          do { try action() }
          catch { errorMessage = error.localizedDescription }
      }
  }
  ```

- [ ] **Step 2: 替换 AgentListView.swift**

  ```swift
  import SwiftUI

  struct AgentListView: View {
      let items: [LaunchItem]
      @ObservedObject var store: AgentStore
      @Binding var showingNewAgent: Bool
      @Binding var errorMessage: String?

      var body: some View {
          Group {
              if items.isEmpty {
                  ContentUnavailableView("没有 Agent", systemImage: "tray",
                      description: Text("此分类下暂无 LaunchAgent/Daemon"))
              } else {
                  ScrollView {
                      LazyVStack(spacing: 6) {
                          ForEach(items) { item in
                              AgentRowView(item: item, store: store, errorMessage: $errorMessage)
                          }
                      }
                      .padding()
                  }
              }
          }
          .safeAreaInset(edge: .bottom) {
              if !store.warnings.isEmpty {
                  HStack {
                      Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                      Text("解析失败：\(store.warnings.joined(separator: "、"))")
                          .font(.caption)
                      Spacer()
                  }
                  .padding(8)
                  .background(.yellow.opacity(0.12))
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

- [ ] **Step 3: Build 确认无编译错误**

  `LogViewerSheet` 还不存在，先保留空占位：
  ```swift
  // LogViewerSheet.swift
  import SwiftUI
  struct LogViewerSheet: View {
      let item: LaunchItem
      var body: some View { Text("日志功能开发中") }
  }
  ```

  ⌘B → Expected: Build Succeeded

- [ ] **Step 4: 运行 App，手动验证列表展示**

  ⌘R → 应看到侧边栏三个分类，点击某行可展开显示详情，「加载/停止/启动」按钮可见。

- [ ] **Step 5: Commit**

  ```bash
  git add LaunchManager/Views/AgentListView.swift \
          LaunchManager/Views/AgentRowView.swift \
          LaunchManager/Views/LogViewerSheet.swift
  git commit -m "feat: add AgentListView and AgentRowView with expand/collapse"
  ```

---

## Task 9: EditAgentSheet

**Files:**
- Modify: `LaunchManager/Views/EditAgentSheet.swift`

- [ ] **Step 1: 替换 EditAgentSheet.swift**

  ```swift
  import SwiftUI

  struct EditAgentSheet: View {
      let existingItem: LaunchItem?
      let defaultScope: LaunchItem.Scope
      @ObservedObject var store: AgentStore
      @Environment(\.dismiss) private var dismiss

      @State private var label: String
      @State private var program: String
      @State private var argumentsText: String
      @State private var triggerType: LaunchItem.TriggerType
      @State private var weekday: Int?
      @State private var hour: Int
      @State private var minute: Int
      @State private var startInterval: Int
      @State private var watchPath: String
      @State private var runAtLoad: Bool
      @State private var keepAlive: Bool
      @State private var stdoutPath: String
      @State private var stderrPath: String
      @State private var errorMessage: String?

      init(existingItem: LaunchItem?, defaultScope: LaunchItem.Scope, store: AgentStore) {
          self.existingItem = existingItem
          self.defaultScope = defaultScope
          self.store = store
          let i = existingItem
          _label         = State(initialValue: i?.label ?? "")
          _program       = State(initialValue: i?.program ?? "")
          _argumentsText = State(initialValue: i?.programArguments.joined(separator: "\n") ?? "")
          _triggerType   = State(initialValue: i?.triggerType ?? .atLoad)
          _weekday       = State(initialValue: i?.calendarInterval?.weekday)
          _hour          = State(initialValue: i?.calendarInterval?.hour ?? 8)
          _minute        = State(initialValue: i?.calendarInterval?.minute ?? 0)
          _startInterval = State(initialValue: i?.startInterval ?? 60)
          _watchPath     = State(initialValue: i?.watchPaths.first ?? "")
          _runAtLoad     = State(initialValue: i?.runAtLoad ?? false)
          _keepAlive     = State(initialValue: i?.keepAlive ?? false)
          _stdoutPath    = State(initialValue: i?.standardOutPath ?? "")
          _stderrPath    = State(initialValue: i?.standardErrorPath ?? "")
      }

      var body: some View {
          Form {
              Section("基本信息") {
                  TextField("Label（如 com.example.mytask）", text: $label)
                  HStack {
                      TextField("程序路径", text: $program)
                      Button("选择…") { pickProgram() }
                  }
                  VStack(alignment: .leading, spacing: 2) {
                      TextEditor(text: $argumentsText)
                          .font(.system(.body, design: .monospaced))
                          .frame(height: 64)
                          .overlay(RoundedRectangle(cornerRadius: 4)
                              .stroke(Color.secondary.opacity(0.3)))
                      Text("参数（每行一个）").font(.caption).foregroundStyle(.secondary)
                  }
              }

              Section("触发方式") {
                  Picker("类型", selection: $triggerType) {
                      ForEach(LaunchItem.TriggerType.allCases, id: \.self) {
                          Text($0.rawValue).tag($0)
                      }
                  }
                  .pickerStyle(.segmented)

                  switch triggerType {
                  case .calendar:
                      HStack {
                          Text("星期")
                          Picker("", selection: $weekday) {
                              Text("每天").tag(Int?.none)
                              ForEach(1...7, id: \.self) { d in
                                  Text(["","周一","周二","周三","周四","周五","周六","周日"][d])
                                      .tag(Int?.some(d))
                              }
                          }.frame(width: 80)
                          Spacer()
                          Text("时间")
                          TextField("时", value: $hour, format: .number).frame(width: 44)
                          Text(":")
                          TextField("分", value: $minute, format: .number).frame(width: 44)
                      }
                  case .interval:
                      HStack {
                          Text("每隔")
                          TextField("秒", value: $startInterval, format: .number).frame(width: 80)
                          Text("秒执行一次")
                      }
                  case .watchPath:
                      TextField("监视路径", text: $watchPath)
                  case .atLoad:
                      Text("登录或加载时执行一次").foregroundStyle(.secondary)
                  }
              }

              Section("选项") {
                  Toggle("加载时自动运行", isOn: $runAtLoad)
                  Toggle("保持存活（崩溃后自动重启）", isOn: $keepAlive)
              }

              Section("日志路径（可选）") {
                  TextField("标准输出 StandardOutPath", text: $stdoutPath)
                  TextField("标准错误 StandardErrorPath", text: $stderrPath)
              }
          }
          .formStyle(.grouped)
          .frame(minWidth: 500)
          .navigationTitle(existingItem == nil ? "新建 Agent" : "编辑 Agent")
          .toolbar {
              ToolbarItem(placement: .cancellationAction) {
                  Button("取消") { dismiss() }
              }
              ToolbarItem(placement: .confirmationAction) {
                  Button("保存") { saveItem() }
                      .disabled(label.isEmpty || program.isEmpty)
              }
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

      private func pickProgram() {
          let panel = NSOpenPanel()
          panel.canChooseFiles = true
          panel.canChooseDirectories = false
          if panel.runModal() == .OK, let url = panel.url {
              program = url.path
          }
      }

      private func saveItem() {
          let scope    = existingItem?.scope ?? defaultScope
          let args     = argumentsText.components(separatedBy: "\n").filter { !$0.isEmpty }
          let plistURL = existingItem?.plistURL ??
              scope.directoryURL.appendingPathComponent("\(label).plist")

          let item = LaunchItem(
              label: label, plistURL: plistURL, scope: scope,
              program: program, programArguments: args,
              triggerType: triggerType,
              calendarInterval: triggerType == .calendar
                  ? LaunchItem.CalendarInterval(weekday: weekday, hour: hour, minute: minute)
                  : nil,
              startInterval: triggerType == .interval ? startInterval : nil,
              watchPaths: triggerType == .watchPath ? [watchPath] : [],
              runAtLoad: runAtLoad, keepAlive: keepAlive,
              standardOutPath:  stdoutPath.isEmpty  ? nil : stdoutPath,
              standardErrorPath: stderrPath.isEmpty ? nil : stderrPath,
              isLoaded: existingItem?.isLoaded ?? false,
              pid: existingItem?.pid,
              lastExitCode: existingItem?.lastExitCode
          )
          do {
              try store.save(item)
              dismiss()
          } catch {
              errorMessage = error.localizedDescription
          }
      }
  }
  ```

- [ ] **Step 2: 运行 App 手动测试**

  1. 点击工具栏「+」新建
  2. 填写 Label: `com.test.hello`，程序: `/bin/echo`，参数: `hello`，触发: 登录时
  3. 点保存 → 应在 `~/Library/LaunchAgents/com.test.hello.plist` 生成文件
  4. 列表刷新后应出现该 agent

- [ ] **Step 3: Commit**

  ```bash
  git add LaunchManager/Views/EditAgentSheet.swift
  git commit -m "feat: add EditAgentSheet with full form and file picker"
  ```

---

## Task 10: LogViewerSheet

**Files:**
- Modify: `LaunchManager/Views/LogViewerSheet.swift`

- [ ] **Step 1: 替换 LogViewerSheet.swift**

  ```swift
  import SwiftUI

  struct LogViewerSheet: View {
      let item: LaunchItem
      @Environment(\.dismiss) private var dismiss

      @State private var selectedTab     = 0
      @State private var fileLogContent  = ""
      @State private var systemLogContent = ""
      @State private var filterText      = ""
      @State private var isLoadingSystem = false

      var filteredSystemLog: String {
          guard !filterText.isEmpty else { return systemLogContent }
          return systemLogContent
              .components(separatedBy: "\n")
              .filter { $0.localizedCaseInsensitiveContains(filterText) }
              .joined(separator: "\n")
      }

      var body: some View {
          VStack(spacing: 0) {
              Picker("", selection: $selectedTab) {
                  Text("文件日志").tag(0)
                  Text("系统日志").tag(1)
              }
              .pickerStyle(.segmented)
              .padding()

              Divider()

              if selectedTab == 0 { fileLogTab } else { systemLogTab }
          }
          .frame(minWidth: 620, minHeight: 420)
          .navigationTitle("日志 — \(item.label)")
          .toolbar {
              ToolbarItem(placement: .confirmationAction) {
                  Button("关闭") { dismiss() }
              }
          }
          .onAppear {
              loadFileLog()
              loadSystemLog()
          }
      }

      // ── File Log Tab ──────────────────────────────────────
      @ViewBuilder
      private var fileLogTab: some View {
          if item.standardOutPath == nil && item.standardErrorPath == nil {
              ContentUnavailableView(
                  "未配置日志文件路径",
                  systemImage: "doc.text.slash",
                  description: Text("在编辑 Agent 时填写 StandardOutPath / StandardErrorPath 即可启用。")
              )
          } else {
              VStack(spacing: 0) {
                  ScrollView {
                      Text(fileLogContent.isEmpty ? "（日志为空）" : fileLogContent)
                          .font(.system(.caption, design: .monospaced))
                          .textSelection(.enabled)
                          .frame(maxWidth: .infinity, alignment: .leading)
                          .padding()
                  }
                  Divider()
                  HStack {
                      Spacer()
                      Button("清空日志") { clearFileLog() }
                          .padding(8)
                  }
              }
          }
      }

      // ── System Log Tab ────────────────────────────────────
      @ViewBuilder
      private var systemLogTab: some View {
          VStack(spacing: 0) {
              HStack {
                  Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                  TextField("过滤关键字", text: $filterText)
                      .textFieldStyle(.roundedBorder)
                  if isLoadingSystem { ProgressView().scaleEffect(0.7) }
                  Button { loadSystemLog() } label: {
                      Image(systemName: "arrow.clockwise")
                  }
              }
              .padding(.horizontal).padding(.vertical, 6)
              Divider()
              ScrollView {
                  Text(filteredSystemLog.isEmpty ? "（无日志）" : filteredSystemLog)
                      .font(.system(.caption, design: .monospaced))
                      .textSelection(.enabled)
                      .frame(maxWidth: .infinity, alignment: .leading)
                      .padding()
              }
          }
      }

      // ── Helpers ───────────────────────────────────────────
      private func loadFileLog() {
          var content = ""
          if let path = item.standardOutPath,
             let text = try? String(contentsOfFile: path) {
              content += "=== stdout (\(path)) ===\n\(text)\n"
          }
          if let path = item.standardErrorPath,
             let text = try? String(contentsOfFile: path) {
              content += "=== stderr (\(path)) ===\n\(text)\n"
          }
          fileLogContent = content
      }

      private func loadSystemLog() {
          isLoadingSystem = true
          DispatchQueue.global(qos: .userInitiated).async {
              let process = Process()
              process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
              process.arguments = [
                  "show",
                  "--predicate",
                  "subsystem == \"\(item.label)\" OR process == \"\(item.label)\"",
                  "--last", "1h",
                  "--style", "compact"
              ]
              let pipe = Pipe()
              process.standardOutput = pipe
              process.standardError  = pipe
              try? process.run()
              process.waitUntilExit()
              let output = String(
                  data: pipe.fileHandleForReading.readDataToEndOfFile(),
                  encoding: .utf8) ?? ""
              DispatchQueue.main.async {
                  self.systemLogContent = output
                  self.isLoadingSystem  = false
              }
          }
      }

      private func clearFileLog() {
          if let path = item.standardOutPath  { try? "".write(toFile: path, atomically: true, encoding: .utf8) }
          if let path = item.standardErrorPath { try? "".write(toFile: path, atomically: true, encoding: .utf8) }
          loadFileLog()
      }
  }
  ```

- [ ] **Step 2: 运行 App，验证日志 Sheet**

  1. 展开一个已有日志路径的 agent（如之前创建的 `com.syncthing.start`）
  2. 点击「查看日志」→ Sheet 弹出
  3. 切换「文件日志」Tab：若配置了路径，应显示内容
  4. 切换「系统日志」Tab：加载中动画后显示 `log show` 输出
  5. 在过滤框输入关键字，确认实时过滤生效

- [ ] **Step 3: Commit**

  ```bash
  git add LaunchManager/Views/LogViewerSheet.swift
  git commit -m "feat: add LogViewerSheet with file and system log tabs"
  ```

---

## Task 11: 收尾 — README 与测试全跑

**Files:**
- Create: `README.md`

- [ ] **Step 1: 全量运行测试**

  ⌘U → Expected: 全部 8 个测试通过

- [ ] **Step 2: 手动端到端测试清单**

  1. **新建用户 Agent**：Label `com.test.e2e`，程序 `/bin/date`，登录时触发 → 保存 → plist 出现在 `~/Library/LaunchAgents/`
  2. **加载**：点「加载」→ 状态变绿（或灰，取决于触发类型）
  3. **手动启动**：点「启动」→ 状态变绿，PID 出现
  4. **停止**：点「停止」→ PID 消失
  5. **编辑**：点铅笔图标 → 修改程序参数 → 保存 → plist 文件更新
  6. **删除**：展开行 → 卸载 → 折叠 → 点删除 → 确认 → plist 消失，列表刷新
  7. **系统 Agent 读取**：侧边栏切换到「系统 Agents」→ 能看到 `/Library/LaunchAgents/` 下的列表（只读权限时加载可能需要密码）
  8. **警告行**：手动创建一个格式损坏的 plist → 底部出现黄色警告条

- [ ] **Step 3: 创建 README.md**

  ```markdown
  # LaunchManager

  免费开源的 macOS launchd 可视化管理工具，功能对标 Lingon X。

  ## 功能

  - 列出并查看 User LaunchAgents / System LaunchAgents / LaunchDaemons 及运行状态
  - 一键加载 / 卸载 / 启动 / 停止
  - 表单新建、编辑 Agent（支持定时/间隔/登录时/监视路径四种触发方式）
  - 删除 plist 文件
  - 查看文件日志（stdout/stderr）与系统日志（log show）
  - 系统级操作自动请求管理员授权（osascript）

  ## 要求

  - macOS 13 Ventura 及以上

  ## 构建

  用 Xcode 打开 `LaunchManager.xcodeproj`，⌘R 运行即可。无需第三方依赖。

  ## 许可

  MIT
  ```

- [ ] **Step 4: 最终 Commit**

  ```bash
  git add README.md
  git commit -m "docs: add README"
  git tag v0.1.0
  ```

---

## 注意事项

- **launchctl load/unload 在 macOS 13+ 已软弃用**（官方推荐 `launchctl bootstrap`），但目前仍可用。若将来需要升级，只需改 `LaunchctlService` 里的命令，不影响其他代码。
- **系统日志 Tab** 的 `log show` 可能需要授予「完全磁盘访问权限」才能读取所有进程日志（系统设置 → 隐私与安全性 → 完全磁盘访问权限）。
- **PrivilegeService** 中 osascript 的密码缓存由 macOS 管理，通常约 5 分钟内不重复弹窗。
