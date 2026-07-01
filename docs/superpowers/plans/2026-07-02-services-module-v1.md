# Services 模块 v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 LaunchManager 新增 Services 模块：自动扫描本地监听端口、三层识别 dev 服务、智能过滤列表、展示健康状态，并提供 Open / Copy URL / Reveal / Kill 操作。

**Architecture:** `ProcessDiscoveryService` 通过 `lsof`+`ps` 产出 `ListeningProcess[]`；`ServiceClassifier` 串联 Executable / CommandLine / Project 三个 Resolver enrich 为 `Service`；`DevServiceFilter` 按 heuristics 过滤；`ServiceStore`（`@MainActor`）每 3s 后台 scan 并 diff 更新 UI。

**Tech Stack:** Swift 5.10, SwiftUI, XCTest, Darwin kill(2), ShellRunner, String Catalog, macOS 14+

**Spec:** `docs/superpowers/specs/2026-07-02-services-module-design.md`

---

## File Map

| 操作 | 文件 | 职责 |
|------|------|------|
| Create | `LaunchManager/Models/ServiceHealth.swift` | 健康状态枚举 |
| Create | `LaunchManager/Models/ListeningProcess.swift` | 扫描原始模型 |
| Create | `LaunchManager/Models/Service.swift` | 业务服务模型 + ServiceCategory |
| Create | `LaunchManager/Services/ProcessDiscoveryService.swift` | lsof/ps 扫描与解析 |
| Create | `LaunchManager/Services/ServiceResolvers/ResolverTypes.swift` | ClassificationHit |
| Create | `LaunchManager/Services/ServiceResolvers/ExecutableResolver.swift` | L1 可执行文件识别 |
| Create | `LaunchManager/Services/ServiceResolvers/CommandLineResolver.swift` | L2 argv 识别 |
| Create | `LaunchManager/Services/ServiceResolvers/ProjectResolver.swift` | L3 项目名识别 |
| Create | `LaunchManager/Services/ServiceClassifier.swift` | Resolver 管道编排 |
| Create | `LaunchManager/Services/DevServiceFilter.swift` | 智能过滤 |
| Create | `LaunchManager/Services/ProcessKillService.swift` | SIGTERM → SIGKILL |
| Create | `LaunchManager/Store/ServiceStore.swift` | ObservableObject + timer |
| Create | `LaunchManager/Views/ServicesListView.swift` | 列表页 |
| Create | `LaunchManager/Views/ServiceRowView.swift` | 单行 + 菜单 |
| Create | `LaunchManager/Views/KillConfirmSheet.swift` | Kill 确认 |
| Modify | `LaunchManager/Models/SidebarSelection.swift` | 新增 `.services` |
| Modify | `LaunchManager/Views/SidebarView.swift` | 底部 Services 入口 |
| Modify | `LaunchManager/ContentView.swift` | 路由 + ServiceStore |
| Modify | `LaunchManager/Localizable.xcstrings` | Services 相关文案 en |
| Modify | `LaunchManagerTests/LaunchManagerTests.swift` | 全部单元测试 |

> 项目使用 `PBXFileSystemSynchronizedRootGroup`，新建 Swift 文件放入 `LaunchManager/` 目录即可，无需手动改 `project.pbxproj`。

---

### Task 1: 基础模型

**Files:**
- Create: `LaunchManager/Models/ServiceHealth.swift`
- Create: `LaunchManager/Models/ListeningProcess.swift`
- Create: `LaunchManager/Models/Service.swift`

- [ ] **Step 1: 创建 ServiceHealth.swift**

```swift
import Foundation

enum ServiceHealth: String, Equatable {
    case healthy
    case down
    case unknown
}
```

- [ ] **Step 2: 创建 ListeningProcess.swift**

```swift
import Foundation

struct ListeningProcess: Identifiable, Hashable, Sendable {
    var id: String { "\(pid)-\(port)-\(protocolName)" }
    let pid: Int32
    let port: Int
    let protocolName: String
    let command: String
    let executable: String
    let workingDirectory: String?
}
```

- [ ] **Step 3: 创建 Service.swift**

