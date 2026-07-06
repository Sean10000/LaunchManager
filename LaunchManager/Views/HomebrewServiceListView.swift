import SwiftUI

struct HomebrewServiceListView: View {
    @ObservedObject var store: HomebrewServiceStore
    var searchText: String
    @Binding var errorMessage: String?

    @State private var collapsedGroups: Set<HomebrewServiceScope> = []

    private var filteredServicesByScope: [HomebrewServiceScope: [HomebrewService]] {
        Dictionary(uniqueKeysWithValues: HomebrewServiceScope.allCases.map { scope in
            let services = store.services(for: scope)
            guard !searchText.isEmpty else { return (scope, services) }
            let filtered = services.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.label.localizedCaseInsensitiveContains(searchText) ||
                ($0.plistPath?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
            return (scope, filtered)
        })
    }

    private var groupedScopes: [HomebrewServiceScope] {
        HomebrewServiceScope.allCases.filter { scope in
            !(filteredServicesByScope[scope] ?? []).isEmpty
        }
    }

    var body: some View {
        Group {
            if !store.brewAvailable {
                ContentUnavailableView(
                    "未找到 Homebrew",
                    systemImage: "exclamationmark.triangle",
                    description: Text("请安装 Homebrew，或确认 /opt/homebrew/bin/brew 可用。")
                )
            } else if groupedScopes.isEmpty {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: "mug",
                    description: Text(emptyDescription)
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(groupedScopes, id: \.self) { scope in
                            serviceGroupSection(scope: scope)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Homebrew Services")
        .toolbar {
            ToolbarItem {
                Button { store.refresh() } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .disabled(store.isRefreshing)
            }
        }
    }

    private func serviceGroupSection(scope: HomebrewServiceScope) -> some View {
        let services = filteredServicesByScope[scope] ?? []
        let count = services.count
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

            if !isCollapsed {
                ForEach(services) { service in
                    HomebrewServiceRowView(service: service, store: store, errorMessage: $errorMessage)
                }
            }
        }
    }

    private var emptyTitle: LocalizedStringKey {
        searchText.isEmpty ? "没有 Homebrew 服务" : "没有匹配结果"
    }

    private var emptyDescription: LocalizedStringKey {
        searchText.isEmpty
            ? "通过 brew install 安装带 service 的 formula 后，会显示在这里"
            : "尝试其他搜索词"
    }
}
