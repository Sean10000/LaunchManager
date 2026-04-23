import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)

            VStack(spacing: 4) {
                Text("LaunchManager")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("版本 \(appVersion)")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }

            Text("macOS 定时任务与开机启动管理工具")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Divider()

            VStack(spacing: 8) {
                Link(destination: URL(string: "https://github.com/Sean10000/LaunchManager")!) {
                    Label("GitHub: Sean10000/LaunchManager", systemImage: "link")
                        .font(.subheadline)
                }

                Text("MIT License · 开源免费")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(32)
        .frame(width: 360)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
}
