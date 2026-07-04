import SwiftUI

struct AboutView: View {
    @ObservedObject var updateChecker: UpdateChecker
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            if let icon = NSImage(named: NSImage.applicationIconName) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 80, height: 80)
            } else {
                Image(systemName: "gearshape.2.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.blue)
            }

            VStack(spacing: 4) {
                Text("LaunchManager")
                    .font(.title2)
                    .fontWeight(.bold)
                Text(String(localized: "版本 \(appVersion)"))
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }

            Text("macOS 定时任务与开机启动管理工具")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Divider()

            VStack(spacing: 8) {
                Button {
                    updateChecker.checkNow()
                } label: {
                    if updateChecker.isChecking {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("检查更新…")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(updateChecker.isChecking)

                Link(destination: URL(string: "https://github.com/Sean10000/LaunchManager")!) {
                    Label("GitHub: Sean10000/LaunchManager", systemImage: "link")
                        .font(.subheadline)
                }

                Text("MIT License · 开源免费")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Button("关闭") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(32)
        .frame(width: 360)
    }

    private var appVersion: String {
        AppVersion.current.displayString
    }
}
