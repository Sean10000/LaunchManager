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

    func test_project_duplicateWeekdays_dedupesKindKeepsSourceRefs() {
        let intervals: [[String: Any]] = [
            ["Weekday": 1, "Hour": 9, "Minute": 0],
            ["Weekday": 1, "Hour": 9, "Minute": 0],
        ]
        let native = TriggerCompiler.parseNative(from: [
            "StartCalendarInterval": intervals
        ])
        let rules = TriggerCompiler.project(native)
        XCTAssertEqual(rules.count, 1)
        guard case .weekly(let weekdays, let hour, let minute) = rules[0].kind else {
            return XCTFail("expected weekly")
        }
        XCTAssertEqual(weekdays, [1])
        XCTAssertEqual(hour, 9)
        XCTAssertEqual(minute, 0)
        XCTAssertEqual(rules[0].sourceRefs.count, 2)
        XCTAssertEqual(
            rules[0].sourceRefs,
            [
                .calendarEntry(native.calendarEntries[0].sessionId),
                .calendarEntry(native.calendarEntries[1].sessionId),
            ]
        )
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

    // MARK: - compile + apply

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
            "StartCalendarInterval": ["Hour": 9], // missing Minute — custom
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
        // single-dict shape preserved
        XCTAssertTrue(out["StartCalendarInterval"] is [String: Any])
        XCTAssertEqual(out["Label"] as? String, "t")
    }

    func test_applyChange_editMergedWeek_onlyTouchesRefs() {
        // Build array [Mon 9:00, daily 18:00, Tue 9:00]; edit weekly time to 10:00;
        // assert middle daily unchanged; A/C become Hour 10.
        let intervals: [[String: Any]] = [
            ["Weekday": 1, "Hour": 9, "Minute": 0], // Mon
            ["Hour": 18, "Minute": 0],
            ["Weekday": 2, "Hour": 9, "Minute": 0], // Tue
        ]
        let root: [String: Any] = ["StartCalendarInterval": intervals]
        let native = TriggerCompiler.parseNative(from: root)
        var rules = TriggerCompiler.project(native)
        guard let weeklyIdx = rules.firstIndex(where: {
            if case .weekly = $0.kind { return true }
            return false
        }) else {
            return XCTFail("expected weekly rule")
        }
        guard case .weekly(let weekdays, _, let minute) = rules[weeklyIdx].kind else {
            return XCTFail("expected weekly")
        }
        rules[weeklyIdx].kind = .weekly(weekdays: weekdays, hour: 10, minute: minute)
        rules[weeklyIdx].isModified = true

        let out = TriggerCompiler.applyTriggers(
            to: root,
            native: native,
            rules: rules,
            pathIdsInOrder: []
        )
        guard let array = out["StartCalendarInterval"] as? [[String: Any]] else {
            return XCTFail("expected calendar array")
        }
        XCTAssertEqual(array.count, 3)
        // Order preserved: week entries around daily
        XCTAssertEqual(array[0]["Weekday"] as? Int, 1)
        XCTAssertEqual(array[0]["Hour"] as? Int, 10)
        XCTAssertEqual(array[0]["Minute"] as? Int, 0)
        XCTAssertEqual(array[1]["Hour"] as? Int, 18)
        XCTAssertNil(array[1]["Weekday"])
        XCTAssertEqual(array[1]["Minute"] as? Int, 0)
        XCTAssertEqual(array[2]["Weekday"] as? Int, 2)
        XCTAssertEqual(array[2]["Hour"] as? Int, 10)
        XCTAssertEqual(array[2]["Minute"] as? Int, 0)
    }

    func test_applyChange_deletingRuleRemovesRefs() {
        let intervals: [[String: Any]] = [
            ["Weekday": 1, "Hour": 9, "Minute": 0],
            ["Hour": 18, "Minute": 0],
            ["Weekday": 2, "Hour": 9, "Minute": 0],
        ]
        let root: [String: Any] = ["Label": "t", "StartCalendarInterval": intervals]
        let native = TriggerCompiler.parseNative(from: root)
        var rules = TriggerCompiler.project(native)
        rules.removeAll { if case .weekly = $0.kind { return true }; return false }

        let out = TriggerCompiler.applyTriggers(
            to: root,
            native: native,
            rules: rules,
            pathIdsInOrder: []
        )
        guard let array = out["StartCalendarInterval"] as? [[String: Any]] else {
            return XCTFail("expected calendar array")
        }
        XCTAssertEqual(array.count, 1)
        XCTAssertEqual(array[0]["Hour"] as? Int, 18)
        XCTAssertNil(array[0]["Weekday"])
        XCTAssertEqual(out["Label"] as? String, "t")
    }

    func test_applyChange_newDailyAppends() {
        let root: [String: Any] = [
            "StartCalendarInterval": ["Hour": 9, "Minute": 0] as [String: Any],
        ]
        let native = TriggerCompiler.parseNative(from: root)
        var rules = TriggerCompiler.project(native)
        rules.append(TriggerRule(
            id: UUID(),
            kind: .daily(hour: 12, minute: 30),
            sourceRefs: [],
            isModified: true
        ))

        let out = TriggerCompiler.applyTriggers(
            to: root,
            native: native,
            rules: rules,
            pathIdsInOrder: []
        )
        guard let array = out["StartCalendarInterval"] as? [[String: Any]] else {
            return XCTFail("expected calendar array after append")
        }
        XCTAssertEqual(array.count, 2)
        XCTAssertEqual(array[0] as NSDictionary, ["Hour": 9, "Minute": 0] as NSDictionary)
        XCTAssertEqual(array[1] as NSDictionary, ["Hour": 12, "Minute": 30] as NSDictionary)
    }

    func test_applyChange_unmodifiedSingleDictShapePreserved() {
        let root: [String: Any] = [
            "StartCalendarInterval": ["Hour": 9, "Minute": 0] as [String: Any],
        ]
        let native = TriggerCompiler.parseNative(from: root)
        let rules = TriggerCompiler.project(native)
        let out = TriggerCompiler.applyTriggers(
            to: root,
            native: native,
            rules: rules,
            pathIdsInOrder: []
        )
        XCTAssertTrue(out["StartCalendarInterval"] is [String: Any])
        XCTAssertFalse(out["StartCalendarInterval"] is [[String: Any]])
        XCTAssertEqual(
            out["StartCalendarInterval"] as? NSDictionary,
            ["Hour": 9, "Minute": 0] as NSDictionary
        )
    }

    func test_applyChange_touchedAndCountGreaterThanOneWritesArray() {
        let root: [String: Any] = [
            "StartCalendarInterval": ["Hour": 9, "Minute": 0] as [String: Any],
        ]
        let native = TriggerCompiler.parseNative(from: root)
        var rules = TriggerCompiler.project(native)
        guard case .daily(_, let minute) = rules[0].kind else {
            return XCTFail("expected daily")
        }
        rules[0].kind = .daily(hour: 10, minute: minute)
        rules[0].isModified = true
        rules.append(TriggerRule(
            id: UUID(),
            kind: .daily(hour: 15, minute: 0),
            sourceRefs: [],
            isModified: true
        ))

        let out = TriggerCompiler.applyTriggers(
            to: root,
            native: native,
            rules: rules,
            pathIdsInOrder: []
        )
        guard let array = out["StartCalendarInterval"] as? [[String: Any]] else {
            return XCTFail("expected calendar array")
        }
        XCTAssertEqual(array.count, 2)
        XCTAssertEqual(array[0]["Hour"] as? Int, 10)
        XCTAssertEqual(array[1]["Hour"] as? Int, 15)
    }

    func test_applyChange_weeklyNativeOrder_matchesByWeekday() {
        // Native order Tue then Mon — edit time; slots keep Tue/Mon weekdays with new hour.
        let intervals: [[String: Any]] = [
            ["Weekday": 2, "Hour": 9, "Minute": 0], // Tue first
            ["Weekday": 1, "Hour": 9, "Minute": 0], // Mon second
        ]
        let root: [String: Any] = ["StartCalendarInterval": intervals]
        let native = TriggerCompiler.parseNative(from: root)
        var rules = TriggerCompiler.project(native)
        XCTAssertEqual(rules.count, 1)
        guard case .weekly(let weekdays, _, let minute) = rules[0].kind else {
            return XCTFail("expected weekly")
        }
        rules[0].kind = .weekly(weekdays: weekdays, hour: 11, minute: minute)
        rules[0].isModified = true

        let out = TriggerCompiler.applyTriggers(
            to: root,
            native: native,
            rules: rules,
            pathIdsInOrder: []
        )
        guard let array = out["StartCalendarInterval"] as? [[String: Any]] else {
            return XCTFail("expected calendar array")
        }
        XCTAssertEqual(array.count, 2)
        XCTAssertEqual(array[0]["Weekday"] as? Int, 2)
        XCTAssertEqual(array[0]["Hour"] as? Int, 11)
        XCTAssertEqual(array[1]["Weekday"] as? Int, 1)
        XCTAssertEqual(array[1]["Hour"] as? Int, 11)
    }

    func test_applyChange_editSingleDaily_keepsSingleDictShape() {
        let root: [String: Any] = [
            "StartCalendarInterval": ["Hour": 9, "Minute": 0] as [String: Any],
        ]
        let native = TriggerCompiler.parseNative(from: root)
        var rules = TriggerCompiler.project(native)
        guard case .daily(_, let minute) = rules[0].kind else {
            return XCTFail("expected daily")
        }
        rules[0].kind = .daily(hour: 14, minute: minute)
        rules[0].isModified = true

        let out = TriggerCompiler.applyTriggers(
            to: root,
            native: native,
            rules: rules,
            pathIdsInOrder: []
        )
        XCTAssertTrue(out["StartCalendarInterval"] is [String: Any])
        XCTAssertFalse(out["StartCalendarInterval"] is [[String: Any]])
        XCTAssertEqual(
            out["StartCalendarInterval"] as? NSDictionary,
            ["Hour": 14, "Minute": 0] as NSDictionary
        )
    }

    func test_applyChange_intervalAndWatchPaths_unmodifiedPreserved() {
        let root: [String: Any] = [
            "Label": "t",
            "StartInterval": 3600,
            // WatchPaths intentionally absent
        ]
        let native = TriggerCompiler.parseNative(from: root)
        let rules = TriggerCompiler.project(native)
        XCTAssertFalse(native.watchPathsKeyPresent)

        let out = TriggerCompiler.applyTriggers(
            to: root,
            native: native,
            rules: rules,
            pathIdsInOrder: []
        )
        XCTAssertEqual(out["StartInterval"] as? Int, 3600)
        XCTAssertNil(out["WatchPaths"])
        XCTAssertEqual(out["Label"] as? String, "t")
    }

    // MARK: - Regression (Task 9)

    func test_roundTrip_unmodifiedRules_calendarLogicallyEqual() {
        let intervals: [[String: Any]] = [
            ["Hour": 8], // hour-only custom — must not invent Minute
            ["Weekday": 1, "Hour": 9, "Minute": 0],
            ["Month": 2, "Day": 29, "Hour": 10, "Minute": 0],
            ["Day": 31, "Hour": 11, "Minute": 0],
        ]
        let root: [String: Any] = [
            "Label": "t",
            "StartCalendarInterval": intervals,
            "StartInterval": 600,
            "WatchPaths": ["/tmp/a", "/tmp/b"],
            "QueueDirectories": ["/tmp/q"],
        ]
        let native = TriggerCompiler.parseNative(from: root)
        let rules = TriggerCompiler.project(native)
        XCTAssertFalse(rules.contains(where: \.isModified))

        let out = TriggerCompiler.applyTriggers(
            to: root,
            native: native,
            rules: rules,
            pathIdsInOrder: []
        )
        XCTAssertTrue(
            NSDictionary(dictionary: out).isEqual(to: root),
            "unmodified applyTriggers must be a logical no-op on the root"
        )
    }

    func test_applyChange_partialEdit_preservesQueueDirectories() {
        let root: [String: Any] = [
            "Label": "t",
            "StartCalendarInterval": ["Hour": 9, "Minute": 0] as [String: Any],
            "WatchPaths": ["/tmp/a"],
            "QueueDirectories": ["/tmp/q"],
            "StartOnMount": true,
        ]
        let native = TriggerCompiler.parseNative(from: root)
        var rules = TriggerCompiler.project(native)
        guard case .daily(_, let minute) = rules[0].kind else {
            return XCTFail("expected daily")
        }
        rules[0].kind = .daily(hour: 14, minute: minute)
        rules[0].isModified = true

        let out = TriggerCompiler.applyTriggers(
            to: root,
            native: native,
            rules: rules,
            pathIdsInOrder: []
        )
        XCTAssertEqual(
            out["StartCalendarInterval"] as? NSDictionary,
            ["Hour": 14, "Minute": 0] as NSDictionary
        )
        XCTAssertEqual(out["QueueDirectories"] as? [String], ["/tmp/q"])
        XCTAssertEqual(out["StartOnMount"] as? Bool, true)
        XCTAssertEqual(out["WatchPaths"] as? [String], ["/tmp/a"])
        XCTAssertEqual(out["Label"] as? String, "t")
    }

    func test_compile_day31_and_feb29_unchanged() {
        let monthly = TriggerCompiler.compileCalendarDicts(
            kind: .monthly(day: 31, hour: 8, minute: 0, months: nil)
        )
        XCTAssertEqual(monthly.count, 1)
        XCTAssertEqual(monthly[0]["Day"] as? Int, 31)
        XCTAssertEqual(monthly[0]["Hour"] as? Int, 8)
        XCTAssertEqual(monthly[0]["Minute"] as? Int, 0)
        XCTAssertNil(monthly[0]["Month"])

        let yearly = TriggerCompiler.compileCalendarDicts(
            kind: .yearly(month: 2, day: 29, hour: 9, minute: 30)
        )
        XCTAssertEqual(yearly.count, 1)
        XCTAssertEqual(
            yearly[0] as NSDictionary,
            ["Month": 2, "Day": 29, "Hour": 9, "Minute": 30] as NSDictionary
        )

        // Unmodified apply also keeps Day 31 / Feb 29 raw intact.
        let root: [String: Any] = [
            "StartCalendarInterval": [
                ["Day": 31, "Hour": 8, "Minute": 0],
                ["Month": 2, "Day": 29, "Hour": 9, "Minute": 30],
            ] as [[String: Any]],
        ]
        let native = TriggerCompiler.parseNative(from: root)
        let rules = TriggerCompiler.project(native)
        let out = TriggerCompiler.applyTriggers(
            to: root,
            native: native,
            rules: rules,
            pathIdsInOrder: []
        )
        guard let array = out["StartCalendarInterval"] as? [[String: Any]] else {
            return XCTFail("expected calendar array")
        }
        XCTAssertEqual(array[0]["Day"] as? Int, 31)
        XCTAssertEqual(array[1]["Month"] as? Int, 2)
        XCTAssertEqual(array[1]["Day"] as? Int, 29)
    }

    func test_dayPlusWeekday_staysCustom_presetsNeverGenerateBoth() {
        let interval: [String: Any] = [
            "Day": 15, "Weekday": 3, "Hour": 9, "Minute": 0,
        ]
        let native = TriggerCompiler.parseNative(from: [
            "StartCalendarInterval": interval,
        ])
        let rules = TriggerCompiler.project(native)
        guard case .customCalendar(_, let malformed) = rules[0].kind else {
            return XCTFail("Day+Weekday must project as custom")
        }
        XCTAssertFalse(malformed)

        let presets: [TriggerRuleKind] = [
            .daily(hour: 9, minute: 0),
            .weekly(weekdays: [1, 3, 5], hour: 9, minute: 0),
            .monthly(day: 15, hour: 9, minute: 0, months: nil),
            .monthly(day: 15, hour: 9, minute: 0, months: Set([1, 6])),
            .yearly(month: 3, day: 15, hour: 9, minute: 0),
        ]
        for kind in presets {
            for dict in TriggerCompiler.compileCalendarDicts(kind: kind) {
                let hasDay = dict["Day"] != nil
                let hasWeekday = dict["Weekday"] != nil
                XCTAssertFalse(
                    hasDay && hasWeekday,
                    "preset \(kind) must not emit Day+Weekday: \(dict)"
                )
            }
        }
    }

    // MARK: - Preserve unparseable trigger values

    func test_applyTriggers_invalidStartInterval_string_preserved() {
        let root: [String: Any] = [
            "Label": "t",
            "StartInterval": "bad",
        ]
        let native = TriggerCompiler.parseNative(from: root)
        XCTAssertNil(native.startInterval)
        XCTAssertNotNil(native.startIntervalIssue)
        let rules = TriggerCompiler.project(native)
        XCTAssertFalse(rules.contains { if case .interval = $0.kind { return true }; return false })

        let out = TriggerCompiler.applyTriggers(
            to: root,
            native: native,
            rules: rules,
            pathIdsInOrder: []
        )
        XCTAssertEqual(out["StartInterval"] as? String, "bad")
        XCTAssertEqual(out["Label"] as? String, "t")
    }

    func test_applyTriggers_calendarArray_nonDictOrphan_preserved() {
        let intervals: [Any] = [
            ["Weekday": 1, "Hour": 9, "Minute": 0] as [String: Any],
            "oops",
            ["Hour": 8, "Minute": 0] as [String: Any],
        ]
        let root: [String: Any] = ["StartCalendarInterval": intervals]
        let native = TriggerCompiler.parseNative(from: root)
        XCTAssertEqual(native.calendarEntries.count, 2)
        XCTAssertEqual(native.calendarOrphans.count, 1)
        XCTAssertEqual(native.calendarOrphans[0].offset, 1)
        XCTAssertEqual(native.calendarOrphans[0].value as? String, "oops")

        let rules = TriggerCompiler.project(native)
        let out = TriggerCompiler.applyTriggers(
            to: root,
            native: native,
            rules: rules,
            pathIdsInOrder: []
        )
        guard let array = out["StartCalendarInterval"] as? [Any] else {
            return XCTFail("expected calendar array")
        }
        XCTAssertEqual(array.count, 3)
        XCTAssertEqual(array[1] as? String, "oops")
        XCTAssertEqual(
            array[0] as? NSDictionary,
            ["Weekday": 1, "Hour": 9, "Minute": 0] as NSDictionary
        )
        XCTAssertEqual(
            array[2] as? NSDictionary,
            ["Hour": 8, "Minute": 0] as NSDictionary
        )
    }

    func test_applyTriggers_invalidCalendarType_string_preserved() {
        let root: [String: Any] = [
            "Label": "t",
            "StartCalendarInterval": "nope",
        ]
        let native = TriggerCompiler.parseNative(from: root)
        XCTAssertTrue(native.calendarKeyPresent)
        XCTAssertTrue(native.calendarEntries.isEmpty)
        XCTAssertEqual(native.calendarRawValue as? String, "nope")
        let rules = TriggerCompiler.project(native)
        XCTAssertFalse(rules.contains {
            switch $0.kind {
            case .interval, .watchPath: return false
            default: return true
            }
        })

        let out = TriggerCompiler.applyTriggers(
            to: root,
            native: native,
            rules: rules,
            pathIdsInOrder: []
        )
        XCTAssertEqual(out["StartCalendarInterval"] as? String, "nope")
        XCTAssertEqual(out["Label"] as? String, "t")
    }
}
