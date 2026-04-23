//
//  LaunchManagerApp.swift
//  LaunchManager
//
//  Created by Shi-Cheng Ma on 2026/4/22.
//

import SwiftUI

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
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
            }
        }

        Settings {
            AboutView()
        }
    }
}
