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
        let original = LaunchItem(
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
            workingDirectory: nil,
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
            return XCTFail("expected missingLabel")
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
            workingDirectory: nil,
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

// MARK: - FilePathNormalizer Tests

final class FilePathNormalizerTests: XCTestCase {
    func test_decodeLsofOctalEscapes_decodesUTF8Path() {
        // 启动器 in octal: \345\220\257\345\212\250\345\231\250
        let encoded = "/Applications/\\345\\220\\257\\345\\212\\250\\345\\231\\250.app"
        XCTAssertEqual(
            FilePathNormalizer.decodeLsofOctalEscapes(encoded),
            "/Applications/启动器.app"
        )
    }

    func test_repairUTF8Mojibake_fixesLatin1Misread() {
        let mojibake = "å¯å¨å¨"
        XCTAssertEqual(FilePathNormalizer.repairUTF8Mojibake(mojibake), "启动器")
    }

    func test_normalize_leavesAsciiPathsUntouched() {
        XCTAssertEqual(
            FilePathNormalizer.normalize("/Users/sean/project"),
            "/Users/sean/project"
        )
    }

    func test_normalize_preservesChinesePath() {
        XCTAssertEqual(
            FilePathNormalizer.normalize("/Applications/启动器.app"),
            "/Applications/启动器.app"
        )
    }

    func test_display_preservesChinesePath() {
        XCTAssertEqual(
            FilePathNormalizer.display("/Applications/启动器.app"),
            "/Applications/启动器.app"
        )
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

    func test_executableName_fromFullPsCommand() {
        XCTAssertEqual(
            ProcessDiscoveryService.executableName(from: "/opt/homebrew/bin/cloudflared tunnel run"),
            "cloudflared"
        )
        XCTAssertEqual(
            ProcessDiscoveryService.executableName(from: "/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter"),
            "ControlCenter"
        )
    }
}

private struct FakeDiscoveryShell: ShellRunner, @unchecked Sendable {
    let lsofOutput: String
    var psResponses: [Int32: String] = [:]
    var cwdResponses: [Int32: String] = [:]

    func run(_ path: String, arguments: [String]) throws -> String {
        if path == "/usr/bin/env", arguments.count >= 3 {
            let realPath = arguments[2]
            let realArgs = Array(arguments.dropFirst(3))
            return try run(realPath, arguments: realArgs)
        }
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
        let fakePid: Int32 = 42_424
        let lsof = """
        COMMAND   PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
        node    \(fakePid) sean   21u  IPv4 0x0      0t0  TCP *:3000 (LISTEN)
        """
        let shell = FakeDiscoveryShell(
            lsofOutput: lsof,
            psResponses: [fakePid: "node /usr/local/bin/next dev"],
            cwdResponses: [fakePid: "/Users/sean/blog/frontend"]
        )
        let svc = ProcessDiscoveryService(
            shell: shell,
            isAlive: { $0 == fakePid }
        )
        let processes = try svc.scan()
        XCTAssertEqual(processes.count, 1)
        XCTAssertEqual(processes[0].command, "node /usr/local/bin/next dev")
        XCTAssertEqual(processes[0].executable, "node")
        XCTAssertEqual(processes[0].workingDirectory, "/Users/sean/blog/frontend")
    }

    func test_resolveCommand_usesPsFallbackForUnknownPid() {
        let shell = FakeDiscoveryShell(
            lsofOutput: "",
            psResponses: [99_999: "/Applications/启动器.app/Contents/MacOS/启动器 --serve"]
        )
        let svc = ProcessDiscoveryService(shell: shell)
        let command = svc.resolveCommand(pid: 99_999, shell: shell, fallbackExecutable: "启动器")
        XCTAssertEqual(command, "/Applications/启动器.app/Contents/MacOS/启动器 --serve")
    }

    func test_healthCheck_aliveProcess() {
        XCTAssertTrue(ProcessDiscoveryService.isProcessAlive(pid: getpid()))
        XCTAssertFalse(ProcessDiscoveryService.isProcessAlive(pid: 999_999))
    }

    func test_parseLsofOutput_allowsFewerColumnsWhenNameHasSpaces() {
        let output = """
        COMMAND   PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
        Google    123 sean   51u  IPv4 0x0      0t0  TCP 127.0.0.1:9222 (LISTEN)
        """
        let rows = svc.parseLsofOutput(output)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].port, 9222)
    }
}