```swift
import Foundation

enum ServiceCategory: String, Equatable, Sendable {
    case web, database, cache, ai, proxy, other
}

struct Service: Identifiable, Hashable, Sendable {
    var id: String { "\(pid)-\(port)" }
    let displayName: String
    let subtitle: String?
    let category: ServiceCategory
    let health: ServiceHealth
    let port: Int
    let host: String
    let pid: Int32
    let executable: String
    let command: String
    let workingDirectory: String?
    let url: URL?

    var addressLabel: String {
        if let url { return url.absoluteString }
        return "\(host):\(port)"
    }
}
```

- [ ] **Step 4: 编译**

```bash
cd /Users/sean/LaunchManager/LaunchManager
xcodebuild build -project LaunchManager.xcodeproj -scheme LaunchManager -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```

预期：`BUILD SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add LaunchManager/Models/ServiceHealth.swift \
        LaunchManager/Models/ListeningProcess.swift \
        LaunchManager/Models/Service.swift
git commit -m "feat(services): add Service, ListeningProcess, ServiceHealth models"
```

---

### Task 2: ProcessDiscoveryService — lsof 输出解析

**Files:**
- Create: `LaunchManager/Services/ProcessDiscoveryService.swift`
- Modify: `LaunchManagerTests/LaunchManagerTests.swift`

- [ ] **Step 1: 写失败测试 — parseLsofOutput**

在 `LaunchManagerTests.swift` 末尾添加：

```swift
// MARK: - ProcessDiscoveryService Tests

final class ProcessDiscoveryServiceTests: XCTestCase {
    let svc = ProcessDiscoveryService(shell: NoopShell())

    func test_parseLsofOutput_extractsPidPortExecutable() {
        let output = """
        COMMAND   PID USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        node    12345 sean   21u  IPv4 0xdeadbeef      0t0  TCP *:3000 (LISTEN)
        Python  67890 sean    3u  IPv4 0xbeefdead      0t0  TCP 127.0.0.1:8000 (LISTEN)
        """
        let rows = svc.parseLsofOutput(output)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].pid, 12345)
        XCTAssertEqual(rows[0].port, 3000)
        XCTAssertEqual(rows[0].executable, "node")
        XCTAssertEqual(rows[1].pid, 67890)
        XCTAssertEqual(rows[1].port, 8000)
        XCTAssertEqual(rows[1].executable, "Python")
    }

    func test_parseLsofOutput_skipsHeaderAndNonListen() {
        let output = """
        COMMAND   PID USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        """
        XCTAssertTrue(svc.parseLsofOutput(output).isEmpty)
    }

    func test_extractPort_parsesIPv6() {
        XCTAssertEqual(ProcessDiscoveryService.extractPort(from: "[::1]:5432"), 5432)
        XCTAssertEqual(ProcessDiscoveryService.extractPort(from: "*:6379"), 6379)
        XCTAssertNil(ProcessDiscoveryService.extractPort(from: "*:bonjour"))
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
cd /Users/sean/LaunchManager/LaunchManager
xcodebuild test -project LaunchManager.xcodeproj -scheme LaunchManager -destination 'platform=macOS' -only-testing LaunchManagerTests/ProcessDiscoveryServiceTests 2>&1 | grep -E "error:|Test Case|BUILD SUCCEEDED|BUILD FAILED|passed|failed"
```

预期：FAIL — `ProcessDiscoveryService` 未定义

- [ ] **Step 3: 实现 ProcessDiscoveryService（解析部分）**

