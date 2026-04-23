//
//  LaunchManagerTests.swift
//  LaunchManagerTests
//
//  Created by Shi-Cheng Ma on 2026/4/22.
//

import XCTest
@testable import LaunchManager

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

        struct NoopShell: ShellRunner {
            func run(_ path: String, arguments: [String]) throws -> String { "" }
        }
        let launchctl = LaunchctlService(shell: NoopShell())
        try svc.delete(item, launchctl: launchctl, privilege: PrivilegeService())

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}
