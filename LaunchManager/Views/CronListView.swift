import SwiftUI

struct CronListView: View {
    @ObservedObject var store: CrontabStore
    var searchText: String
    @Binding var newCronScope: CrontabScope
    @Binding var showingNewCron: Bool
    @Binding var errorMessage: String?

    @State private var collapsedGroups: Set<CrontabScope> = []

    private var filteredJobsByScope: [CrontabScope: [CronJob]] {
        Dictionary(uniqueKeysWithValues: CrontabScope.allCases.map { scope in
            let jobs = store.jobs(for: scope)
            guard !searchText.isEmpty else { return (scope, jobs) }
            let filtered = jobs.filter {
                $0.command.localizedCaseInsensitiveContains(searchText) ||
                $0.scheduleDescription.localizedCaseInsensitiveContains(searchText) ||
                ($0.runAsUser?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
            return (scope, filtered)
        })
    }

    private var groupedScopes: [CrontabScope] {
        CrontabScope.allCases.filter { scope in
            !(filteredJobsByScope[scope] ?? []).isEmpty || !store.preambleLines(for: scope).isEmpty
        }
    }

    private var hasVisibleContent: Bool {
        !groupedScopes.isEmpty
    }

    var body: some View {
        Group {
            if !hasVisibleContent {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: "clock",
                    description: Text(emptyDescription)
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(groupedScopes, id: \.self) { scope in
                            cronGroupSection(scope: scope)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Crontab")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ForEach(CrontabScope.allCases, id: \.self) { scope in
                        Button {
                            newCronScope = scope
                            showingNewCron = true
                        } label: {
                            Label(scope.newJobMenuTitle, systemImage: scope.systemImage)
                        }
                    }
                } label: {
                    Label("新建", systemImage: "plus")
                }
            }
            ToolbarItem {
                Button { store.refresh() } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .disabled(store.isRefreshing)
            }
        }
    }

    private func cronGroupSection(scope: CrontabScope) -> some View {
        let jobs = filteredJobsByScope[scope] ?? []
        let preamble = store.preambleLines(for: scope)
        let count = jobs.count
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
                if !preamble.isEmpty {
                    preambleSection(scope: scope, lines: preamble)
                }
                ForEach(jobs) { job in
                    CronRowView(job: job, store: store, errorMessage: $errorMessage)
                }
            }
        }
    }

    private func preambleSection(scope: CrontabScope, lines: [CrontabLine]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(scope == .system ? "文件头部" : "Crontab 头部")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(lines) { line in
                Text(preambleText(for: line))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func preambleText(for line: CrontabLine) -> String {
        switch line {
        case .blank:
            return ""
        case .comment(_, let text):
            return text
        case .environment(_, let key, let value):
            return "\(key)=\(value)"
        case .job:
            return ""
        case .raw(_, let text):
            return text
        }
    }

    private var emptyTitle: LocalizedStringKey {
        searchText.isEmpty ? "没有 Cron 任务" : "没有匹配结果"
    }

    private var emptyDescription: LocalizedStringKey {
        searchText.isEmpty
            ? "用户 crontab 与 /etc/crontab 均为空，点击「新建」添加定时任务"
            : "尝试其他搜索词"
    }
}