```swift
import Foundation

struct LsofRow: Equatable {
    let pid: Int32
    let port: Int
    let executable: String
}

final class ProcessDiscoveryService: Sendable {
    private let shell: ShellRunner

    init(shell: ShellRunner = DefaultShellRunner()) {
        self.shell = shell
    }

    static func extractPort(from nameField: String) -> Int? {
        let trimmed = nameField.replacingOccurrences(of: " (LISTEN)", with: "")
        guard let colon = trimmed.lastIndex(of: ":") else { return nil }
        let portStr = String(trimmed[trimmed.index(after: colon)...])
        return Int(portStr)
    }

    func parseLsofOutput(_ output: String) -> [LsofRow] {
        var rows: [LsofRow] = []
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let s = String(line)
            if s.hasPrefix("COMMAND") { continue }
            let parts = s.split(whereSeparator: { $0.isWhitespace })
            guard parts.count >= 9 else { continue }
            guard let pid = Int32(parts[1]) else { continue }
            let executable = String(parts[0])
            let nameField = parts[8...].joined(separator: " ")
            guard nameField.contains("(LISTEN)") else { continue }
            guard let port = Self.extractPort(from: nameField) else { continue }
            rows.append(LsofRow(pid: pid, port: port, executable: executable))
        }
        return rows
    }
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
xcodebuild test -project LaunchManager.xcodeproj -scheme LaunchManager -destination 'platform=macOS' -only-testing LaunchManagerTests/ProcessDiscoveryServiceTests 2>&1 | grep -E "Test Case|passed|failed|BUILD"
```

预期：3 tests passed

- [ ] **Step 5: Commit**

```bash
git add LaunchManager/Services/ProcessDiscoveryService.swift LaunchManagerTests/LaunchManagerTests.swift
git commit -m "feat(services): add lsof output parser with tests"
```

---

### Task 3: ProcessDiscoveryService — 完整 scan + ps + cwd

**Files:**
- Modify: `LaunchManager/Services/ProcessDiscoveryService.swift`
- Modify: `LaunchManagerTests/LaunchManagerTests.swift`

- [ ] **Step 1: 写失败测试 — buildProcesses**

```swift
private struct FakeDiscoveryShell: ShellRunner, @unchecked Sendable {
    let lsofOutput: String
    var psResponses: [Int32: String] = [:]
    var cwdResponses: [Int32: String] = [:]

    func run(_ path: String, arguments: [String]) throws -> String {
        if path == "/usr/sbin/lsof" && arguments.contains("-iTCP") {
            return lsofOutput
        }
        if path == "/bin/ps", let pidStr = arguments.last, let pid = Int32(pidStr) {
            return psResponses[pid] ?? ""
        }
        if path == "/usr/sbin/lsof", arguments.contains("-d"), arguments.contains("cwd") {
            if let pIndex = arguments.firstIndex(of: "-p"), pIndex + 1 < arguments.count,
               let pid = Int32(arguments[pIndex + 1]) {
                if let cwd = cwdResponses[pid] { return "n\(cwd)\n" }
            }
        }
        return ""
    }
}

extension ProcessDiscoveryServiceTests {
    func test_buildProcesses_enrichesCommandAndCwd() throws {
        let lsof = """
        COMMAND   PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
        node    100 sean   21u  IPv4 0x0      0t0  TCP *:3000 (LISTEN)
        """
        let shell = FakeDiscoveryShell(
            lsofOutput: lsof,
            psResponses: [100: "node /usr/local/bin/next dev"],
            cwdResponses: [100: "/Users/sean/blog/frontend"]
        )
        let svc = ProcessDiscoveryService(shell: shell)
        let processes = try svc.scan()
        XCTAssertEqual(processes.count, 1)
        XCTAssertEqual(processes[0].command, "node /usr/local/bin/next dev")
        XCTAssertEqual(processes[0].workingDirectory, "/Users/sean/blog/frontend")
        XCTAssertEqual(processes[0].executable, "node")
    }

    func test_healthCheck_aliveProcess() {
        XCTAssertTrue(ProcessDiscoveryService.isProcessAlive(pid: getpid()))
        XCTAssertFalse(ProcessDiscoveryService.isProcessAlive(pid: 999_999))
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
xcodebuild test -project LaunchManager.xcodeproj -scheme LaunchManager -destination 'platform=macOS' -only-testing LaunchManagerTests/ProcessDiscoveryServiceTests/test_buildProcesses_enrichesCommandAndCwd 2>&1 | grep -E "error:|failed|passed"
```

- [ ] **Step 3: 实现 scan() + ProcessScanning protocol**

在 `ProcessDiscoveryService.swift` 追加：

