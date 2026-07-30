import SwiftUI

struct CronRowView: View {
    let job: CronJob
    @ObservedObject var store: CrontabStore
    @Binding var errorMessage: String?

    @State private var isExpanded = false
    @State private var showingEdit = false
    @State private var showingDeleteConfirm = false

    private var statusColor: Color {
        job.isEnabled ? .green : .orange
    }

    private var statusTooltip: LocalizedStringKey {
        job.isEnabled ? "已启用" : "已禁用"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .help(statusTooltip)
                if job.scope == .system, let user = job.runAsUser {
                    Text(user)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 36, alignment: .leading)
                }
                Text(job.command)
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
                    detailRow("计划", job.scheduleDescription)
                    detailRow("表达式", expressionText)
                    if let user = job.runAsUser {
                        detailRow("用户", user)
                    }
                    detailRow("命令", FilePathNormalizer.display(job.command))
                    detailRow("来源", job.scope.sourceDescription)
                    if job.scope.requiresPrivilege {
                        detailRow("权限", String(localized: "写入时需管理员密码"))
                    }
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
            EditCronSheet(existingJob: job, scope: job.scope, store: store, errorMessage: $errorMessage)
        }
        .confirmationDialog(
            String(localized: "确认删除此 Cron 任务？"),
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                do { try store.deleteJob(id: job.id, scope: job.scope) }
                catch PrivilegeError.cancelled { }
                catch { errorMessage = error.localizedDescription }
            }
        } message: {
            Text(job.command)
        }
    }

    private var expressionText: String {
        if let user = job.runAsUser {
            return (job.scheduleFields + [user]).joined(separator: " ")
        }
        return job.scheduleFields.joined(separator: " ")
    }

    @ViewBuilder
    private var primaryActionButton: some View {
        if job.isEnabled {
            Button("禁用") {
                do { try store.setEnabled(id: job.id, scope: job.scope, enabled: false) }
                catch PrivilegeError.cancelled { }
                catch { errorMessage = error.localizedDescription }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        } else {
            Button("启用") {
                do { try store.setEnabled(id: job.id, scope: job.scope, enabled: true) }
                catch PrivilegeError.cancelled { }
                catch { errorMessage = error.localizedDescription }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    private func detailRow(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .leading)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        }
        .font(.caption)
    }
}
