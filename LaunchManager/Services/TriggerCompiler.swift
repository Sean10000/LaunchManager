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

    // MARK: - Compile + apply

    static func compileCalendarDicts(kind: TriggerRuleKind) -> [[String: Any]] {
        switch kind {
        case .daily(let h, let m):
            return [["Hour": h, "Minute": m]]
        case .weekly(let days, let h, let m):
            return days.sorted().map { ["Weekday": $0, "Hour": h, "Minute": m] }
        case .monthly(let day, let h, let m, let months):
            if let months, !months.isEmpty {
                return months.sorted().map {
                    ["Month": $0, "Day": day, "Hour": h, "Minute": m]
                }
            }
            return [["Day": day, "Hour": h, "Minute": m]]
        case .yearly(let month, let day, let h, let m):
            return [["Month": month, "Day": day, "Hour": h, "Minute": m]]
        default:
            return []
        }
    }

    /// Rebuild StartCalendarInterval / StartInterval / WatchPaths from rules + native.
    /// Unmodified calendar rules copy `raw` from referenced entries in original relative order.
    /// Modified preset rules replace their refs with compiled dicts (extras after the last ref).
    static func applyTriggers(
        to root: [String: Any],
        native: NativeTriggers,
        rules: [TriggerRule],
        pathIdsInOrder: [UUID]
    ) -> [String: Any] {
        var result = root

        let entryById: [UUID: CalendarEntry] = Dictionary(
            uniqueKeysWithValues: native.calendarEntries.map { ($0.sessionId, $0) }
        )

        var ruleByCalendarSessionId: [UUID: TriggerRule] = [:]
        var referencedSessionIds: Set<UUID> = []
        for rule in rules {
            for ref in rule.sourceRefs {
                guard case .calendarEntry(let id) = ref else { continue }
                referencedSessionIds.insert(id)
                ruleByCalendarSessionId[id] = rule
            }
        }

        // Precompute ordered native calendar refs per rule (original encounter order).
        var nativeRefsByRuleId: [UUID: [UUID]] = [:]
        for entry in native.calendarEntries {
            guard let rule = ruleByCalendarSessionId[entry.sessionId] else { continue }
            nativeRefsByRuleId[rule.id, default: []].append(entry.sessionId)
        }

        // Remaining compiled dicts per modified rule; matched by Weekday/Month, not index.
        var remainingCompiledByRuleId: [UUID: [[String: Any]]] = [:]
        var calendarDicts: [[String: Any]] = []

        for entry in native.calendarEntries {
            guard referencedSessionIds.contains(entry.sessionId) else {
                continue // deleted
            }
            guard let rule = ruleByCalendarSessionId[entry.sessionId] else { continue }

            // Custom: always keep raw (v1 has no custom editor); modified flag does not rewrite.
            if case .customCalendar = rule.kind {
                calendarDicts.append(entry.raw)
                continue
            }

            if rule.isModified {
                if remainingCompiledByRuleId[rule.id] == nil {
                    remainingCompiledByRuleId[rule.id] = compileCalendarDicts(kind: rule.kind)
                }
                var remaining = remainingCompiledByRuleId[rule.id] ?? []
                if remaining.isEmpty {
                    // No compiled output (or all slots already taken) — skip this ref.
                    remainingCompiledByRuleId[rule.id] = remaining
                } else if let matchIndex = Self.indexOfCompiledMatch(
                    remaining: remaining, kind: rule.kind, entry: entry
                ) {
                    calendarDicts.append(remaining.remove(at: matchIndex))
                    remainingCompiledByRuleId[rule.id] = remaining
                } else {
                    // Native weekday/month removed from the edited kind — drop this slot.
                    remainingCompiledByRuleId[rule.id] = remaining
                }

                // After the last native ref of this rule, append extras (new weekdays/months).
                let refs = nativeRefsByRuleId[rule.id] ?? []
                if entry.sessionId == refs.last {
                    let extras = remainingCompiledByRuleId[rule.id] ?? []
                    calendarDicts.append(contentsOf: extras)
                    remainingCompiledByRuleId[rule.id] = []
                }
            } else {
                calendarDicts.append(entry.raw)
            }
        }

        // Brand-new calendar rules: empty sourceRefs or no refs present in native.
        for rule in rules {
            switch rule.kind {
            case .interval, .watchPath, .customCalendar:
                continue
            default:
                break
            }
            let calendarRefs = rule.sourceRefs.compactMap { ref -> UUID? in
                if case .calendarEntry(let id) = ref { return id }
                return nil
            }
            let hasExistingNativeRef = calendarRefs.contains { entryById[$0] != nil }
            if hasExistingNativeRef { continue }

            let compiled = compileCalendarDicts(kind: rule.kind)
            guard !compiled.isEmpty else { continue }
            calendarDicts.append(contentsOf: compiled)
        }

        // Write StartCalendarInterval shape: single dict when count==1 and original was not array.
        if calendarDicts.isEmpty {
            if native.calendarKeyPresent {
                result["StartCalendarInterval"] = [[String: Any]]()
            } else {
                result.removeValue(forKey: "StartCalendarInterval")
            }
        } else if calendarDicts.count == 1, !native.calendarIsArray {
            result["StartCalendarInterval"] = calendarDicts[0]
        } else {
            result["StartCalendarInterval"] = calendarDicts
        }

        // Interval
        let intervalRule = rules.first { if case .interval = $0.kind { return true }; return false }
        if let intervalRule, case .interval(let seconds) = intervalRule.kind {
            if !intervalRule.isModified,
               native.startInterval == seconds,
               result["StartInterval"] != nil
            {
                // Leave key as-is (don't rewrite).
            } else {
                result["StartInterval"] = seconds
            }
        } else if native.startInterval != nil || result["StartInterval"] != nil {
            result.removeValue(forKey: "StartInterval")
        }

        // WatchPaths: rewrite only when dirty or path set/order changed.
        var newWatchPaths: [String] = []
        if pathIdsInOrder.isEmpty {
            for rule in rules {
                guard case .watchPath(let path) = rule.kind else { continue }
                newWatchPaths.append(path)
            }
        } else {
            for pathId in pathIdsInOrder {
                guard let rule = rules.first(where: {
                    $0.sourceRefs.contains(.watchPath(pathId))
                }),
                case .watchPath(let path) = rule.kind
                else { continue }
                newWatchPaths.append(path)
            }
        }

        let watchDirty = rules.contains {
            if case .watchPath = $0.kind { return $0.isModified }
            return false
        }
        if watchDirty || newWatchPaths != native.watchPaths {
            if newWatchPaths.isEmpty {
                result.removeValue(forKey: "WatchPaths")
            } else {
                result["WatchPaths"] = newWatchPaths
            }
        }
        // else leave key untouched (preserve missing vs [])

        return result
    }

    /// Match a compiled slot to a native entry by Weekday (weekly) or Month (monthly-with-months).
    /// Other kinds take the first remaining compiled dict.
    private static func indexOfCompiledMatch(
        remaining: [[String: Any]],
        kind: TriggerRuleKind,
        entry: CalendarEntry
    ) -> Int? {
        switch kind {
        case .weekly:
            guard let weekday = entry.weekday else { return remaining.isEmpty ? nil : 0 }
            return remaining.firstIndex { ($0["Weekday"] as? Int) == weekday }
        case .monthly(_, _, _, let months) where months != nil && !(months?.isEmpty ?? true):
            guard let month = entry.month else { return remaining.isEmpty ? nil : 0 }
            return remaining.firstIndex { ($0["Month"] as? Int) == month }
        default:
            return remaining.isEmpty ? nil : 0
        }
    }
}
