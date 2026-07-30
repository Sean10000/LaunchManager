import Foundation
import SwiftUI

enum AppModule: String, CaseIterable, Identifiable, Codable, Hashable {
    case agents
    case crontab
    case loginItems
    case services

    var id: String { rawValue }

    var sidebarSelection: SidebarSelection {
        switch self {
        case .agents: return .agents
        case .crontab: return .crontab
        case .loginItems: return .loginItems
        case .services: return .services
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .agents: return "Launch Agents"
        case .crontab: return "Crontab"
        case .loginItems: return "Login Items"
        case .services: return "Services"
        }
    }

    var subtitle: LocalizedStringKey {
        switch self {
        case .agents: return "用户 · 全局 · 系统 · Homebrew"
        case .crontab: return "用户 · 系统"
        case .loginItems: return "说明 · 系统设置"
        case .services: return "本地开发环境"
        }
    }

    var systemImage: String {
        switch self {
        case .agents: return "list.bullet.rectangle"
        case .crontab: return "clock"
        case .loginItems: return "key.fill"
        case .services: return "bolt.fill"
        }
    }

    var settingsDescription: LocalizedStringKey {
        switch self {
        case .agents: return "扫描 LaunchAgent / LaunchDaemon 与 Homebrew 服务"
        case .crontab: return "扫描用户与系统 Crontab"
        case .loginItems: return "说明页 · 跳转系统设置"
        case .services: return "扫描本地监听端口与开发服务"
        }
    }
}

enum AppLinks {
    static let helpURL = URL(string: "https://www.launchmanager.dev/help")!
}
