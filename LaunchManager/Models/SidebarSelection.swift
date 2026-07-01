import Foundation

enum SidebarSelection: Hashable {
    case scope(LaunchItem.Scope)
    case loginItems
    case services
}
