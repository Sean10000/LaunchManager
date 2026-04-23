import SwiftUI

struct OnboardingView: View {
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text("🚀")
                    .font(.system(size: 52))
                Text("欢迎使用 LaunchManager")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("macOS 定时任务与开机启动管理")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                FeatureCard(
                    icon: "list.bullet.rectangle",
                    title: "管理启动项",
                    description: "浏览 LaunchAgent 和 LaunchDaemon，无需打开终端"
                )
                FeatureCard(
                    icon: "clock.badge.checkmark",
                    title: "自定义调度",
                    description: "按时间、间隔或路径变化触发，灵活配置执行计划"
                )
                FeatureCard(
                    icon: "doc.text.magnifyingglass",
                    title: "查看 XML",
                    description: "直接在界面打开 plist 配置文件，一键查看原始内容"
                )
                FeatureCard(
                    icon: "arrow.2.circlepath",
                    title: "加载 vs 运行",
                    description: "加载：launchd 登记该任务。运行：任务当前正在执行"
                )
            }

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.system(size: 13, weight: .semibold))
                VStack(alignment: .leading, spacing: 3) {
                    Text("关于删除操作")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.orange)
                    Text("删除 plist 仅移除自动执行配置，不影响应用本身。删除后该任务不再自动运行（如开机自启或定时执行）。系统级操作需要管理员密码授权。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .background(Color.orange.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
            )
            .cornerRadius(8)

            Button("开始使用") {
                isPresented = false
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(28)
        .frame(width: 520)
    }
}

private struct FeatureCard: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(.blue)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}
