import SwiftUI

struct AgentRowView: View {
    let item: LaunchItem
    let brewService: HomebrewService?
    let brewPending: PendingOperation?
    let brewActions: BrewRowActions?
    @ObservedObject var store: AgentStore
    @Binding var errorMessage: String?

    @State private var isExpanded = false
    @State private var showingEdit = false
    @State private var showingClone = false
    @State private var showingLog  = false
    @State private var showingDeleteConfirm = false
    @State private var pulseOpacity = false

    private var usesBrewOperations: Bool {
        item.isBrewManaged && brewService != nil && brewActions != nil
    }

    private var pending: PendingOperation? {
        brewPending ?? store.pendingOperations[item.label]
    }

    private var isRowLocked: Bool {
        pending != nil
    }

    var statusColor: Color {
        if pending != nil { return .yellow }
        if usesBrewOperations, let brewService {
            switch brewService.status {
            case .started:
                return item.pid != nil ? .green : .yellow
            case .stopped:
                if item.pid != nil { return .yellow }
                return .orange
            case .error: return .red
            case .none: return Color(nsColor: .tertiaryLabelColor)
            case .unknown: return .yellow
            }
        }
        if item.isDisabledByOverride && item.pid == nil { return .orange }
        if item.pid != nil { return .green }
        if let code = item.lastExitCode {
            if code == 0  { return .blue.opacity(0.7) }
            if code > 0   { return .yellow }
        }
        return Color(nsColor: .tertiaryLabelColor)
    }

    private var statusTooltip: String {
        if item.isDisabledByOverride {
            return String(localized: "已被系统禁用（launchctl override）")
        }
        if usesBrewOperations, let brewService {
            if let exitCode = brewService.exitCode, brewService.status == .error {
                return "Homebrew: \(brewService.status.localizedName) (退出码 \(exitCode))"
            }
            if brewService.status == .stopped, item.pid != nil {
                return String(localized: "Brew 已停止，但进程仍在运行 (PID \(item.pid!))")
            }
            if brewService.status == .started, item.pid == nil {
                return String(localized: "Brew: 运行中，等待进程启动")
            }
            return "Homebrew: \(brewService.status.localizedName)"
        }
        if let pid = item.pid { return String(localized: "运行中 (PID \(pid))") }
        if let code = item.lastExitCode {
            if code == 0  { return String(localized: "上次执行：正常退出 (0)") }
            if code < 0   { return String(localized: "已停止 (信号 \(-code))") }
            return String(localized: "上次执行：退出码 \(code)")
        }
        return String(localized: item.isLoaded ? "已加载，等待触发" : "未加载")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .opacity(isRowLocked ? (pulseOpacity ? 1.0 : 0.35) : 1.0)
                    .animation(
                        isRowLocked ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default,
                        value: pulseOpacity
                    )
                    .onAppear { pulseOpacity = true }
                    .onChange(of: isRowLocked) { _, locked in
                        pulseOpacity = locked
                    }
                    .help(Text(statusTooltip))
                if item.isBrewManaged {
                    HomebrewTag()
                }
                Text(item.label)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                primaryActionButton
                Button { showingEdit = true } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .disabled(isRowLocked)
                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(isRowLocked)
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .disabled(isRowLocked)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if isExpanded {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    if let formula = item.brewFormulaName {
                        detailRow("Formula", formula)
                    }
                    if usesBrewOperations, let brewService {
                        detailRow("管理方式", String(localized: "brew services"))
                        detailRow("Brew 状态", brewService.status.localizedName)
                        if let exitCode = brewService.exitCode {
                            detailRow("退出码", "\(exitCode)")
                        }
                        if let user = brewService.runAsUser {
                            detailRow("用户", user)
                        }
                    }
                    detailRow("程序", FilePathNormalizer.display(([item.program] + item.programArguments).joined(separator: " ")))
                    detailRow("触发", triggerDescription)
                    detailRow("路径", FilePathNormalizer.display(item.plistURL.path))
                    HStack(spacing: 8) {
                        if usesBrewOperations, let brewService, let brewActions {
                            if brewService.isRunning {
                                Button("重启") {
                                    brewActions.onRestart(brewService)
                                }
                                .buttonStyle(.bordered).controlSize(.small)
                                .disabled(isRowLocked)
                            }
                        } else if item.isLoaded {
                            Button("移除") {
                                store.bootout(item) { errorMessage = $0 }
                            }
                            .buttonStyle(.bordered).controlSize(.small)
                            .disabled(isRowLocked)
                        }
                        Button("复制…") { showingClone = true }
                            .buttonStyle(.bordered).controlSize(.small)
                            .disabled(isRowLocked)
                        Button("查看日志") { showingLog = true }
                            .buttonStyle(.bordered).controlSize(.small)
                            .disabled(isRowLocked)
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
        )
        .sheet(isPresented: $showingEdit) {
            EditAgentSheet(existingItem: item, defaultScope: item.scope, store: store)
        }
        .sheet(isPresented: $showingClone) {
            CloneAgentSheet(item: item, store: store, errorMessage: $errorMessage)
        }
        .sheet(isPresented: $showingLog) {
            LogViewerSheet(item: item)
        }
        .confirmationDialog(
            String(localized: "确认删除 \(item.label)？"),
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                do { try store.delete(item) }
                catch { errorMessage = error.localizedDescription }
            }
        } message: {
            Text("此操作将 bootout 并永久删除 plist 文件，无法撤销。")
        }
    }

    @ViewBuilder
    private var primaryActionButton: some View {
        if let pending {
            Button {} label: {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(pending.localizedLabel)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(true)
        } else if usesBrewOperations, let brewService, let brewActions {
            if brewService.isRunning {
                Button("停止") {
                    brewActions.onStop(brewService)
                }
                .buttonStyle(.borderedProminent).controlSize(.small)
            } else {
                Button("启动") {
                    brewActions.onStart(brewService)
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
        } else if item.pid != nil {
            Button("停止") {
                store.stop(item) { errorMessage = $0 }
            }
            .buttonStyle(.borderedProminent).controlSize(.small)
        } else if item.isDisabledByOverride && !item.isLoaded {
            Button("启用") {
                store.enable(item) { errorMessage = $0 }
            }
            .buttonStyle(.borderedProminent).controlSize(.small)
        } else if item.isLoaded {
            Button("启动") {
                store.start(item) { errorMessage = $0 }
            }
            .buttonStyle(.bordered).controlSize(.small)
        } else {
            Button("载入") {
                store.bootstrap(item) { errorMessage = $0 }
            }
            .buttonStyle(.bordered).controlSize(.small)
        }
    }

    private func detailRow(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        }
        .font(.caption)
    }

    private var triggerDescription: String {
        switch item.triggerType {
        case .calendar:
            guard let ci = item.calendarInterval else {
                return String(localized: "定时")
            }
            let day = ci.weekday.map { String(localized: "周\($0)") }
                    ?? String(localized: "每天")
            let h = ci.hour.map { String(format: "%02d", $0) } ?? "**"
            return "\(day) \(h):\(String(format: "%02d", ci.minute))"
        case .interval:
            return String(localized: "每 \(item.startInterval ?? 0) 秒")
        case .atLoad:
            return String(localized: "登录时")
        case .watchPath:
            return String(localized: "监视路径：\(item.watchPaths.first ?? "")")
        }
    }
}
