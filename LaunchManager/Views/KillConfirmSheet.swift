import SwiftUI

struct KillConfirmSheet: View {
    let service: Service
    @ObservedObject var store: ServiceStore
    @Binding var errorMessage: String?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("确认终止服务？")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text(service.displayName)
                Text(service.addressLabel)
                    .font(.system(.body, design: .monospaced))
                Text("PID \(service.pid)")
                    .foregroundStyle(.secondary)
                if let cwd = service.workingDirectory {
                    Text(cwd)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("终止进程", role: .destructive) {
                    store.kill(service) { errorMessage = $0 }
                    dismiss()
                }
                .disabled(store.pendingKillIDs.contains(service.id))
            }
        }
        .padding(24)
        .frame(minWidth: 360)
    }
}
