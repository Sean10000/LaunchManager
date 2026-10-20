import Foundation
import SwiftUI

struct LaunchItem: Identifiable, Hashable {
    var id: String { label }
    var label: String
    var plistURL: URL
    var scope: Scope
    var program: String
    var programArguments: [String]
    var calendarIntervals: [CalendarInterval]
    var startInterval: Int?
    var watchPaths: [String]
    var runAtLoad: Bool
    var keepAlive: Bool
    var standardOutPath: String?
    var standardErrorPath: String?
    var workingDirectory: String?
    var environmentVariables: [String: String] = [:]
    var isLoaded: Bool
    var isDisabledByOverride: Bool = false
    var pid: Int?
    var lastExitCode: Int?
    /// List/detail trigger summary; set at parse from root dict via `summaryLines(from:runAtLoad:)`.
    var triggerSummaryLines: [String] = []

    enum Scope: String, CaseIterable, Hashable {
        case userAgent    = "userAgent"
        case systemAgent  = "systemAgent"
        case systemDaemon = "systemDaemon"

        var displayName: String {
            switch self {
            case .userAgent, .systemAgent: return "LaunchAgent"
            case .systemDaemon:            return "LaunchDaemon"
            }
        }

        var directoryHint: LocalizedStringKey {
            switch self {
            case .userAgent:    return "用户级 · ~/Library"
            case .systemAgent:  return "全局 · /Library"
            case .systemDaemon: return "系统级 · /Library"
            }
        }

        var sectionTitle: LocalizedStringKey {
            switch self {
            case .userAgent:    return "用户 Agents"
            case .systemAgent:  return "全局 Agents"
            case .systemDaemon: return "LaunchDaemons"
            }
        }

        var sectionSubtitle: LocalizedStringKey {
            switch self {
            case .userAgent:    return "~/Library/LaunchAgents"
            case .systemAgent:  return "/Library/LaunchAgents"
            case .systemDaemon: return "/Library/LaunchDaemons"
            }
        }

        var systemImage: String {
            switch self {
            case .userAgent:    return "person.circle"
            case .systemAgent:  return "gearshape.circle"
            case .systemDaemon: return "server.rack"
            }
        }

        var newAgentMenuTitle: LocalizedStringKey {
            switch self {
            case .userAgent:    return "新建用户 Agent"
            case .systemAgent:  return "新建全局 Agent"
            case .systemDaemon: return "新建 LaunchDaemon"
            }
        }

        var directoryURL: URL {
            switch self {
            case .userAgent:
                return FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/LaunchAgents")
            case .systemAgent:
                return URL(fileURLWithPath: "/Library/LaunchAgents")
            case .systemDaemon:
                return URL(fileURLWithPath: "/Library/LaunchDaemons")
            }
        }

        var requiresPrivilege: Bool { self != .userAgent }
    }

    struct CalendarInterval: Hashable {
        var weekday: Int?
        var hour: Int?
        var minute: Int?
        var day: Int?
        var month: Int?

        init(
            weekday: Int? = nil,
            hour: Int? = nil,
            minute: Int? = nil,
            day: Int? = nil,
            month: Int? = nil
        ) {
            self.weekday = weekday
            self.hour = hour
            self.minute = minute
            self.day = day
            self.month = month
        }
    }

    /// Launch-condition keys shown as passthrough in list summaries (not form-edited as rules).
    static let passthroughLaunchKeys: Set<String> = [
        "QueueDirectories", "StartOnMount", "Sockets",
    ]

    /// Build list summary lines from a plist root via TriggerCompiler projection.
    static func summaryLines(from root: [String: Any], runAtLoad: Bool) -> [String] {
        let native = TriggerCompiler.parseNative(from: root)
        let rules = TriggerCompiler.project(native)
        var lines: [String] = rules.map { line(for: $0.kind) }

        let passthroughCount = passthroughLaunchKeys.filter { root[$0] != nil }.count
        if passthroughCount > 0 {
            lines.append(
                String(
                    format: String(localized: "+%lld 其它启动条件"),
                    locale: .current,
                    passthroughCount
                )
            )
        }

        if runAtLoad {
            lines.append(String(localized: "加载时运行一次"))
        }

        if lines.isEmpty {
            lines.append(String(localized: "无自动触发"))
        }
        return lines
    }

    private static func line(for kind: TriggerRuleKind) -> String {
        switch kind {
        case .daily(let hour, let minute):
            return "\(String(localized: "每天")) \(timeString(hour: hour, minute: minute))"
        case .weekly(let weekdays, let hour, let minute):
            let days = formatWeekdays(weekdays)
            return "\(days) \(timeString(hour: hour, minute: minute))"
        case .monthly(let day, let hour, let minute, let months):
            let time = timeString(hour: hour, minute: minute)
            if let months, !months.isEmpty {
                let monthList = months.sorted().map(String.init).joined(separator: ",")
                return String(
                    format: String(localized: "每月 · %@ 月 · %lld 日 %@"),
                    locale: .current,
                    monthList, day, time
                )
            }
            return String(
                format: String(localized: "每月 %lld 日 %@"),
                locale: .current,
                day, time
            )
        case .yearly(let month, let day, let hour, let minute):
            let time = timeString(hour: hour, minute: minute)
            return String(
                format: String(localized: "每年 %lld 月 %lld 日 %@"),
                locale: .current,
                month, day, time
            )
        case .interval(let seconds):
            return String(localized: "每 \(seconds) 秒")
        case .watchPath(let path):
            return String(localized: "监视路径：\(path)")
        case .customCalendar(let summary, let isMalformed):
            if isMalformed {
                return String(
                    format: String(localized: "配置异常：%@"),
                    locale: .current,
                    summary
                )
            }
            return String(
                format: String(localized: "自定义日历：%@"),
                locale: .current,
                summary
            )
        }
    }

    private static func timeString(hour: Int, minute: Int) -> String {
        String(format: "%02d:%02d", hour, minute)
    }

    private static func formatWeekdays(_ weekdays: [Int]) -> String {
        let weekdayNames = [
            "",
            String(localized: "周一"),
            String(localized: "周二"),
            String(localized: "周三"),
            String(localized: "周四"),
            String(localized: "周五"),
            String(localized: "周六"),
            String(localized: "周日"),
        ]
        let normalized = Array(Set(weekdays.map { $0 == 0 ? 7 : $0 }))
            .filter { (1...7).contains($0) }
            .sorted()
        guard !normalized.isEmpty else { return "" }
        let names = normalized.map { weekdayNames[$0] }
        if names.count >= 2 {
            let consecutive = zip(normalized, normalized.dropFirst()).allSatisfy { $1 - $0 == 1 }
            if consecutive {
                return "\(names.first!)至\(names.last!)"
            }
        }
        return names.joined(separator: "、")
    }
}
