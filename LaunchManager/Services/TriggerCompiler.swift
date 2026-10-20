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
}
