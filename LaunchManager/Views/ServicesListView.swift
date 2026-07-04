import SwiftUI

struct ServicesListView: View {
    @ObservedObject var store: ServiceStore
    @Binding var errorMessage: String?
    var onCreateLaunchAgent: (LaunchAgentDraft) -> Void

    @State private var searchText = ""
    @State private var collapsedGroups: Set<ServiceRuntimeGroup> = []

    private var filteredServices: [Service] {
        guard !searchText.isEmpty else { return store.services }
        return store.services.filter { service in
            service.displayName.localizedCaseInsensitiveContains(searchText) ||
            (service.subtitle?.localizedCaseInsensitiveContains(searchText) ?? false) ||
            String(service.port).contains(searchText) ||
            service.executable.localizedCaseInsensitiveContains(searchText) ||
            service.addressLabel.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var groupedServices: [(ServiceRuntimeGroup, [Service])] {
        ServiceRuntimeGroup.allCases.compactMap { group in
            let items = filteredServices.filter { $0.runtimeGroup == group }
            return items.isEmpty ? nil : (group, items)
        }
    }

    var body: some View {
        Group {
            if filteredServices.isEmpty {
                ContentUnavailableView(
                    emptyStateTitle,
                    systemImage: store.lastScanError == nil ? "bolt.slash" : "exclamationmark.triangle",
                    description: Text(emptyStateDescription)
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(groupedServices, id: \.0) { group, services in
                            serviceGroupSection(group: group, services: services)
                        }
                    }
                    .padding()
                }
            }
        }
        .searchable(text: $searchText, prompt: "搜索服务名、端口、项目…")
        .toolbar {
            if store.lastScanError != nil {
                ToolbarItem {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .help(store.lastScanError ?? "")
                }
            }
            ToolbarItem {
                Toggle("显示全部", isOn: $store.showAll)
            }
            ToolbarItem {
                Button { store.refreshNow() } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
            }
        }
    }

    private var emptyStateTitle: LocalizedStringKey {
        if store.lastScanError != nil { return "扫描失败" }
        if !store.showAll { return "没有发现开发服务" }
        return "没有发现服务"
    }

    private var emptyStateDescription: String {
        if let error = store.lastScanError { return error }
        if !store.showAll {
            return String(localized: "尝试启动 dev server，或开启「显示全部」")
        }
        return String(localized: "当前没有监听中的 TCP 服务")
    }

    private func serviceGroupSection(group: ServiceRuntimeGroup, services: [Service]) -> some View {
        let isCollapsed = collapsedGroups.contains(group)

        return VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if isCollapsed {
                        collapsedGroups.remove(group)
                    } else {
                        collapsedGroups.insert(group)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: group.systemImage)
                        .foregroundStyle(.secondary)
                    Text(group.title)
                        .font(.headline)
                    Text("\(services.count)")
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
            .accessibilityLabel(isCollapsed ? "展开 \(group.title)" : "收起 \(group.title)")

            if !isCollapsed {
                ForEach(services) { service in
                    ServiceRowView(
                        service: service,
                        store: store,
                        errorMessage: $errorMessage,
                        onCreateLaunchAgent: onCreateLaunchAgent
                    )
                }
            }
        }
    }
}
