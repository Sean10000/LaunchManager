import Foundation
import SwiftUI

enum SidebarSelection: Hashable {
    case agents
    case crontab
    case loginItems
    case services

    var appModule: AppModule? {
        switch self {
        case .agents: return .agents
        case .crontab: return .crontab
        case .loginItems: return .loginItems
        case .services: return .services
        }
    }
}

enum AgentListFilter: Hashable {
    case all
    case homebrew
    case scope(LaunchItem.Scope)

    var chipTitle: LocalizedStringKey {
        switch self {
        case .all: return "全部"
        case .homebrew: return "Homebrew"
        case .scope(let scope):
            switch scope {
            case .userAgent: return "用户级"
            case .systemAgent: return "全局"
            case .systemDaemon: return "Daemon"
            }
        }
    }
}
