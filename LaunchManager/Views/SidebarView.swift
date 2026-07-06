import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarSelection?
    @ObservedObject var store: AgentStore
    @ObservedObject var crontabStore: CrontabStore
    @ObservedObject var homebrewStore: HomebrewServiceStore

    private var agentCount: Int {
        store.items.count + store.invalidItems.count
    }

    var body: some View {
        List {
            Section {
                SidebarRowButton(
                    selection: $selection,
                    tag: .agents,
                    title: Text("Launch Agents"),
                    subtitle: Text("用户 · 全局 · 系统"),
                    icon: "list.bullet.rectangle",
                    badge: agentCount
                )
            }

            Section {
                SidebarRowButton(
                    selection: $selection,
                    tag: .crontab,
                    title: Text("Crontab"),
                    subtitle: Text("用户 · 系统"),
                    icon: "clock",
                    badge: crontabStore.jobs.count
                )
            }

            Section {
                SidebarRowButton(
                    selection: $selection,
                    tag: .homebrew,
                    title: Text("Homebrew Services"),
                    subtitle: Text("用户 · 系统"),
                    icon: "mug.fill",
                    badge: homebrewStore.services.count
                )
            }

            Section {
                SidebarRowButton(
                    selection: $selection,
                    tag: .loginItems,
                    title: Text("Login Items"),
                    subtitle: Text("说明 · 系统设置"),
                    icon: "key.fill",
                    badge: 0
                )
            }

            Section {
                SidebarRowButton(
                    selection: $selection,
                    tag: .services,
                    title: Text("Services"),
                    subtitle: Text("本地开发环境"),
                    icon: "bolt.fill",
                    badge: 0
                )
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("LaunchManager")
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
