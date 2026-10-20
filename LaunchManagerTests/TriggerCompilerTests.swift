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

    // MARK: - parseNative smoke

    func test_parseNative_singleDict() {
        let interval: [String: Any] = ["Hour": 9, "Minute": 0]
        let native = TriggerCompiler.parseNative(from: [
            "StartCalendarInterval": interval
        ])
        XCTAssertTrue(native.calendarKeyPresent)
        XCTAssertFalse(native.calendarIsArray)
        XCTAssertEqual(native.calendarEntries.count, 1)
        XCTAssertEqual(native.calendarEntries[0].hour, 9)
        XCTAssertEqual(native.calendarEntries[0].minute, 0)
    }

    func test_parseNative_arrayOfEntries() {
        let intervals: [[String: Any]] = [
            ["Weekday": 1, "Hour": 9, "Minute": 0],
            ["Hour": 18, "Minute": 0],
        ]
        let native = TriggerCompiler.parseNative(from: [
            "StartCalendarInterval": intervals
        ])
        XCTAssertTrue(native.calendarKeyPresent)
        XCTAssertTrue(native.calendarIsArray)
        XCTAssertEqual(native.calendarEntries.count, 2)
        XCTAssertEqual(native.calendarEntries[0].weekday, 1)
        XCTAssertEqual(native.calendarEntries[1].hour, 18)
    }

    // MARK: - project

    func test_project_hourMinute_isDaily() {
        let interval: [String: Any] = ["Hour": 9, "Minute": 0]
        let native = TriggerCompiler.parseNative(from: [
            "StartCalendarInterval": interval
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
        let interval: [String: Any] = ["Hour": 9]
        let native = TriggerCompiler.parseNative(from: [
            "StartCalendarInterval": interval
        ])
        let rules = TriggerCompiler.project(native)
        guard case .customCalendar(_, let malformed) = rules[0].kind else {
            return XCTFail("expected custom")
        }
        XCTAssertFalse(malformed)
    }

    func test_project_mergesWeekdays_keepsSourceRefs() {
        // Explicit [[String: Any]] so parseNative's [Any] → [String: Any] casting succeeds.
        let intervals: [[String: Any]] = [
            ["Weekday": 1, "Hour": 9, "Minute": 0], // 1 = Monday
            ["Hour": 18, "Minute": 0],
            ["Weekday": 3, "Hour": 9, "Minute": 0], // 3 = Wednesday
        ]
        let native = TriggerCompiler.parseNative(from: [
            "StartCalendarInterval": intervals
        ])
        let rules = TriggerCompiler.project(native)
        let weekly = rules.first { if case .weekly = $0.kind { return true }; return false }
        XCTAssertNotNil(weekly)
        XCTAssertEqual(
            weekly?.sourceRefs,
            [
                .calendarEntry(native.calendarEntries[0].sessionId),
                .calendarEntry(native.calendarEntries[2].sessionId),
            ]
        )
        XCTAssertTrue(rules.contains { if case .daily = $0.kind { return true }; return false })
        // First-occurrence stable: weekly (from index 0) before daily (index 1)
        XCTAssertEqual(rules.count, 2)
        guard case .weekly(let weekdays, let hour, let minute) = rules[0].kind else {
            return XCTFail("expected weekly first")
        }
        XCTAssertEqual(weekdays, [1, 3])
        XCTAssertEqual(hour, 9)
        XCTAssertEqual(minute, 0)
        guard case .daily = rules[1].kind else {
            return XCTFail("expected daily second")
        }
    }

    func test_project_mergesMonths_keepsSourceRefs() {
        let intervals: [[String: Any]] = [
            ["Month": 1, "Day": 15, "Hour": 9, "Minute": 0],
            ["Month": 6, "Day": 15, "Hour": 9, "Minute": 0],
            ["Month": 12, "Day": 15, "Hour": 9, "Minute": 0],
        ]
        let native = TriggerCompiler.parseNative(from: [
            "StartCalendarInterval": intervals
        ])
        let rules = TriggerCompiler.project(native)
        XCTAssertEqual(rules.count, 1)
        guard case .monthly(let day, let hour, let minute, let months) = rules[0].kind else {
            return XCTFail("expected monthly")
        }
        XCTAssertEqual(day, 15)
        XCTAssertEqual(hour, 9)
        XCTAssertEqual(minute, 0)
        XCTAssertEqual(months, Set([1, 6, 12]))
        XCTAssertEqual(rules[0].sourceRefs.count, 3)
        XCTAssertEqual(
            rules[0].sourceRefs,
            native.calendarEntries.map { SourceRef.calendarEntry($0.sessionId) }
        )
    }

    func test_project_mergesAllTwelveMonths_keepsMonthsSet() {
        let intervals: [[String: Any]] = (1...12).map { month in
            ["Month": month, "Day": 1, "Hour": 8, "Minute": 30]
        }
        let native = TriggerCompiler.parseNative(from: [
            "StartCalendarInterval": intervals
        ])
        let rules = TriggerCompiler.project(native)
        XCTAssertEqual(rules.count, 1)
        guard case .monthly(_, _, _, let months) = rules[0].kind else {
            return XCTFail("expected monthly")
        }
        XCTAssertNotNil(months)
        XCTAssertEqual(months, Set(1...12))
        XCTAssertEqual(rules[0].sourceRefs.count, 12)
    }

    func test_project_intervalAndWatchPaths() {
        let native = TriggerCompiler.parseNative(from: [
            "StartInterval": 3600,
            "WatchPaths": ["/tmp/a", "/tmp/b"],
        ])
        let rules = TriggerCompiler.project(native)
        XCTAssertEqual(rules.count, 3)

        guard case .interval(let seconds) = rules[0].kind else {
            return XCTFail("expected interval first")
        }
        XCTAssertEqual(seconds, 3600)
        XCTAssertEqual(rules[0].sourceRefs, [.startInterval])

        guard case .watchPath(let path0) = rules[1].kind else {
            return XCTFail("expected watchPath")
        }
        XCTAssertEqual(path0, "/tmp/a")
        XCTAssertEqual(rules[1].sourceRefs.count, 1)
        guard case .watchPath = rules[1].sourceRefs[0] else {
            return XCTFail("expected .watchPath sourceRef")
        }

        guard case .watchPath(let path1) = rules[2].kind else {
            return XCTFail("expected watchPath")
        }
        XCTAssertEqual(path1, "/tmp/b")
        XCTAssertEqual(rules[2].sourceRefs.count, 1)
        guard case .watchPath = rules[2].sourceRefs[0] else {
            return XCTFail("expected .watchPath sourceRef")
        }
    }

    func test_project_dayWeekday_isCustom() {
        let interval: [String: Any] = ["Day": 1, "Weekday": 2, "Hour": 9, "Minute": 0]
        let native = TriggerCompiler.parseNative(from: [
            "StartCalendarInterval": interval
        ])
        let rules = TriggerCompiler.project(native)
        guard case .customCalendar = rules[0].kind else {
            return XCTFail("expected custom")
        }
    }

    func test_project_invalidHour_isMalformedCustom() {
        let interval: [String: Any] = ["Hour": 99, "Minute": 0]
        let native = TriggerCompiler.parseNative(from: [
            "StartCalendarInterval": interval
        ])
        let rules = TriggerCompiler.project(native)
        guard case .customCalendar(_, let malformed) = rules[0].kind else {
            return XCTFail("expected custom")
        }
        XCTAssertTrue(malformed)
    }
}
