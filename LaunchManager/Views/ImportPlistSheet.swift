import SwiftUI

struct ImportPlistSheet: View {
    let sourceURL: URL
    @ObservedObject var store: AgentStore
    @Binding var errorMessage: String?
    var onImported: (LaunchItem) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var scope: LaunchItem.Scope = .userAgent
    @State private var inlineError: String?
    @State private var showOverwriteConfirm = false

    var body: some View {
        Form {
            Section("导入到") {
                Picker("Scope", selection: $scope) {
                    ForEach(LaunchItem.Scope.allCases, id: \.self) { s in
                        Text(s.sectionTitle).tag(s)
                    }
                }
                Text(sourceURL.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let inlineError {
                Section {
                    Text(inlineError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 400, minHeight: 180)
        .navigationTitle("导入 Plist")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("导入") { importPlist(overwrite: false) }
            }
        }
        .confirmationDialog(
            "文件已存在，是否覆盖？",
            isPresented: $showOverwriteConfirm,
            titleVisibility: .visible
        ) {
            Button("覆盖", role: .destructive) { importPlist(overwrite: true) }
            Button("取消", role: .cancel) {}
        }
    }

    private func importPlist(overwrite: Bool) {
        do {
            let item = try store.importPlist(from: sourceURL, scope: scope, overwrite: overwrite)
            onImported(item)
            dismiss()
        } catch PlistValidationError.invalidFormat(let message) {
            if message == String(localized: "文件已存在") {
                showOverwriteConfirm = true
            } else {
                inlineError = message
            }
        } catch {
            inlineError = error.localizedDescription
        }
    }
}
