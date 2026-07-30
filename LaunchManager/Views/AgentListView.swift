import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AgentListView: View {
    @ObservedObject var store: AgentStore
    @ObservedObject var homebrewStore: HomebrewServiceStore
    var searchText: String
    @Binding var newAgentScope: LaunchItem.Scope
    @Binding var showingNewAgent: Bool
    @Binding var showingNewFromXml: Bool
    @Binding var errorMessage: String?

    @State private var listFilter: AgentListFilter = .all
    @State private var collapsedGroups: Set<LaunchItem.Scope> = []
    @State private var importRequest: ImportPlistRequest?
    @State private var bootstrapAfterImport: LaunchItem?

    private struct ImportPlistRequest: Identifiable {
        let id = UUID()
        let url: URL
    }

    private var brewLookup: [String: HomebrewService] {
        homebrewStore.servicesByLabel
    }

    private var registeredLabels: Set<String> {
        Set(store.items.map(\.label))
    }

    private var brewActions: BrewRowActions {
        BrewRowActions(
            onStart: { homebrewStore.start($0) { errorMessage = $0 } },
            onStop: { homebrewStore.stop($0) { errorMessage = $0 } },
            onRestart: { homebrewStore.restart($0) { errorMessage = $0 } }
        )
    }

    private var unregisteredBrewServices: [HomebrewService] {
        let orphans = homebrewStore.unregisteredServices(excludingLabels: registeredLabels)
        guard !searchText.isEmpty else { return orphans }
        return orphans.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.label.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredItems: [LaunchItem] {
        var items = store.items
        items = applyScopeFilter(to: items)
        guard !searchText.isEmpty else { return items }
        return items.filter {
            $0.label.localizedCaseInsensitiveContains(searchText) ||
            $0.program.localizedCaseInsensitiveContains(searchText) ||
            ($0.brewFormulaName?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    private var filteredInvalidItems: [InvalidPlist] {
        var invalid = store.invalidItems
        if case .scope(let scope) = listFilter {
            invalid = invalid.filter { $0.scope == scope }
        } else if listFilter == .homebrew {
            invalid = []
        }
        guard !searchText.isEmpty else { return invalid }
        return invalid.filter {
            $0.url.lastPathComponent.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var groupedScopes: [LaunchItem.Scope] {
        LaunchItem.Scope.allCases.filter { scope in
            filteredItems.contains { $0.scope == scope } ||
            filteredInvalidItems.contains { $0.scope == scope }
        }
    }

    private var hasVisibleContent: Bool {
        !filteredItems.isEmpty || !filteredInvalidItems.isEmpty || !unregisteredBrewServices.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            Divider()

            Group {
                if !hasVisibleContent {
                    ContentUnavailableView(
                        emptyTitle,
                        systemImage: listFilter == .homebrew ? "mug" : "tray",
                        description: Text(emptyDescription)
                    )
                } else if listFilter == .homebrew {
                    homebrewListContent
                } else {
                    groupedListContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Launch Agents")
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
                Button { refreshAll() } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .disabled(homebrewStore.isRefreshing)
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

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                filterChip(.all)
                filterChip(.homebrew, icon: "mug.fill")
                ForEach(LaunchItem.Scope.allCases, id: \.self) { scope in
                    filterChip(.scope(scope), icon: scope.systemImage)
                }
            }
        }
    }

    private var homebrewListContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                if !unregisteredBrewServices.isEmpty {
                    unregisteredSection
                        .padding(.bottom, 8)
                }
                ForEach(filteredItems) { item in
                    agentRow(for: item)
                }
            }
            .padding()
        }
    }

    private var groupedListContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(groupedScopes, id: \.self) { scope in
                    agentGroupSection(scope: scope)
                }
            }
            .padding()
        }
    }

    private func filterChip(_ filter: AgentListFilter, icon: String? = nil) -> some View {
        Button {
            listFilter = filter
        } label: {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.caption2)
                }
                Text(filter.chipTitle)
            }
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(listFilter == filter ? chipFillColor(for: filter) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                Capsule()
                    .stroke(listFilter == filter ? chipStrokeColor(for: filter) : Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func chipFillColor(for filter: AgentListFilter) -> Color {
        filter == .homebrew ? Color(red: 0.24, green: 0.21, blue: 0.13) : Color.accentColor.opacity(0.25)
    }

    private func chipStrokeColor(for filter: AgentListFilter) -> Color {
        filter == .homebrew ? Color(red: 0.36, green: 0.29, blue: 0.07) : Color.accentColor
    }

    private var unregisteredSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "mug")
                    .foregroundStyle(.secondary)
                Text("未注册的 Homebrew 服务")
                    .font(.headline)
                Text("\(unregisteredBrewServices.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color(nsColor: .controlBackgroundColor)))
            }
            .padding(.horizontal, 4)

            ForEach(unregisteredBrewServices) { service in
                HomebrewServiceRowView(
                    service: service,
                    store: homebrewStore,
                    errorMessage: $errorMessage,
                    startButtonTitle: "注册并启动"
                )
            }
        }
    }

    private func agentRow(for item: LaunchItem) -> some View {
        let brew = brewLookup[item.label]
        return AgentRowView(
            item: item,
            brewService: brew,
            brewPending: brew.flatMap { homebrewStore.pendingOperations[$0.id] },
            brewActions: brew == nil ? nil : brewActions,
            store: store,
            errorMessage: $errorMessage
        )
    }

    private func refreshAll() {
        store.refresh()
        homebrewStore.refresh()
    }

    private func applyScopeFilter(to items: [LaunchItem]) -> [LaunchItem] {
        switch listFilter {
        case .all:
            return items
        case .homebrew:
            return items.filter(\.isBrewManaged)
        case .scope(let scope):
            return items.filter { $0.scope == scope }
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
        if listFilter == .homebrew {
            return searchText.isEmpty ? "没有 Homebrew 服务" : "没有匹配结果"
        }
        return searchText.isEmpty ? "没有 Agent" : "没有匹配结果"
    }

    private var emptyDescription: LocalizedStringKey {
        if listFilter == .homebrew {
            return searchText.isEmpty
                ? "已安装的 brew formula 在启动后会出现在对应分组中"
                : "尝试其他搜索词"
        }
        return searchText.isEmpty
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
                    agentRow(for: item)
                }
                ForEach(invalid) { item in
                    InvalidPlistRowView(item: item, store: store, errorMessage: $errorMessage)
                }
            }
        }
    }
}