```swift
protocol ProcessScanning: Sendable {
    func scan() throws -> [ListeningProcess]
}

extension ProcessDiscoveryService: ProcessScanning {
    static func isProcessAlive(pid: Int32) -> Bool {
        kill(pid, 0) == 0
    }

    func scan() throws -> [ListeningProcess] {
        let lsofOut = try shell.run("/usr/sbin/lsof", arguments: [
            "-iTCP", "-sTCP:LISTEN", "-nP"
        ])
        let rows = parseLsofOutput(lsofOut)
        var seen = Set<String>()
        var result: [ListeningProcess] = []

        for row in rows {
            let key = "\(row.pid)-\(row.port)"
            guard seen.insert(key).inserted else { continue }
            guard Self.isProcessAlive(pid: row.pid) else { continue }

            let command = (try? shell.run("/bin/ps", arguments: ["-p", "\(row.pid)", "-o", "command="]))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? row.executable

            let cwdOut = (try? shell.run("/usr/sbin/lsof", arguments: [
                "-a", "-p", "\(row.pid)", "-d", "cwd", "-Fn"
            ])) ?? ""
            let cwd = cwdOut.split(separator: "\n")
                .first(where: { $0.hasPrefix("n") })
                .map { String($0.dropFirst()) }

            result.append(ListeningProcess(
                pid: row.pid,
                port: row.port,
                protocolName: "tcp",
                command: command,
                executable: row.executable,
                workingDirectory: cwd
            ))
        }
        return result.sorted { $0.port < $1.port }
    }
}
```

- [ ] **Step 4: 运行全部 ProcessDiscoveryServiceTests + Commit**

```bash
xcodebuild test -project LaunchManager.xcodeproj -scheme LaunchManager -destination 'platform=macOS' -only-testing LaunchManagerTests/ProcessDiscoveryServiceTests 2>&1 | grep -E "Test Case|passed|failed"
git add LaunchManager/Services/ProcessDiscoveryService.swift LaunchManagerTests/LaunchManagerTests.swift
git commit -m "feat(services): add full process discovery scan with ps and cwd"
```

---

### Task 4: Service Resolvers (L1 / L2 / L3)

**Files:**
- Create: `LaunchManager/Services/ServiceResolvers/ResolverTypes.swift`
- Create: `LaunchManager/Services/ServiceResolvers/ExecutableResolver.swift`
- Create: `LaunchManager/Services/ServiceResolvers/CommandLineResolver.swift`
- Create: `LaunchManager/Services/ServiceResolvers/ProjectResolver.swift`
- Modify: `LaunchManagerTests/LaunchManagerTests.swift`

- [ ] **Step 1: 写 Resolver 失败测试**

```swift
// MARK: - Service Resolver Tests

final class ServiceResolverTests: XCTestCase {
    func test_commandLineResolver_nextJs() {
        let hit = CommandLineResolver().resolve(command: "node /path/next dev --port 3000")
        XCTAssertEqual(hit?.displayName, "Next.js")
        XCTAssertEqual(hit?.category, .web)
    }

    func test_commandLineResolver_uvicorn() {
        let hit = CommandLineResolver().resolve(command: "uvicorn app.main:app --reload")
        XCTAssertEqual(hit?.displayName, "FastAPI")
    }

    func test_executableResolver_redis() {
        let hit = ExecutableResolver().resolve(executable: "redis-server")
        XCTAssertEqual(hit?.displayName, "Redis")
        XCTAssertEqual(hit?.category, .cache)
    }

    func test_projectResolver_packageJson() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try #"{"name":"blog-frontend"}"#.write(to: dir.appendingPathComponent("package.json"),
                                               atomically: true, encoding: .utf8)
        let name = ProjectResolver().resolve(workingDirectory: dir.path)
        XCTAssertEqual(name, "blog-frontend")
    }
}
```

- [ ] **Step 2: 实现 ResolverTypes + 三个 Resolver**

`ResolverTypes.swift`:

```swift
import Foundation

struct ClassificationHit: Equatable {
    var displayName: String
    var category: ServiceCategory
    var generatesURL: Bool
}
```

`ExecutableResolver.swift` — map: node, python, python3, redis-server, postgres, mongod, ollama, nginx, docker-proxy（见 spec）。