// MARK: - Service Resolver Tests

final class ServiceResolverTests: XCTestCase {
    func test_commandLineResolver_nextJs() {
        let hit = CommandLineResolver().resolve(command: "node /path/next dev --port 3000")
        XCTAssertEqual(hit?.displayName, "Next.js")
        XCTAssertEqual(hit?.identityKind, .realService)
    }

    func test_commandLineResolver_uvicorn_notMatched() {
        let hit = CommandLineResolver().resolve(command: "uvicorn app.main:app --reload")
        XCTAssertNil(hit)
    }

    func test_executableResolver_redis() {
        let hit = ExecutableResolver().resolve(executable: "redis-server")
        XCTAssertEqual(hit?.displayName, "Redis")
        XCTAssertEqual(hit?.category, .cache)
    }

    func test_executableResolver_postgres() {
        let hit = ExecutableResolver().resolve(executable: "postgres")
        XCTAssertEqual(hit?.displayName, "PostgreSQL")
    }

    func test_executableResolver_node_notMatched() {
        XCTAssertNil(ExecutableResolver().resolve(executable: "node"))
    }

    func test_hostMechanism_dockerProxy() {
        let process = ListeningProcess(
            pid: 1, port: 6379, protocolName: "tcp",
            command: "docker-proxy -proto tcp -host-ip 0.0.0.0 -host-port 6379",
            executable: "docker-proxy", workingDirectory: nil
        )
        let hit = HostMechanismResolver().resolve(process: process)
        XCTAssertEqual(hit?.displayName, String(localized: "Docker 端口转发"))
        XCTAssertEqual(hit?.identityKind, .hostMechanism)
    }

    func test_hostMechanism_sshForward() {
        let process = ListeningProcess(
            pid: 1, port: 5432, protocolName: "tcp",
            command: "ssh -L 5432:127.0.0.1:5432 user@remote",
            executable: "ssh", workingDirectory: nil
        )
        let hit = HostMechanismResolver().resolve(process: process)
        XCTAssertEqual(hit?.displayName, String(localized: "SSH 端口转发"))
    }

    func test_hostMechanism_colima() {
        let process = ListeningProcess(
            pid: 1, port: 8080, protocolName: "tcp",
            command: "/Users/sean/.colima/default/docker.sock",
            executable: "colima", workingDirectory: nil
        )
        let hit = HostMechanismResolver().resolve(process: process)
        XCTAssertEqual(hit?.displayName, "Colima")
    }

    func test_hostMechanism_launchd() {
        let process = ListeningProcess(
            pid: 1, port: 8080, protocolName: "tcp",
            command: "/sbin/launchd",
            executable: "launchd", workingDirectory: nil
        )
        let hit = HostMechanismResolver().resolve(process: process)
        XCTAssertEqual(hit?.displayName, String(localized: "系统服务 (launchd)"))
    }

    func test_projectResolver_packageJson() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try #"{"name":"blog-frontend"}"#.write(to: dir.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        let name = ProjectResolver().resolve(workingDirectory: dir.path)
        XCTAssertEqual(name, "blog-frontend")
    }

    func test_projectContext_findsRootFromCommandPath() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try #"{"name":"my-app"}"#.write(to: dir.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        let bin = dir.appendingPathComponent("node_modules/.bin/next")
        try FileManager.default.createDirectory(at: bin.deletingLastPathComponent(), withIntermediateDirectories: true)

        let process = ListeningProcess(
            pid: 1, port: 3000, protocolName: "tcp",
            command: "\(bin.path) dev",
            executable: "node",
            workingDirectory: FileManager.default.homeDirectoryForCurrentUser.path
        )
        let context = ProjectContextResolver().resolve(process: process)
        XCTAssertEqual(context.projectDirectory, dir.path)
        XCTAssertEqual(context.projectName, "my-app")
    }
}

// MARK: - ServiceClassifier Tests

