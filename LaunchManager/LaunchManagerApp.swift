import SwiftUI

extension Notification.Name {
    static let showAbout = Notification.Name("showAbout")
}

@main
struct LaunchManagerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 700, minHeight: 450)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(replacing: .appInfo) {
                Button("关于 LaunchManager") {
                    NotificationCenter.default.post(name: .showAbout, object: nil)
                }
            }
        }
    }
}
