import Foundation

enum ParseIssue: Hashable, Equatable {
    case invalidType(key: String, expected: String)
    case outOfRange(key: String, value: Int)
    case unknownKey(String)
}

struct CalendarEntry: Equatable {
    var weekday: Int?
    var month: Int?
    var day: Int?
    var hour: Int?
    var minute: Int?
    var raw: [String: Any]
    var diagnostics: [ParseIssue]
    var sessionId: UUID

    static func == (lhs: CalendarEntry, rhs: CalendarEntry) -> Bool {
        lhs.sessionId == rhs.sessionId
            && lhs.weekday == rhs.weekday
            && lhs.month == rhs.month
            && lhs.day == rhs.day
            && lhs.hour == rhs.hour
            && lhs.minute == rhs.minute
            && lhs.diagnostics == rhs.diagnostics
            && NSDictionary(dictionary: lhs.raw).isEqual(to: rhs.raw)
    }
}

struct NativeTriggers: Equatable {
    var calendarEntries: [CalendarEntry]
    var startInterval: Int?
    var startIntervalIssue: ParseIssue?
    var watchPaths: [String]
    /// Presence of key vs empty — derived at parse from root, not inventing persistence.
    var calendarKeyPresent: Bool
    var calendarIsArray: Bool
    var watchPathsKeyPresent: Bool
    /// Exact `StartCalendarInterval` value from root when the key is present.
    var calendarRawValue: Any?
    /// Non-dict elements in a `StartCalendarInterval` array, with original offsets.
    var calendarOrphans: [(offset: Int, value: Any)]

    static func == (lhs: NativeTriggers, rhs: NativeTriggers) -> Bool {
        lhs.calendarEntries == rhs.calendarEntries
            && lhs.startInterval == rhs.startInterval
            && lhs.startIntervalIssue == rhs.startIntervalIssue
            && lhs.watchPaths == rhs.watchPaths
            && lhs.calendarKeyPresent == rhs.calendarKeyPresent
            && lhs.calendarIsArray == rhs.calendarIsArray
            && lhs.watchPathsKeyPresent == rhs.watchPathsKeyPresent
            && isEqualAnyOptional(lhs.calendarRawValue, rhs.calendarRawValue)
            && lhs.calendarOrphans.count == rhs.calendarOrphans.count
            && zip(lhs.calendarOrphans, rhs.calendarOrphans).allSatisfy {
                $0.offset == $1.offset && isEqualAny($0.value, $1.value)
            }
    }
}

private func isEqualAnyOptional(_ lhs: Any?, _ rhs: Any?) -> Bool {
    switch (lhs, rhs) {
    case (nil, nil): return true
    case (nil, _), (_, nil): return false
    case let (l?, r?): return isEqualAny(l, r)
    }
}

private func isEqualAny(_ lhs: Any, _ rhs: Any) -> Bool {
    if let l = lhs as? [String: Any], let r = rhs as? [String: Any] {
        return NSDictionary(dictionary: l).isEqual(to: r)
    }
    if let l = lhs as? [Any], let r = rhs as? [Any] {
        guard l.count == r.count else { return false }
        return zip(l, r).allSatisfy { isEqualAny($0, $1) }
    }
    return (lhs as AnyObject).isEqual(rhs)
}

enum SourceRef: Hashable {
    case calendarEntry(UUID)
    case watchPath(UUID)
    case startInterval
}

enum TriggerRuleKind: Equatable {
    case daily(hour: Int, minute: Int)
    case weekly(weekdays: [Int], hour: Int, minute: Int) // launchd Weekday values
    case monthly(day: Int, hour: Int, minute: Int, months: Set<Int>?) // nil = all months
    case yearly(month: Int, day: Int, hour: Int, minute: Int)
    case interval(seconds: Int)
    case watchPath(String)
    case customCalendar(summary: String, isMalformed: Bool)
}

struct TriggerRule: Identifiable, Equatable {
    var id: UUID
    var kind: TriggerRuleKind
    var sourceRefs: [SourceRef]
    var isModified: Bool
}
