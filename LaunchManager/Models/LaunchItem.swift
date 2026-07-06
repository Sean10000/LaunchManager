import Foundation
import SwiftUI

struct LaunchItem: Identifiable, Hashable {
    var id: String { label }
    var label: String
    var plistURL: URL
    var scope: Scope
    var program: String
    var programArguments: [String]
    var triggerType: TriggerType
    var calendarInterval: CalendarInterval?
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

    enum TriggerType: String, CaseIterable, Hashable {
        case calendar  = "calendar"
        case interval  = "interval"
        case atLoad    = "atLoad"
        case watchPath = "watchPath"

        var localizedName: LocalizedStringKey {
            switch self {
            case .calendar:  return "定时"
            case .interval:  return "间隔"
            case .atLoad:    return "登录时"
            case .watchPath: return "监视路径"
            }
        }
    }

    struct CalendarInterval: Hashable {
        var weekday: Int?
        var hour: Int?
        var minute: Int
    }
}
