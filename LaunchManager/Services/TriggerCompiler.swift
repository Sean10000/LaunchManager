import Foundation

enum TriggerCompiler {
    static let knownCalendarKeys: Set<String> = [
        "Weekday", "Month", "Day", "Hour", "Minute"
    ]

    static func parseEntry(_ dict: [String: Any], sessionId: UUID = UUID()) -> CalendarEntry {
        var diagnostics: [ParseIssue] = []
        for key in dict.keys where !knownCalendarKeys.contains(key) {
            diagnostics.append(.unknownKey(key))
        }

        func parseInt(_ key: String, range: ClosedRange<Int>) -> Int? {
            guard let any = dict[key] else { return nil }
            let value: Int?
            if let i = any as? Int { value = i }
            else if let n = any as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() {
                value = n.intValue
            } else {
                diagnostics.append(.invalidType(key: key, expected: "Int"))
                return nil
            }
            guard let value else { return nil }
            guard range.contains(value) else {
                diagnostics.append(.outOfRange(key: key, value: value))
                return nil
            }
            return value
        }

        return CalendarEntry(
            weekday: parseInt("Weekday", range: 0...7),
            month: parseInt("Month", range: 1...12),
            day: parseInt("Day", range: 1...31),
            hour: parseInt("Hour", range: 0...23),
            minute: parseInt("Minute", range: 0...59),
            raw: dict,
            diagnostics: diagnostics,
            sessionId: sessionId
        )
    }

    static func parseNative(from root: [String: Any]) -> NativeTriggers {
        var entries: [CalendarEntry] = []
        var calendarKeyPresent = false
        var calendarIsArray = false
        if let value = root["StartCalendarInterval"] {
            calendarKeyPresent = true
            if let dict = value as? [String: Any] {
                entries = [parseEntry(dict)]
            } else if let array = value as? [Any] {
                calendarIsArray = true
                entries = array.compactMap { el in
                    guard let d = el as? [String: Any] else { return nil }
                    return parseEntry(d)
                }
            }
        }

        var startInterval: Int?
        var startIntervalIssue: ParseIssue?
        if let any = root["StartInterval"] {
            if let i = any as? Int { startInterval = i }
            else if let n = any as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() {
                startInterval = n.intValue
            } else {
                startIntervalIssue = .invalidType(key: "StartInterval", expected: "Int")
            }
        }

        let watchPathsKeyPresent = root["WatchPaths"] != nil
        let watchPaths = root["WatchPaths"] as? [String] ?? []

        return NativeTriggers(
            calendarEntries: entries,
            startInterval: startInterval,
            startIntervalIssue: startIntervalIssue,
            watchPaths: watchPaths,
            calendarKeyPresent: calendarKeyPresent,
            calendarIsArray: calendarIsArray,
            watchPathsKeyPresent: watchPathsKeyPresent
        )
    }

    // MARK: - Projection

    static func presentKeys(_ entry: CalendarEntry) -> Set<String> {
        Set(entry.raw.keys)
    }

    static func isPresetCandidate(_ entry: CalendarEntry) -> Bool {
        entry.diagnostics.isEmpty && presentKeys(entry).isSubset(of: knownCalendarKeys)
    }

    static func summary(for entry: CalendarEntry) -> String {
        knownCalendarKeys.sorted().compactMap { key -> String? in
            guard let v = entry.raw[key] else { return nil }
            return "\(key)=\(v)"
        }.joined(separator: " ")
    }

    static func classifySingleton(_ entry: CalendarEntry) -> TriggerRuleKind {
        guard isPresetCandidate(entry) else {
            return .customCalendar(
                summary: summary(for: entry),
                isMalformed: !entry.diagnostics.isEmpty
            )
        }

        let keys = presentKeys(entry)
        if keys == Set(["Hour", "Minute"]),
           let hour = entry.hour,
           let minute = entry.minute
        {
            return .daily(hour: hour, minute: minute)
        }
        if keys == Set(["Weekday", "Hour", "Minute"]),
           let weekday = entry.weekday,
           let hour = entry.hour,
           let minute = entry.minute
        {
            return .weekly(weekdays: [weekday], hour: hour, minute: minute)
        }
        if keys == Set(["Day", "Hour", "Minute"]),
           let day = entry.day,
           let hour = entry.hour,
           let minute = entry.minute
        {
            return .monthly(day: day, hour: hour, minute: minute, months: nil)
        }
        if keys == Set(["Month", "Day", "Hour", "Minute"]),
           let month = entry.month,
           let day = entry.day,
           let hour = entry.hour,
           let minute = entry.minute
        {
            return .yearly(month: month, day: day, hour: hour, minute: minute)
        }
        // Day+Weekday, missing optionals despite key set, or any other non-preset → custom
        return .customCalendar(summary: summary(for: entry), isMalformed: false)
    }

