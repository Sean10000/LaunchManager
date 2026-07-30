import AppKit
import ServiceManagement
import SwiftUI

enum LoginItemsSettings {
    static func openSystemSettings() {
        if #available(macOS 13.0, *) {
            SMAppService.openSystemSettingsLoginItems()
        } else if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

struct LoginItemsGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Login Items 与 Launchd 的区别")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("系统「登录项」请在本页了解后，前往系统设置管理。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                GuideCard(
                    icon: "gearshape.2",
                    title: "Launchd（本应用管理）",
                    description: "对应侧边栏中的 LaunchAgent / LaunchDaemon，plist 位于 ~/Library/LaunchAgents、/Library/LaunchAgents、/Library/LaunchDaemons。可在本应用中载入、移除、启动与停止。"
                )

                GuideCard(
                    icon: "key.fill",
                    title: "Login Items（系统设置管理）",
                    description: "位于「系统设置 → 通用 → 登录项」，包括「打开时登录」的应用与「允许在后台」的项目。由 macOS 统一管理，本应用不提供列表或开关。"
                )

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text("许多 Login Item 背后对应同一个 launchd plist，若已在 Launch Agents / LaunchDaemons 中出现，请在本应用相应分类中管理。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)

                Button {
                    LoginItemsSettings.openSystemSettings()
                } label: {
                    Label("打开登录项设置", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(24)
            .frame(maxWidth: 560, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("Login Items")
    }
}

private struct GuideCard: View {
    let icon: String
    let title: LocalizedStringKey
    let description: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(.blue)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}
