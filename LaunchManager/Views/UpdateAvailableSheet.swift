import AppKit
import SwiftUI

struct UpdateAvailableSheet: View {
    let release: GitHubRelease
    let currentVersion: AppVersion
    let onSkip: () -> Void
    let onDismiss: () -> Void

    @State private var copyConfirmed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("发现新版本")
                    .font(.title2)
                    .fontWeight(.bold)
                Text(String(localized: "LaunchManager \(release.version.displayString) 已发布"))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 24) {
                versionColumn("当前版本", currentVersion.displayString)
                versionColumn("最新版本", release.version.displayString)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("直接下载")
                    .font(.headline)
                Button {
                    NSWorkspace.shared.open(release.downloadURL)
                } label: {
                    Label("下载 LaunchManager.dmg", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Homebrew 升级")
                    .font(.headline)
                Text(GitHubRelease.homebrewUpgradeCommand)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Button(copyConfirmed ? "已复制" : "复制命令") {
                    copyHomebrewCommand()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(copyConfirmed)
            }

            Link(destination: release.releasePageURL) {
                Label("在 GitHub 查看 Release", systemImage: "link")
                    .font(.subheadline)
            }

            HStack {
                Button("跳过此版本", role: .destructive) {
                    onSkip()
                }
                .buttonStyle(.borderless)
                Spacer()
                Button("稍后") {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func versionColumn(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.monospaced())
                .fontWeight(.semibold)
        }
    }

    private func copyHomebrewCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(GitHubRelease.homebrewUpgradeCommand, forType: .string)
        copyConfirmed = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            copyConfirmed = false
        }
    }
}
