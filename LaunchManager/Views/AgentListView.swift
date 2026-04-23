import SwiftUI

struct AgentListView: View {
    let items: [LaunchItem]
    let invalidItems: [InvalidPlist]
    @ObservedObject var store: AgentStore
    @Binding var showingNewAgent: Bool
    @Binding var errorMessage: String?

    var body: some View {
        Group {
            if items.isEmpty && invalidItems.isEmpty {
                ContentUnavailableView(
                    "没有 Agent",
                    systemImage: "tray",
                    description: Text("此分类下暂无 LaunchAgent / Daemon")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(items) { item in
                            AgentRowView(item: item, store: store, errorMessage: $errorMessage)
                        }
                        ForEach(invalidItems) { item in
                            InvalidPlistRowView(item: item, store: store, errorMessage: $errorMessage)
                        }
                    }
                    .padding()
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingNewAgent = true } label: {
                    Label("新建", systemImage: "plus")
                }
            }
            ToolbarItem {
                Button { store.refresh() } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
            }
        }
    }
}