    static func project(_ native: NativeTriggers) -> [TriggerRule] {
        var rules: [TriggerRule] = []
        var consumed: Set<UUID> = []
        let entries = native.calendarEntries

        for entry in entries {
            if consumed.contains(entry.sessionId) { continue }

            let keys = presentKeys(entry)

            // Weekly merge: same Hour+Minute, only Weekday differs
            if isPresetCandidate(entry),
               keys == Set(["Weekday", "Hour", "Minute"]),
               let hour = entry.hour,
               let minute = entry.minute,
               let weekday = entry.weekday
            {
                var weekdays: [Int] = [weekday]
                var refs: [SourceRef] = [.calendarEntry(entry.sessionId)]
                consumed.insert(entry.sessionId)

                for other in entries {
                    if consumed.contains(other.sessionId) { continue }
                    guard isPresetCandidate(other),
                          presentKeys(other) == Set(["Weekday", "Hour", "Minute"]),
                          other.hour == hour,
                          other.minute == minute,
                          let wd = other.weekday
                    else { continue }
                    weekdays.append(wd)
                    refs.append(.calendarEntry(other.sessionId))
                    consumed.insert(other.sessionId)
                }

                // Keep all sourceRefs (fidelity); unique+sorted weekdays for the kind only
                let uniqueWeekdays = Array(Set(weekdays)).sorted()
                rules.append(TriggerRule(
                    id: UUID(),
                    kind: .weekly(weekdays: uniqueWeekdays, hour: hour, minute: minute),
                    sourceRefs: refs,
                    isModified: false
                ))
                continue
            }

            // Month merge: same Day+Hour+Minute, only Month differs → monthly(months:)
            // Single Month+Day+Hour+Minute stays yearly. Never strip months when count == 12.
            if isPresetCandidate(entry),
               keys == Set(["Month", "Day", "Hour", "Minute"]),
               let month = entry.month,
               let day = entry.day,
               let hour = entry.hour,
               let minute = entry.minute
            {
                var months: Set<Int> = [month]
                var refs: [SourceRef] = [.calendarEntry(entry.sessionId)]
                consumed.insert(entry.sessionId)

                for other in entries {
                    if consumed.contains(other.sessionId) { continue }
                    guard isPresetCandidate(other),
                          presentKeys(other) == Set(["Month", "Day", "Hour", "Minute"]),
                          other.day == day,
                          other.hour == hour,
                          other.minute == minute,
                          let m = other.month
                    else { continue }
                    months.insert(m)
                    refs.append(.calendarEntry(other.sessionId))
                    consumed.insert(other.sessionId)
                }

                let kind: TriggerRuleKind
                if refs.count == 1 {
                    kind = .yearly(month: month, day: day, hour: hour, minute: minute)
                } else {
                    kind = .monthly(day: day, hour: hour, minute: minute, months: months)
                }

                rules.append(TriggerRule(
                    id: UUID(),
                    kind: kind,
                    sourceRefs: refs,
                    isModified: false
                ))
                continue
            }

            consumed.insert(entry.sessionId)
            rules.append(TriggerRule(
                id: UUID(),
                kind: classifySingleton(entry),
                sourceRefs: [.calendarEntry(entry.sessionId)],
                isModified: false
            ))
        }

        if let seconds = native.startInterval {
            rules.append(TriggerRule(
                id: UUID(),
                kind: .interval(seconds: seconds),
                sourceRefs: [.startInterval],
                isModified: false
            ))
        }

        for path in native.watchPaths {
            let pathId = UUID()
            rules.append(TriggerRule(
                id: UUID(),
                kind: .watchPath(path),
                sourceRefs: [.watchPath(pathId)],
                isModified: false
            ))
        }

        return rules
    }
}
