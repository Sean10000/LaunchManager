import Foundation

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
        case userAgent    = "用户 Agents"
        case systemAgent  = "系统 Agents"
        case systemDaemon = "系统 Daemons"

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
        case calendar  = "定时"
        case interval  = "间隔"
        case atLoad    = "登录时"
        case watchPath = "监视路径"
    }

    struct CalendarInterval: Hashable {
        var weekday: Int?
        var hour: Int?
        var minute: Int
    }
}
