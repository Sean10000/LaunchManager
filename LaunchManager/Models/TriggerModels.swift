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
