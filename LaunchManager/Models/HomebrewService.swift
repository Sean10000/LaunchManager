import Foundation

enum HomebrewServiceStatus: String, Hashable {
    case started
    case stopped
    case none
    case error
    case unknown

    init(brewStatus: String) {
        switch brewStatus {
        case "started": self = .started
        case "stopped": self = .stopped
        case "none": self = .none
        case "error": self = .error
        default: self = .unknown
        }
    }

    var localizedName: String {
        switch self {
        case .started: return String(localized: "运行中")
        case .stopped: return String(localized: "已停止")
        case .none: return String(localized: "未注册")
        case .error: return String(localized: "错误")
        case .unknown: return String(localized: "未知")
        }
    }
}

struct HomebrewService: Identifiable, Hashable {
    var name: String
    var scope: HomebrewServiceScope
    var status: HomebrewServiceStatus
    var runAsUser: String?
    var plistPath: String?
    var exitCode: Int?

    var id: String { "\(scope.rawValue):\(name)" }
    var label: String { "homebrew.mxcl.\(name)" }

    var isRunning: Bool { status == .started }
    var isRegistered: Bool { status == .started || status == .stopped }
}
