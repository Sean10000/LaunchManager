import AppKit
import SwiftUI

struct ServiceRowView: View {
    let service: Service
    @ObservedObject var store: ServiceStore
    @Binding var errorMessage: String?
    var onCreateLaunchAgent: (LaunchAgentDraft) -> Void

    @State private var isExpanded = false
    @State private var showingKillConfirm = false
    @State private var copyConfirmed = false
    @State private var renameText = ""
    @State private var isEditingName = false

    private var isKilling: Bool { store.pendingKillIDs.contains(service.id) }

    private var statusColor: Color {
        service.health == .healthy ? .green : .red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .help("PID \(service.pid)")

                if service.isHomebrewManaged {
                    HomebrewTag()
                }

                summaryText
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                Spacer()

                if isKilling {
                    ProgressView().controlSize(.small)
                } else {
                    primaryActionButton
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .disabled(isKilling)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if isExpanded {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    renameSection
                    if service.isHomebrewManaged, let formula = service.brewFormulaName {
                        detailRow("来源", "Homebrew · \(formula)")
                        if let label = service.brewLaunchdLabel {
                            detailRow("Launchd", label)
                        }
                    }
                    if service.identityKind == .hostMechanism {
                        detailRow("类型", String(localized: "宿主机制"))
                    }
                    if let docker = service.dockerInfo {
                        detailRow("容器", docker.containerLabel)
                        detailRow("镜像", docker.image)
                        if let project = docker.composeProject {
                            detailRow("Compose", project)
                        }
                        detailRow("容器 ID", docker.shortID)
                    }
                    detailRow("程序", FilePathNormalizer.display(service.command))
                    detailRow("PID", "\(service.pid)")
                    detailRow("可执行", FilePathNormalizer.display(service.executable))
                    if let projectDir = service.workingDirectory {
                        detailRow("项目目录", FilePathNormalizer.display(projectDir))
                    }
                    if let processDir = service.processDirectory,
                       processDir != service.workingDirectory {
                        detailRow("进程目录", FilePathNormalizer.display(processDir))
                    }

                    HStack(spacing: 8) {
                        if service.runtimeGroup == .instance && service.killAllowed,
                           let draft = LaunchAgentDraft.from(service: service) {
                            Button("创建 Launch Agent…") {
                                onCreateLaunchAgent(draft)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        Button(copyConfirmed ? "已复制" : "复制地址") {
                            copyAddress()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(copyConfirmed)

                        if let url = service.url {
                            Button("Open") {
                                NSWorkspace.shared.open(url)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        Button(killButtonTitle, role: .destructive) {
                            showingKillConfirm = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isKilling || !service.killAllowed)
                        .help(service.killBlockedReason ?? "")
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
        .confirmationDialog(
            killDialogTitle,
            isPresented: $showingKillConfirm,
            titleVisibility: .visible
        ) {
            Button(killConfirmActionTitle, role: .destructive) {
                store.kill(service) { errorMessage = $0 }
            }
        } message: {
            Text(killConfirmMessage)
        }
        .onChange(of: isExpanded) { _, expanded in
            if expanded {
                renameText = service.displayName
                isEditingName = false
            }
        }
        .onChange(of: renameText) { _, _ in
            isEditingName = true
        }
        .onChange(of: service.displayName) { _, newName in
            if !isEditingName { renameText = newName }
        }
    }

    private var renameSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("显示名称")
                    .foregroundStyle(.secondary)
                    .frame(width: 56, alignment: .leading)
                TextField("显示名称", text: $renameText)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .onSubmit { saveRename() }
                Button("保存") { saveRename() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if store.hasCustomName(for: service) {
                    Button("恢复自动") {
                        store.clearCustomName(for: service)
                        renameText = service.autoDisplayName
                        isEditingName = false
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
            }
            if store.hasCustomName(for: service) {
                Text(String(localized: "已自定义名称（自动识别: \(service.autoDisplayName)）"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .padding(.bottom, 4)
    }

    private func saveRename() {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if trimmed == service.autoDisplayName {
            store.clearCustomName(for: service)
        } else {
            store.setCustomName(trimmed, for: service)
        }
        isEditingName = false
    }

    private var summaryText: some View {
        HStack(spacing: 4) {
            Text(service.displayName)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(0)

            if let subtitle = service.subtitle {
                Text("·")
                    .foregroundStyle(.secondary)
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(-1)
            }

            Spacer(minLength: 8)

            Text(service.addressLabel)
                .foregroundStyle(.secondary)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
        }
    }

    private var killButtonTitle: LocalizedStringKey {
        service.usesDockerStop ? "停止容器…" : "终止进程…"
    }

    private var killDialogTitle: LocalizedStringKey {
        service.usesDockerStop ? "确认停止容器？" : "确认终止服务？"
    }

    private var killConfirmActionTitle: LocalizedStringKey {
        service.usesDockerStop ? "停止容器" : "终止进程"
    }

    private var killConfirmMessage: String {
        var lines = [service.displayName, service.addressLabel]
        if let docker = service.dockerInfo {
            lines.append(String(localized: "容器: \(docker.containerLabel)"))
            lines.append(String(localized: "镜像: \(docker.image)"))
        } else {
            lines.append(String(localized: "PID \(service.pid)"))
        }
        if let dir = service.workingDirectory {
            lines.append(FilePathNormalizer.display(dir))
        }
        return lines.joined(separator: "\n")
    }

    @ViewBuilder
    private var primaryActionButton: some View {
        if let url = service.url {
            Button("Open") {
                NSWorkspace.shared.open(url)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        } else {
            Button(copyConfirmed ? "已复制" : "复制地址") {
                copyAddress()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(copyConfirmed)
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

    private func copyAddress() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(service.addressLabel, forType: .string)
        copyConfirmed = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            copyConfirmed = false
        }
    }
}