`CommandLineResolver.swift` — rules: next dev/start→Next.js, vite→Vite, nuxt→Nuxt, uvicorn→FastAPI, gunicorn→Flask, manage.py runserver→Django, cargo run→Rust, go run→Go。

`ProjectResolver.swift` — 读取 package.json / pyproject.toml / Cargo.toml 的 name 字段。

- [ ] **Step 3: 运行测试 + Commit**

```bash
xcodebuild test -project LaunchManager.xcodeproj -scheme LaunchManager -destination 'platform=macOS' -only-testing LaunchManagerTests/ServiceResolverTests 2>&1 | grep -E "passed|failed"
git add LaunchManager/Services/ServiceResolvers/ LaunchManagerTests/LaunchManagerTests.swift
git commit -m "feat(services): add L1/L2/L3 classification resolvers with tests"
```

---

### Task 5: ServiceClassifier + DevServiceFilter

**Files:**
- Create: `LaunchManager/Services/ServiceClassifier.swift`
- Create: `LaunchManager/Services/DevServiceFilter.swift`
- Modify: `LaunchManagerTests/LaunchManagerTests.swift`

- [ ] **Step 1: 写失败测试**

```swift
final class ServiceClassifierTests: XCTestCase {
    func test_classify_nextJs() {
        let p = ListeningProcess(
            pid: 1, port: 3000, protocolName: "tcp",
            command: "node next dev", executable: "node",
            workingDirectory: nil
        )
        let svc = ServiceClassifier().classify(p)
        XCTAssertEqual(svc.displayName, "Next.js")
        XCTAssertEqual(svc.url?.port, 3000)
        XCTAssertEqual(svc.health, .healthy)
    }
}

final class DevServiceFilterTests: XCTestCase {
    func test_devPort_passes() {
        let s = makeService(port: 5432, executable: "postgres", displayName: "PostgreSQL")
        XCTAssertTrue(DevServiceFilter().isDevService(s))
    }

    func test_unknownSystemPort_filtered() {
        let s = makeService(port: 5353, executable: "mDNSResponder", displayName: "mDNSResponder")
        XCTAssertFalse(DevServiceFilter().isDevService(s))
    }

    private func makeService(port: Int, executable: String, displayName: String) -> Service {
        Service(displayName: displayName, subtitle: nil, category: .other,
                health: .healthy, port: port, host: "localhost", pid: 1,
                executable: executable, command: executable,
                workingDirectory: nil, url: nil)
    }
}
```

- [ ] **Step 2: 实现 ServiceClassifier**

```swift
struct ServiceClassifier {
    private let executable = ExecutableResolver()
    private let commandLine = CommandLineResolver()
    private let project = ProjectResolver()

    func classify(_ process: ListeningProcess) -> Service {
        let cmdHit = commandLine.resolve(command: process.command)
        let exeHit = executable.resolve(executable: process.executable)
        let hit = cmdHit ?? exeHit

        let displayName = hit?.displayName ?? process.executable
        let category = hit?.category ?? .other
        let subtitle = project.resolve(workingDirectory: process.workingDirectory)
        let url: URL? = (hit?.generatesURL == true)
            ? URL(string: "http://localhost:\(process.port)")
            : nil
        let health: ServiceHealth = ProcessDiscoveryService.isProcessAlive(pid: process.pid)
            ? .healthy : .down

        return Service(
            displayName: displayName, subtitle: subtitle, category: category,
            health: health, port: process.port, host: "localhost",
            pid: process.pid, executable: process.executable,
            command: process.command, workingDirectory: process.workingDirectory, url: url
        )
    }

    func classifyAll(_ processes: [ListeningProcess]) -> [Service] {
        processes.map(classify)
    }
}
```

- [ ] **Step 3: 实现 DevServiceFilter**（devPorts / devExecutables / devFrameworkNames 见 spec）

- [ ] **Step 4: 测试 + Commit**

