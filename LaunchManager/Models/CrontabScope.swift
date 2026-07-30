import Foundation
import SwiftUI

enum CrontabScope: String, CaseIterable, Hashable {
    case user
    case system

    var displayName: String {
        switch self {
        case .user: return String(localized: "用户 Crontab")
        case .system: return String(localized: "系统 Crontab")
        }
    }

    var sectionTitle: LocalizedStringKey {
        switch self {
        case .user: return "用户 Crontab"
        case .system: return "系统 Crontab"
        }
    }

    var sectionSubtitle: LocalizedStringKey {
        switch self {
        case .user: return "crontab -l"
        case .system: return "/etc/crontab"
        }
    }

    var systemImage: String {
        switch self {
        case .user: return "person.circle"
        case .system: return "server.rack"
        }
    }

    var newJobMenuTitle: LocalizedStringKey {
        switch self {
        case .user: return "新建用户 Cron 任务"
        case .system: return "新建系统 Cron 任务"
        }
    }

    var sourceDescription: String {
        switch self {
        case .user: return "crontab -l"
        case .system: return "/etc/crontab"
        }
    }

    var requiresPrivilege: Bool { self == .system }

    var parserFormat: CrontabFormat {
        switch self {
        case .user: return .user
        case .system: return .system
        }
    }
}

enum CrontabFormat {
    case user
    case system
}
