import AppKit
import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarSelection?
    @ObservedObject var moduleSettings: ModuleSettingsStore
    @ObservedObject var store: AgentStore
    @ObservedObject var crontabStore: CrontabStore
    @Binding var showModuleSettings: Bool
    var onHelpTapped: () -> Void

    private var agentCount: Int {
        store.items.count + store.invalidItems.count
    }

    private var enabledModules: [AppModule] {
        moduleSettings.settings.enabledModules
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    ForEach(enabledModules) { module in
                        SidebarRowButton(
                            selection: $selection,
                            tag: module.sidebarSelection,
                            title: Text(module.title),
                            subtitle: Text(module.subtitle),
                            icon: module.systemImage,
                            badge: badge(for: module)
                        )
                    }
                }

                Section {
                    Button {
                        onHelpTapped()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "book.fill")
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("用户手册")
                                Text("launchmanager.dev/help")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("LaunchManager")

            Divider()

            HStack(spacing: 10) {
                Button {
                    showModuleSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 15))
                }
                .buttonStyle(.plain)
                .help("模块设置")

                Spacer()

                Text(AppVersion.current.displayString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private func badge(for module: AppModule) -> Int {
        switch module {
        case .agents: return agentCount
        case .crontab: return crontabStore.jobs.count
        case .loginItems, .services: return 0
        }
    }
}

private struct SidebarRowButton: View {
    @Binding var selection: SidebarSelection?
    let tag: SidebarSelection
    let title: Text
    let subtitle: Text
    let icon: String
    let badge: Int

    private var isSelected: Bool { selection == tag }

    var body: some View {
        Button {
            selection = tag
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    title
                    subtitle
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if badge > 0 {
                    Text(verbatim: "\(badge)")
                        .font(.caption2)
                        .monospacedDigit()
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(isSelected ? Color.accentColor : nil)
    }
}