final class ServiceClassifierTests: XCTestCase {
    private func isolatedNameStore() -> ServiceNameStore {
        let suite = "ServiceNameStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return ServiceNameStore(defaults: defaults)
    }

    func test_classify_nextJs() {
        let p = ListeningProcess(
            pid: getpid(), port: 3000, protocolName: "tcp",
            command: "node next dev", executable: "node",
            workingDirectory: nil
        )
        let svc = ServiceClassifier().classify(
            p, dockerIndex: DockerContainerIndex(containers: []), nameStore: isolatedNameStore()
        )
        XCTAssertEqual(svc.displayName, "Next.js")
        XCTAssertEqual(svc.runtimeGroup, .instance)
        XCTAssertEqual(svc.identityKind, .realService)
        XCTAssertEqual(svc.url?.port, 3000)
        XCTAssertEqual(svc.health, .healthy)
    }

    func test_classify_dockerProxy_blocksKillWithoutContainer() {
        let p = ListeningProcess(
            pid: 1, port: 6379, protocolName: "tcp",
            command: "docker-proxy -proto tcp -host-port 6379",
            executable: "docker-proxy", workingDirectory: nil
        )
        let svc = ServiceClassifier().classify(
            p, dockerIndex: DockerContainerIndex(containers: []), nameStore: isolatedNameStore()
        )
        XCTAssertEqual(svc.autoDisplayName, String(localized: "Docker 端口转发"))
        XCTAssertEqual(svc.identityKind, .hostMechanism)
        XCTAssertEqual(svc.runtimeGroup, .docker)
        XCTAssertFalse(svc.killAllowed)
        if case .blocked = svc.stopMethod { } else {
            XCTFail("expected blocked stop method")
        }
    }

    func test_classify_dockerProxy_resolvesRedisContainer() {
        let container = DockerContainerInfo(
            id: "abc123def456",
            name: "myproject-redis-1",
            image: "redis:7-alpine",
            composeProject: "myproject",
            composeService: "redis",
            publishedHostPorts: [6379]
        )
        let index = DockerContainerIndex(containers: [container])
        let p = ListeningProcess(
            pid: 1, port: 6379, protocolName: "tcp",
            command: "docker-proxy -proto tcp -host-port 6379",
            executable: "docker-proxy", workingDirectory: nil
        )
        let svc = ServiceClassifier().classify(
            p, dockerIndex: index, nameStore: isolatedNameStore()
        )
        XCTAssertEqual(svc.displayName, "Redis")
        XCTAssertEqual(svc.runtimeGroup, .docker)
        XCTAssertEqual(svc.subtitle, "myproject · redis:7-alpine")
        XCTAssertTrue(svc.usesDockerStop)
        XCTAssertEqual(svc.dockerInfo?.composeService, "redis")
        if case .dockerContainer(let ref, _) = svc.stopMethod {
            XCTAssertEqual(ref, "myproject-redis-1")
        } else {
            XCTFail("expected docker stop")
        }
    }

    func test_classify_redis_direct() {
        let p = ListeningProcess(
            pid: 1, port: 6379, protocolName: "tcp",
            command: "redis-server", executable: "redis-server", workingDirectory: nil
        )
        let svc = ServiceClassifier().classify(
            p, dockerIndex: DockerContainerIndex(containers: []), nameStore: isolatedNameStore()
        )
        XCTAssertEqual(svc.displayName, "Redis")
        XCTAssertEqual(svc.identityKind, .realService)
    }

    func test_classify_unidentified_usesExecutable() {
        let p = ListeningProcess(
            pid: 1, port: 8080, protocolName: "tcp",
            command: "cloudflared tunnel run", executable: "cloudflared", workingDirectory: nil
        )
        let svc = ServiceClassifier().classify(
            p, dockerIndex: DockerContainerIndex(containers: []), nameStore: isolatedNameStore()
        )
        XCTAssertEqual(svc.displayName, "cloudflared")
        XCTAssertEqual(svc.identityKind, .unidentified)
    }

