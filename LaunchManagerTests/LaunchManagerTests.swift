//
//  LaunchManagerTests.swift
//  LaunchManagerTests
//
//  Created by Shi-Cheng Ma on 2026/4/22.
//

import XCTest
@testable import LaunchManager

private struct NoopShell: ShellRunner {
    func run(_ path: String, arguments: [String]) throws -> String { "" }
}

// MARK: - LaunchctlService Tests

final class LaunchctlServiceTests: XCTestCase {
    func test_parseListOutput_running() {
        let output = "PID\tStatus\tLabel\n636\t0\tcom.syncthing.start\n"
        let result = LaunchctlService().parseListOutput(output)
        XCTAssertEqual(result["com.syncthing.start"]?.pid, 636)
        XCTAssertEqual(result["com.syncthing.start"]?.exitCode, 0)
    }

    func test_parseListOutput_stopped() {
        let output = "PID\tStatus\tLabel\n-\t0\tcom.syncthing.stop\n"
        let result = LaunchctlService().parseListOutput(output)
        XCTAssertNil(result["com.syncthing.stop"]?.pid)
        XCTAssertEqual(result["com.syncthing.stop"]?.exitCode, 0)
    }

    func test_parseListOutput_failed() {
        let output = "PID\tStatus\tLabel\n-\t1\tcom.example.failed\n"
        let result = LaunchctlService().parseListOutput(output)
        XCTAssertNil(result["com.example.failed"]?.pid)
        XCTAssertEqual(result["com.example.failed"]?.exitCode, 1)
    }

    func test_parseListOutput_emptyLines() {
        let output = "PID\tStatus\tLabel\n636\t0\tcom.foo\n\n"
        let result = LaunchctlService().parseListOutput(output)
        XCTAssertEqual(result.count, 1)
    }
}

// MARK: - PlistService Tests

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
        <plist version="1.0"><dict>
            <key>Label</key><string>com.test.calendar</string>
            <key>ProgramArguments</key>
            <array><string>/usr/bin/open</string><string>-a</string><string>Syncthing</string></array>
            <key>StartCalendarInterval</key>
            <dict><key>Hour</key><integer>8</integer><key>Minute</key><integer>0</integer></dict>
            <key>RunAtLoad</key><false/>
        </dict></plist>
        """
        let url = tmpDir.appendingPathComponent("com.test.calendar.plist")
        try plist.write(to: url, atomically: true, encoding: .utf8)

        let item = svc.parsePlist(at: url, scope: .userAgent)
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
        <plist version="1.0"><dict>
            <key>Label</key><string>com.test.interval</string>
            <key>Program</key><string>/usr/local/bin/mytool</string>
            <key>StartInterval</key><integer>300</integer>
        </dict></plist>
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

    func test_scanDirectory_separatesInvalidItems() throws {
        let validPlist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
            <key>Label</key><string>com.test.valid</string>
            <key>Program</key><string>/bin/echo</string>
        </dict></plist>
        """
        let emptyPlist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict/></plist>
        """
        let validURL = tmpDir.appendingPathComponent("com.test.valid.plist")
        let emptyURL = tmpDir.appendingPathComponent("com.test.empty.plist")
        try validPlist.write(to: validURL, atomically: true, encoding: .utf8)
        try emptyPlist.write(to: emptyURL, atomically: true, encoding: .utf8)

        let (items, invalid) = svc.scanDirectory(tmpDir, scope: .userAgent)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].label, "com.test.valid")
        XCTAssertEqual(invalid.count, 1)
        XCTAssertEqual(invalid[0].url.lastPathComponent, "com.test.empty.plist")
        XCTAssertEqual(invalid[0].scope, .userAgent)
    }

    func test_delete_nonPrivileged_removesFile() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
            <key>Label</key><string>com.test.delete</string>
            <key>Program</key><string>/bin/echo</string>
        </dict></plist>
        """
        let url = tmpDir.appendingPathComponent("com.test.delete.plist")
        try plist.write(to: url, atomically: true, encoding: .utf8)
        let item = svc.parsePlist(at: url, scope: .userAgent)!

        let launchctl = LaunchctlService(shell: NoopShell())
        try svc.delete(item, launchctl: launchctl, privilege: PrivilegeService())

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}

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

        try await Task.sleep(nanoseconds: 1_100_000_000)

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

private struct FakeDiscoveryShell: ShellRunner, @unchecked Sendable {
    let lsofOutput: String
    var psResponses: [Int32: String] = [:]
    var cwdResponses: [Int32: String] = [:]

    func run(_ path: String, arguments: [String]) throws -> String {
        if path == "/usr/sbin/lsof" && arguments.contains("-iTCP") {
            return lsofOutput
        }
        if path == "/bin/ps" {
            if let pIndex = arguments.firstIndex(of: "-p"), pIndex + 1 < arguments.count,
               let pid = Int32(arguments[pIndex + 1]) {
                return psResponses[pid] ?? ""
            }
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
        let pid = getpid()
        let lsof = """
        COMMAND   PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
        node    \(pid) sean   21u  IPv4 0x0      0t0  TCP *:3000 (LISTEN)
        """
        let shell = FakeDiscoveryShell(
            lsofOutput: lsof,
            psResponses: [pid: "node /usr/local/bin/next dev"],
            cwdResponses: [pid: "/Users/sean/blog/frontend"]
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
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try #"{"name":"blog-frontend"}"#.write(to: dir.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        let name = ProjectResolver().resolve(workingDirectory: dir.path)
        XCTAssertEqual(name, "blog-frontend")
    }
}

// MARK: - ServiceClassifier Tests

final class ServiceClassifierTests: XCTestCase {
    func test_classify_nextJs() {
        let p = ListeningProcess(
            pid: getpid(), port: 3000, protocolName: "tcp",
            command: "node next dev", executable: "node",
            workingDirectory: nil
        )
        let svc = ServiceClassifier().classify(p)
        XCTAssertEqual(svc.displayName, "Next.js")
        XCTAssertEqual(svc.url?.port, 3000)
        XCTAssertEqual(svc.health, .healthy)
    }
}

// MARK: - DevServiceFilter Tests

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
        Service(
            displayName: displayName, subtitle: nil, category: .other,
            health: .healthy, port: port, host: "localhost", pid: 1,
            executable: executable, command: executable,
            workingDirectory: nil, url: nil
        )
    }
}
