import XCTest
@testable import LaunchManager

final class TriggerDocumentSessionTests: XCTestCase {
    func test_session_noChanges_shouldNotWrite() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lm-session-\(UUID().uuidString).plist")
        let root: [String: Any] = [
            "Label": "a.b",
            "Program": "/bin/echo",
            "StartCalendarInterval": ["Hour": 9],
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: root, format: .xml, options: 0
        )
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

    func test_session_isModified_marksTriggersDirty() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lm-session-\(UUID().uuidString).plist")
        let root: [String: Any] = [
            "Label": "a.b",
            "Program": "/bin/echo",
            "StartCalendarInterval": ["Hour": 9, "Minute": 0],
        ]
        try PropertyListSerialization.data(fromPropertyList: root, format: .xml, options: 0)
            .write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        var session = try TriggerDocumentSession(url: url)
        XCTAssertFalse(session.triggersDirty)
        XCTAssertFalse(session.rules.isEmpty)

        session.rules[0].isModified = true
        XCTAssertTrue(session.triggersDirty)
    }

    func test_session_applyTriggerRulesToRoot_canChangeRoot() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lm-session-\(UUID().uuidString).plist")
        let root: [String: Any] = [
            "Label": "a.b",
            "Program": "/bin/echo",
            "StartCalendarInterval": ["Hour": 9, "Minute": 0],
        ]
        try PropertyListSerialization.data(fromPropertyList: root, format: .xml, options: 0)
            .write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        var session = try TriggerDocumentSession(url: url)
        XCTAssertFalse(session.rootLogicallyChanged)

        session.rules[0].kind = .daily(hour: 10, minute: 30)
        session.rules[0].isModified = true
        session.applyTriggerRulesToRoot()

        XCTAssertTrue(session.rootLogicallyChanged)
        let interval = session.root["StartCalendarInterval"] as? [String: Any]
        XCTAssertEqual(interval?["Hour"] as? Int, 10)
        XCTAssertEqual(interval?["Minute"] as? Int, 30)
    }

    func test_session_pathIdsInOrder_fromWatchPaths() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lm-session-\(UUID().uuidString).plist")
        let root: [String: Any] = [
            "Label": "a.b",
            "Program": "/bin/echo",
            "WatchPaths": ["/tmp/a", "/tmp/b"],
        ]
        try PropertyListSerialization.data(fromPropertyList: root, format: .xml, options: 0)
            .write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let session = try TriggerDocumentSession(url: url)
        XCTAssertEqual(session.pathIdsInOrder.count, 2)
        XCTAssertEqual(session.rules.filter {
            if case .watchPath = $0.kind { return true }
            return false
        }.count, 2)
        for (index, pathId) in session.pathIdsInOrder.enumerated() {
            XCTAssertTrue(
                session.rules[index].sourceRefs.contains(.watchPath(pathId))
                    || session.rules.contains { $0.sourceRefs.contains(.watchPath(pathId)) }
            )
        }
    }

    func test_session_structuralAdd_marksTriggersDirty() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lm-session-\(UUID().uuidString).plist")
        let root: [String: Any] = [
            "Label": "a.b",
            "Program": "/bin/echo",
            "StartInterval": 60,
        ]
        try PropertyListSerialization.data(fromPropertyList: root, format: .xml, options: 0)
            .write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        var session = try TriggerDocumentSession(url: url)
        XCTAssertFalse(session.triggersDirty)

        session.rules.append(TriggerRule(
            id: UUID(),
            kind: .watchPath("/tmp/x"),
            sourceRefs: [.watchPath(UUID())],
            isModified: false
        ))
        XCTAssertTrue(session.triggersDirty)
    }

    func test_replacingRootPreservingDiskBaseline_keepsFileChangedOnDiskFalse() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lm-session-\(UUID().uuidString).plist")
        let root: [String: Any] = [
            "Label": "a.b",
            "Program": "/bin/echo",
            "StartCalendarInterval": ["Hour": 9, "Minute": 0],
        ]
        try PropertyListSerialization.data(fromPropertyList: root, format: .xml, options: 0)
            .write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        var session = try TriggerDocumentSession(url: url)
        XCTAssertFalse(try session.fileChangedOnDisk())
        XCTAssertFalse(session.rootLogicallyChanged)

        var modified = root
        modified["RunAtLoad"] = true
        modified["StartCalendarInterval"] = ["Hour": 10, "Minute": 30]
        try session.replacingRootPreservingDiskBaseline(modified)

        // Disk bytes unchanged → external-change check must stay false.
        XCTAssertFalse(try session.fileChangedOnDisk())
        // Working root differs from original disk snapshot.
        XCTAssertTrue(session.rootLogicallyChanged)
        XCTAssertEqual(session.root["RunAtLoad"] as? Bool, true)
        let interval = session.root["StartCalendarInterval"] as? [String: Any]
        XCTAssertEqual(interval?["Hour"] as? Int, 10)
        // openedRoot baseline unchanged (still original disk content).
        XCTAssertNil(session.openedRoot["RunAtLoad"])
    }
}
