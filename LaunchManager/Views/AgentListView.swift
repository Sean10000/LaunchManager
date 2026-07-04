import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AgentListView: View {
    @ObservedObject var store: AgentStore
    var searchText: String
    @Binding var newAgentScope: LaunchItem.Scope
    @Binding var showingNewAgent: Bool
    @Binding var showingNewFromXml: Bool
    @Binding var errorMessage: String?

    @State private var collapsedGroups: Set<LaunchItem.Scope> = []
    @State private var importRequest: ImportPlistRequest?
    @State private var bootstrapAfterImport: LaunchItem?

    private struct ImportPlistRequest: Identifiable {
        let id = UUID()
        let url: URL
    }

    private var filteredItems: [LaunchItem] {
        guard !searchText.isEmpty else { return store.items }
        return store.items.filter {
            $0.label.localizedCaseInsensitiveContains(searchText) ||
            $0.program.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredInvalidItems: [InvalidPlist] {
        guard !searchText.isEmpty else { return store.invalidItems }
        return store.invalidItems.filter {
            $0.url.lastPathComponent.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var groupedScopes: [LaunchItem.Scope] {
        LaunchItem.Scope.allCases.filter { scope in
            filteredItems.contains { $0.scope == scope } ||
            filteredInvalidItems.contains { $0.scope == scope }
        }
    }

    var body: some View {
        Group {
            if filteredItems.isEmpty && filteredInvalidItems.isEmpty {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: "tray",
                    description: Text(emptyDescription)
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(groupedScopes, id: \.self) { scope in
                            agentGroupSection(scope: scope)
                        }
                    }
                    .padding()
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ForEach(LaunchItem.Scope.allCases, id: \.self) { scope in
                        Button {
                            newAgentScope = scope
                            showingNewAgent = true
                        } label: {
                            Label(scope.newAgentMenuTitle, systemImage: scope.systemImage)
                        }
                    }
                    Divider()
                    Button {
                        newAgentScope = .userAgent
                        showingNewFromXml = true
                    } label: {
                        Label("从 XML 粘贴…", systemImage: "doc.on.clipboard")
                    }
                } label: {
                    Label("新建", systemImage: "plus")
                }
            }
            ToolbarItem {
                Button { pickAndImportPlist() } label: {
                    Label("导入", systemImage: "square.and.arrow.down")
                }
            }
            ToolbarItem {
                Button { store.refresh() } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
            }
        }
        .sheet(item: $importRequest) { request in
            ImportPlistSheet(
                sourceURL: request.url,
                store: store,
                errorMessage: $errorMessage,
                onImported: { item in bootstrapAfterImport = item }
            )
        }
        .confirmationDialog(
            "是否立即载入？",
            isPresented: Binding(
                get: { bootstrapAfterImport != nil },
                set: { if !$0 { bootstrapAfterImport = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("载入") {
                if let item = bootstrapAfterImport {
                    store.bootstrap(item) { errorMessage = $0 }
                }
                bootstrapAfterImport = nil
            }
            Button("稍后", role: .cancel) {
                bootstrapAfterImport = nil
            }
        } message: {
            if let item = bootstrapAfterImport {
                Text(item.label)
            }
        }
    }

    private func pickAndImportPlist() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.propertyList]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importRequest = ImportPlistRequest(url: url)
    }

    private var emptyTitle: LocalizedStringKey {
        searchText.isEmpty ? "没有 Agent" : "没有匹配结果"
    }

    private var emptyDescription: LocalizedStringKey {
        searchText.isEmpty
            ? "暂无 LaunchAgent / LaunchDaemon"
            : "尝试其他搜索词"
    }

    private func items(for scope: LaunchItem.Scope) -> [LaunchItem] {
        filteredItems.filter { $0.scope == scope }
    }

    private func invalidItems(for scope: LaunchItem.Scope) -> [InvalidPlist] {
        filteredInvalidItems.filter { $0.scope == scope }
    }

    private func agentGroupSection(scope: LaunchItem.Scope) -> some View {
        let items = items(for: scope)
        let invalid = invalidItems(for: scope)
        let count = items.count + invalid.count
        let isCollapsed = collapsedGroups.contains(scope)

        return VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if isCollapsed {
                        collapsedGroups.remove(scope)
                    } else {
                        collapsedGroups.insert(scope)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: scope.systemImage)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(scope.sectionTitle)
                            .font(.headline)
                        Text(scope.sectionSubtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text("\(count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color(nsColor: .controlBackgroundColor)))
                    Spacer()
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .foregroundStyle(.secondary)
                        .font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isCollapsed ? "展开 \(scope.sectionTitle)" : "收起 \(scope.sectionTitle)")

            if !isCollapsed {
                ForEach(items) { item in
                    AgentRowView(item: item, store: store, errorMessage: $errorMessage)
                }
                ForEach(invalid) { item in
                    InvalidPlistRowView(item: item, store: store, errorMessage: $errorMessage)
                }
            }
        }
    }
}
