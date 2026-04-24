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
    var isLoaded: Bool
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
