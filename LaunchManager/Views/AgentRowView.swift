import SwiftUI

struct AgentRowView: View {
    let item: LaunchItem
    @ObservedObject var store: AgentStore
    @Binding var errorMessage: String?

    @State private var isExpanded = false
    @State private var showingEdit = false
    @State private var showingLog  = false
    @State private var showingDeleteConfirm = false
    @State private var pulseOpacity = false

    private var pending: PendingOperation? {
        store.pendingOperations[item.label]
    }

    private var isRowLocked: Bool {
        pending != nil
    }

    var statusColor: Color {
        if pending != nil { return .yellow }
        if item.pid != nil { return .green }
        if let code = item.lastExitCode {
            if code == 0  { return .blue.opacity(0.7) }
            if code > 0   { return .yellow }
            // negative code = killed by signal (intentional stop) → gray
        }
        return Color(nsColor: .tertiaryLabelColor)
    }

    var statusTooltip: LocalizedStringKey {
        if let pid = item.pid { return "运行中 (PID \(pid))" }
        if let code = item.lastExitCode {
            if code == 0  { return "上次执行：正常退出 (0)" }
            if code < 0   { return "已停止 (信号 \(-code))" }
            return "上次执行：退出码 \(code)"
        }
        return item.isLoaded ? "已加载，等待触发" : "未加载"
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
                    .help(statusTooltip)
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
                    detailRow("程序", FilePathNormalizer.display(([item.program] + item.programArguments).joined(separator: " ")))
                    detailRow("触发", triggerDescription)
                    detailRow("路径", FilePathNormalizer.display(item.plistURL.path))
                    HStack(spacing: 8) {
                        if item.isLoaded {
                            Button("移除") {
                                store.bootout(item) { errorMessage = $0 }
                            }
                            .buttonStyle(.bordered).controlSize(.small)
                            .disabled(isRowLocked)
                        }
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
        } else if item.pid != nil {
            Button("停止") {
                store.stop(item) { errorMessage = $0 }
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
                .frame(width: 36, alignment: .leading)
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
