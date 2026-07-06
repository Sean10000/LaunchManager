import Foundation

enum HomebrewServiceScope: String, CaseIterable, Hashable {
    case user
    case root

    var sectionTitle: LocalizedStringKey {
        switch self {
        case .user: return "用户服务"
        case .root: return "系统服务"
        }
    }

    var sectionSubtitle: LocalizedStringKey {
        switch self {
        case .user: return "brew services · ~/Library/LaunchAgents"
        case .root: return "sudo brew services · /Library/LaunchDaemons"
        }
    }

    var systemImage: String {
        switch self {
        case .user: return "person.circle"
        case .root: return "server.rack"
        }
    }

    var requiresPrivilege: Bool { self == .root }
}
