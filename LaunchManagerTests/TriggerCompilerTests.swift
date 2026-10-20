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
        XCTAssertEqual(weekly?.sourceRefs.count, 2)
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
