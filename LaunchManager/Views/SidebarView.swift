import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarSelection?
    @ObservedObject var store: AgentStore

    var body: some View {
        List {
            Section {
                ForEach(LaunchItem.Scope.allCases, id: \.self) { scope in
                    SidebarRowButton(
                        selection: $selection,
                        tag: .scope(scope),
                        title: Text(scope.displayName),
                        subtitle: Text(scope.directoryHint),
                        icon: iconName(for: scope),
                        badge: store.items.filter { $0.scope == scope }.count
                    )
                }
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
        }
        .listStyle(.sidebar)
        .navigationTitle("LaunchManager")
    }

    private func iconName(for scope: LaunchItem.Scope) -> String {
        switch scope {
        case .userAgent:    return "person.circle"
        case .systemAgent:  return "gearshape.circle"
        case .systemDaemon: return "server.rack"
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
