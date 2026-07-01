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

    var body: some View {
        Group {
            if filteredServices.isEmpty {
                ContentUnavailableView(
                    "没有发现开发服务",
                    systemImage: "bolt.slash",
                    description: Text("尝试启动 dev server，或开启「显示全部」")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(filteredServices) { service in
                            ServiceRowView(
                                service: service,
                                store: store,
                                errorMessage: $errorMessage
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .searchable(text: $searchText, prompt: "搜索服务名、端口或项目")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Toggle("显示全部", isOn: $store.showAll)
                    .onChange(of: store.showAll) { _, _ in
                        store.refresh()
                    }
            }
            if store.lastScanError != nil {
                ToolbarItem {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .help(store.lastScanError ?? "")
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
