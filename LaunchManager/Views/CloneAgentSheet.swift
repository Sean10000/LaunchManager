import SwiftUI

struct CloneAgentSheet: View {
    let item: LaunchItem
    @ObservedObject var store: AgentStore
    @Binding var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    @State private var newLabel: String
    @State private var scope: LaunchItem.Scope
    @State private var inlineError: String?

    init(item: LaunchItem, store: AgentStore, errorMessage: Binding<String?>) {
        self.item = item
        self.store = store
        _errorMessage = errorMessage
        _newLabel = State(initialValue: "\(item.label).copy")
        _scope = State(initialValue: item.scope)
    }

    var body: some View {
        Form {
            Section("新 Job") {
                TextField("Label", text: $newLabel)
                    .textFieldStyle(.roundedBorder)
                Picker("Scope", selection: $scope) {
                    ForEach(LaunchItem.Scope.allCases, id: \.self) { s in
                        Text(s.sectionTitle).tag(s)
                    }
                }
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
        .frame(minWidth: 400, minHeight: 200)
        .navigationTitle("复制 Agent")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("创建") { clone() }
                    .disabled(newLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func clone() {
        let trimmed = newLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try store.cloneItem(item, newLabel: trimmed, scope: scope)
            dismiss()
        } catch {
            inlineError = error.localizedDescription
        }
    }
}
