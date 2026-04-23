import SwiftUI

struct SidebarView: View {
    @Binding var selectedScope: LaunchItem.Scope?
    @ObservedObject var store: AgentStore

    var body: some View {
        List(LaunchItem.Scope.allCases, id: \.self, selection: $selectedScope) { scope in
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(scope.displayName)
                    Text(scope.directoryHint)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: iconName(for: scope))
            }
            .badge(store.items.filter { $0.scope == scope }.count)
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
