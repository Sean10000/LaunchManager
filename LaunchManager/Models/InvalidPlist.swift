import Foundation

struct InvalidPlist: Identifiable {
    var id: URL { url }
    let url: URL
    let scope: LaunchItem.Scope
}
