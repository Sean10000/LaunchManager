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
        var minute: Int
    }

    /// 列表/详情用的触发摘要行（固定顺序）。
    var triggerSummaryLines: [String] {
        var lines: [String] = []
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
        for ci in calendarIntervals {
            let day: String
            if let w = ci.weekday, (1...7).contains(w) {
                day = weekdayNames[w]
            } else {
                day = String(localized: "每天")
            }
            let h = ci.hour.map { String(format: "%02d", $0) } ?? "**"
            lines.append("\(day) \(h):\(String(format: "%02d", ci.minute))")
        }
        if let si = startInterval {
            lines.append(String(localized: "每 \(si) 秒"))
        }
        for path in watchPaths {
            lines.append(String(localized: "监视路径：\(path)"))
        }
        if runAtLoad {
            lines.append(String(localized: "加载时运行"))
        }
        if lines.isEmpty {
            lines.append(String(localized: "无自动触发"))
        }
        return lines
    }
}