    func test_classify_customNameOverrides() {
        let store = isolatedNameStore()
        let key = ServiceNameStore.identityKey(port: 8080, executable: "cloudflared")
        store.setCustomName("我的隧道", for: key)
        let p = ListeningProcess(
            pid: 1, port: 8080, protocolName: "tcp",
            command: "cloudflared tunnel run", executable: "cloudflared", workingDirectory: nil
        )
        let svc = ServiceClassifier().classify(p, dockerIndex: DockerContainerIndex(containers: []), nameStore: store)
        XCTAssertEqual(svc.displayName, "我的隧道")
        XCTAssertEqual(svc.autoDisplayName, "cloudflared")
    }
}

// MARK: - Docker Tests

final class DockerContainerIndexTests: XCTestCase {
    func test_resolveExecutable_usesKnownPathsOnly() {
        guard let path = DockerCLI.resolveExecutable() else { return }
        XCTAssertTrue(DockerCLI.allCandidatePaths().contains(path))
    }

    func test_augmentedPATH_includesCommonInstallDirs() {
        let path = DockerCLI.augmentedPATH(existing: "/usr/bin:/bin")
        XCTAssertTrue(path.contains("/opt/homebrew/bin"))
        XCTAssertTrue(path.contains("/usr/local/bin"))
    }

    func test_optionalInit_succeedsWhenDockerAvailable() throws {
        if DockerCLI.resolveExecutable() == nil && DockerCLI(optional: DefaultShellRunner()) == nil {
            throw XCTSkip("docker not available")
        }
        XCTAssertNotNil(DockerCLI(optional: DefaultShellRunner()))
    }

    func test_parseHostPorts() {
        let ports = DockerContainerIndex.parseHostPorts(
            from: "0.0.0.0:6379->6379/tcp, [::]:6379->6379/tcp, 127.0.0.1:3000->3000/tcp"
        )
        XCTAssertEqual(Set(ports), Set([6379, 3000]))
    }

    func test_parseListingLine() {
        let line = "abc123\tmy-redis\tredis:7\t0.0.0.0:6379->6379/tcp\tredis\tmyproject"
        let container = DockerContainerIndex.parseLine(line)
        XCTAssertEqual(container?.name, "my-redis")
        XCTAssertEqual(container?.composeService, "redis")
        XCTAssertEqual(container?.publishedHostPorts, [6379])
    }

    func test_containerLookupByPort() {
        let container = DockerContainerInfo(
            id: "id1", name: "web-1", image: "nginx:latest",
            composeProject: "app", composeService: "web",
            publishedHostPorts: [8080]
        )
        let index = DockerContainerIndex(containers: [container])
        XCTAssertEqual(index.container(forHostPort: 8080)?.name, "web-1")
        XCTAssertNil(index.container(forHostPort: 9090))
    }
}

final class DockerManagedDetectorTests: XCTestCase {
    func test_dockerProxy() {
        let p = ListeningProcess(
            pid: 1, port: 1, protocolName: "tcp",
            command: "docker-proxy", executable: "docker-proxy", workingDirectory: nil
        )
        XCTAssertTrue(DockerManagedDetector.isDockerManaged(p))
    }

    func test_colimaPath() {
        let p = ListeningProcess(
            pid: 1, port: 1, protocolName: "tcp",
            command: "/Users/sean/.colima/docker.sock",
            executable: "colima", workingDirectory: "/Users/sean/.colima/default"
        )
        XCTAssertTrue(DockerManagedDetector.isDockerManaged(p))
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

    func test_controlCenterOn5000_filtered() {
        let s = makeService(port: 5000, executable: "ControlCenter", displayName: "AirPlay Receiver")
        XCTAssertFalse(DevServiceFilter().isDevService(s))
    }

    private func makeService(port: Int, executable: String, displayName: String) -> Service {
        let key = ServiceNameStore.identityKey(port: port, executable: executable)
        return Service(
            identityKey: key,
            autoDisplayName: displayName,
            displayName: displayName,
            identityKind: .realService,
            runtimeGroup: .instance,
            subtitle: nil, category: .other,
            health: .healthy, port: port, host: "localhost", pid: 1,
            executable: executable, command: executable,
            workingDirectory: nil, processDirectory: nil, url: nil,
            dockerInfo: nil, stopMethod: .process(pid: 1)
        )
    }
}
