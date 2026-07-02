import SwiftUI

struct ServicesListView: View {
    @ObservedObject var store: ServiceStore
    @Binding var errorMessage: String?

    @State private var searchText = ""

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
                    "没有发现服务",
                    systemImage: "bolt.slash",
                    description: Text("当前没有监听中的 TCP 服务")
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
                Button { store.refreshNow() } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
            }
        }
    }

    private func serviceGroupSection(group: ServiceRuntimeGroup, services: [Service]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
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
            }
            .padding(.horizontal, 4)

            ForEach(services) { service in
                ServiceRowView(
                    service: service,
                    store: store,
                    errorMessage: $errorMessage
                )
            }
        }
    }
}
