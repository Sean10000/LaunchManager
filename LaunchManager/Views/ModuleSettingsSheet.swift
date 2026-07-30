import SwiftUI

struct ModuleSettingsSheet: View {
    @ObservedObject var moduleSettings: ModuleSettingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var showMinimumModuleAlert = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("模块设置")
                    .font(.headline)
                Spacer()
                Button("全选") {
                    moduleSettings.enableAll()
                }
                .buttonStyle(.borderless)
            }
            .padding()

            Divider()

            Form {
                Section {
                    Text("至少保留一个模块。未勾选的模块不会出现在侧边栏，也不会执行后台扫描。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("显示与扫描") {
                    ForEach(AppModule.allCases) { module in
                        Toggle(isOn: binding(for: module)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(module.title)
                                Text(module.settingsDescription)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 420, height: 420)
        .alert("至少保留一个模块", isPresented: $showMinimumModuleAlert) {
            Button("确定", role: .cancel) {}
        } message: {
            Text("请至少启用一个模块。")
        }
    }

    private func binding(for module: AppModule) -> Binding<Bool> {
        Binding(
            get: { moduleSettings.isEnabled(module) },
            set: { newValue in
                if newValue {
                    _ = moduleSettings.setEnabled(module, enabled: true)
                } else if !moduleSettings.setEnabled(module, enabled: false) {
                    showMinimumModuleAlert = true
                }
            }
        )
    }
}
