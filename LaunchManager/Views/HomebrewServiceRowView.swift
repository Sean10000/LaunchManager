import SwiftUI

struct HomebrewServiceRowView: View {
    let service: HomebrewService
    @ObservedObject var store: HomebrewServiceStore
    @Binding var errorMessage: String?

    @State private var isExpanded = false
    @State private var pulseOpacity = false

    private var pending: PendingOperation? {
        store.pendingOperations[service.id]
    }

    private var isRowLocked: Bool {
        pending != nil
    }

    private var statusColor: Color {
        if pending != nil { return .yellow }
        switch service.status {
        case .started: return .green
        case .stopped: return .orange
        case .error: return .red
        case .none: return Color(nsColor: .tertiaryLabelColor)
        case .unknown: return .yellow
        }
    }

    private var statusTooltip: String {
        if let exitCode = service.exitCode, service.status == .error {
            return "\(service.status.localizedName) (退出码 \(exitCode))"
        }
        return service.status.localizedName
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
                Text(service.name)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                Spacer()
                primaryActionButton
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
                    detailRow("状态", service.status.localizedName)
                    detailRow("Label", service.label)
                    if let user = service.runAsUser {
                        detailRow("用户", user)
                    }
                    if let path = service.plistPath {
                        detailRow("Plist", FilePathNormalizer.display(path))
                    }
                    if service.scope.requiresPrivilege {
                        detailRow("权限", String(localized: "启动/停止时需管理员密码"))
                    }
                    HStack(spacing: 8) {
                        if service.isRunning {
                            Button("重启") {
                                store.restart(service) { errorMessage = $0 }
                            }
                            .buttonStyle(.bordered).controlSize(.small)
                            .disabled(isRowLocked)
                        }
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
        } else if service.isRunning {
            Button("停止") {
                store.stop(service) { errorMessage = $0 }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        } else {
            Button("启动") {
                store.start(service) { errorMessage = $0 }
            }
            .buttonStyle(.bordered)
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