```bash
xcodebuild test -project LaunchManager.xcodeproj -scheme LaunchManager -destination 'platform=macOS' -only-testing LaunchManagerTests/ServiceClassifierTests -only-testing LaunchManagerTests/DevServiceFilterTests 2>&1 | grep -E "passed|failed"
git add LaunchManager/Services/ServiceClassifier.swift LaunchManager/Services/DevServiceFilter.swift LaunchManagerTests/LaunchManagerTests.swift
git commit -m "feat(services): add ServiceClassifier and DevServiceFilter"
```

---

### Task 6: ProcessKillService

**Files:**
- Create: `LaunchManager/Services/ProcessKillService.swift`
- Modify: `LaunchManagerTests/LaunchManagerTests.swift`

- [ ] **Step 1: 测试 isKillable + 实现 ProcessKillService**

```swift
enum ProcessKillError: LocalizedError {
    case notKillable(pid: Int32)
    case signalFailed(pid: Int32, errno: Int32)

    var errorDescription: String? {
        switch self {
        case .notKillable(let pid): return "无法终止 PID \(pid)：权限不足"
        case .signalFailed(let pid, _): return "无法向 PID \(pid) 发送信号"
        }
    }
}

struct ProcessKillService: Sendable {
    static func isKillable(pid: Int32) -> Bool { kill(pid, 0) == 0 }

    func kill(pid: Int32, termTimeoutSeconds: Double = 5) async throws {
        guard Self.isKillable(pid: pid) else { throw ProcessKillError.notKillable(pid: pid) }
        if kill(pid, SIGTERM) != 0 { throw ProcessKillError.signalFailed(pid: pid, errno: errno) }
        let deadline = Date().addingTimeInterval(termTimeoutSeconds)
        while Date() < deadline {
            if !Self.isKillable(pid: pid) { return }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        if Self.isKillable(pid: pid) { kill(pid, SIGKILL) }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add LaunchManager/Services/ProcessKillService.swift LaunchManagerTests/LaunchManagerTests.swift
git commit -m "feat(services): add ProcessKillService with SIGTERM fallback"
```

---

### Task 7: ServiceStore

**Files:**
- Create: `LaunchManager/Store/ServiceStore.swift`

- [ ] **Step 1: 实现 ServiceStore**

```swift
@MainActor
final class ServiceStore: ObservableObject {
    @Published private(set) var services: [Service] = []
    @Published private(set) var pendingKillIDs: Set<String> = []
    @Published var lastScanError: String?
    @Published var showAll: Bool {
        didSet { UserDefaults.standard.set(showAll, forKey: "servicesShowAll") }
    }

    private let discovery: ProcessScanning
    private let classifier = ServiceClassifier()
    private let filter = DevServiceFilter()
    private let killer = ProcessKillService()
    private var timerTask: Task<Void, Never>?

    init(discovery: ProcessScanning = ProcessDiscoveryService()) {
        self.discovery = discovery
        self.showAll = UserDefaults.standard.bool(forKey: "servicesShowAll")
    }

    func startPolling(isActive: Bool) {
        timerTask?.cancel()
        guard isActive else { return }
        timerTask = Task {
            while !Task.isCancelled {
                refresh()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    func refresh() {
        Task {
            do {
                let processes = try await Task.detached { try self.discovery.scan() }.value
                let classified = self.classifier.classifyAll(processes)
                let filtered = self.filter.filter(classified, showAll: self.showAll)
                await MainActor.run {
                    self.services = filtered
                    self.lastScanError = nil
                }
            } catch {
                await MainActor.run { self.lastScanError = error.localizedDescription }
            }
        }
    }

    func kill(_ service: Service, onError: @escaping (String) -> Void) {
        guard !pendingKillIDs.contains(service.id) else { return }
        pendingKillIDs.insert(service.id)
        Task {
            do {
                try await killer.kill(pid: service.pid)
                pendingKillIDs.remove(service.id)
                refresh()
            } catch {
                pendingKillIDs.remove(service.id)
                onError(error.localizedDescription)
            }
        }
    }
}
```

- [ ] **Step 2: 编译 + Commit**

```bash
xcodebuild build -project LaunchManager.xcodeproj -scheme LaunchManager -destination 'platform=macOS' 2>&1 | grep -E "BUILD SUCCEEDED|error:"
git add LaunchManager/Store/ServiceStore.swift
git commit -m "feat(services): add ServiceStore with polling and kill"
```

