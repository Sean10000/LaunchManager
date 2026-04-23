import SwiftUI

struct AgentRowView: View {
    let item: LaunchItem
    @ObservedObject var store: AgentStore
    @Binding var errorMessage: String?

    @State private var isExpanded = false
    @State private var showingEdit = false
    @State private var showingLog  = false
    @State private var showingDeleteConfirm = false

    var statusColor: Color {
        if item.pid != nil { return .green }
        if let code = item.lastExitCode {
            if code == 0  { return .blue.opacity(0.7) }
            if code > 0   { return .yellow }
            // negative code = killed by signal (intentional stop) → gray
        }
        return Color(nsColor: .tertiaryLabelColor)
    }

    var statusTooltip: String {
        if item.pid != nil { return "运行中 (PID \(item.pid!))" }
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
                Circle().fill(statusColor).frame(width: 8, height: 8)
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
                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if isExpanded {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    detailRow("程序", ([item.program] + item.programArguments).joined(separator: " "))
                    detailRow("触发", triggerDescription)
                    detailRow("路径", item.plistURL.path)
                    HStack(spacing: 8) {
                        if item.isLoaded {
                            Button("卸载") { perform { try store.unload(item) } }
                                .buttonStyle(.bordered).controlSize(.small)
                        }
                        Button("查看日志") { showingLog = true }
                            .buttonStyle(.bordered).controlSize(.small)
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
            "确认删除 \(item.label)？",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                perform { try store.delete(item) }
            }
        } message: {
            Text("此操作将 unload 并永久删除 plist 文件，无法撤销。")
        }
    }

    @ViewBuilder
    private var primaryActionButton: some View {
        if item.pid != nil {
            Button("停止") { perform { try store.stop(item) } }
                .buttonStyle(.borderedProminent).controlSize(.small)
        } else if item.isLoaded {
            Button("启动") { perform { try store.start(item) } }
                .buttonStyle(.bordered).controlSize(.small)
        } else {
            Button("加载") { perform { try store.load(item) } }
                .buttonStyle(.bordered).controlSize(.small)
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
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
            guard let ci = item.calendarInterval else { return "定时" }
            let day = ci.weekday.map { "周\($0)" } ?? "每天"
            let h   = ci.hour.map { String(format: "%02d", $0) } ?? "每小时"
            return "\(day) \(h):\(String(format: "%02d", ci.minute))"
        case .interval:
            return "每 \(item.startInterval ?? 0) 秒"
        case .atLoad:
            return "登录时"
        case .watchPath:
            return "监视路径：\(item.watchPaths.first ?? "")"
        }
    }

    private func perform(_ action: @escaping () throws -> Void) {
        do { try action() }
        catch { errorMessage = error.localizedDescription }
    }
}