---

### Task 8: 导航集成

**Files:**
- Modify: `LaunchManager/Models/SidebarSelection.swift`
- Modify: `LaunchManager/Views/SidebarView.swift`
- Modify: `LaunchManager/ContentView.swift`
- Create: `LaunchManager/Views/ServicesListView.swift`（占位）

- [ ] **Step 1:** `SidebarSelection` 加 `.services`
- [ ] **Step 2:** `SidebarView` 底部 Section 加 Services 行（icon: `bolt.fill`，subtitle: `本地开发环境`）
- [ ] **Step 3:** `ContentView` 加 `@StateObject serviceStore`、`@Environment(\.scenePhase)`、detail 路由、polling 生命周期
- [ ] **Step 4: Commit**

```bash
git add LaunchManager/Models/SidebarSelection.swift LaunchManager/Views/SidebarView.swift LaunchManager/ContentView.swift LaunchManager/Views/ServicesListView.swift
git commit -m "feat(services): wire Services into sidebar navigation"
```

---

### Task 9: ServicesListView + ServiceRowView

**Files:**
- Modify: `LaunchManager/Views/ServicesListView.swift`
- Create: `LaunchManager/Views/ServiceRowView.swift`

- [ ] **Step 1:** `ServicesListView` — 列表、searchable、toolbar（显示全部 Toggle + 刷新 + 扫描错误 icon）、空状态
- [ ] **Step 2:** `ServiceRowView` — 状态点、displayName/subtitle/address、Open/Copy 主按钮、`···` 菜单四项、Kill sheet 触发
- [ ] **Step 3: Commit**

```bash
git add LaunchManager/Views/ServicesListView.swift LaunchManager/Views/ServiceRowView.swift
git commit -m "feat(services): add ServicesListView and ServiceRowView"
```

---

### Task 10: KillConfirmSheet + 本地化

**Files:**
- Create: `LaunchManager/Views/KillConfirmSheet.swift`
- Modify: `LaunchManager/Localizable.xcstrings`

- [ ] **Step 1:** KillConfirmSheet — 展示 name/address/PID/cwd，取消 + 终止进程(destructive)
- [ ] **Step 2:** Localizable 添加 en 译文：Services, 本地开发环境, 没有发现开发服务, 显示全部, 确认终止服务？, 终止进程, Open in Browser, Copy URL, Reveal in Finder, Kill Process…
- [ ] **Step 3: Commit**

```bash
git add LaunchManager/Views/KillConfirmSheet.swift LaunchManager/Localizable.xcstrings
git commit -m "feat(services): add KillConfirmSheet and localization strings"
```

---

### Task 11: 全量测试 + 手动验证

- [ ] **Step 1: 运行全部测试**

```bash
xcodebuild test -project LaunchManager.xcodeproj -scheme LaunchManager -destination 'platform=macOS' 2>&1 | grep -E "Test Suite|passed|failed|BUILD"
```

- [ ] **Step 2: 手动验证清单**

1. 侧边栏底部可见 Services
2. `python3 -m http.server 8000` → 列表出现 Python localhost:8000
3. Next/Vite 项目 → 显示框架名 + subtitle
4. 「显示全部」→ 更多系统服务
5. 搜索 `8000` → 过滤正确
6. Open / Copy / Reveal / Kill 均正常
7. app 后台/前台切换 scan 正常

- [ ] **Step 3: 最终 commit（如有测试补全）**

---

## Spec Coverage

| Spec 要求 | Task |
|-----------|------|
| lsof + ps 扫描 | 2, 3 |
| L1/L2/L3 识别 | 4, 5 |
| 智能过滤 | 5 |
| 进程+端口健康 | 3, 5 |
| Kill SIGTERM→SIGKILL | 6, 10 |
| Open/Copy/Reveal/Kill | 9, 10 |
| 侧边栏底部 Services | 8 |
| 3s 轮询 + 前台 only | 7, 8 |
| 搜索 + toolbar | 9 |
| 本地化 | 10 |
| v2 不做项 | 未纳入 ✓ |
