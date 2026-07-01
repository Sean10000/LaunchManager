import AppKit
import SwiftUI

struct ServiceRowView: View {
    let service: Service
    @ObservedObject var store: ServiceStore
    @Binding var errorMessage: String?

    @State private var showingKillConfirm = false

    private var statusColor: Color {
        service.health == .healthy ? .green : .red
    }

    private var statusTooltip: String {
        "PID \(service.pid)"
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .help(statusTooltip)

            VStack(alignment: .leading, spacing: 2) {
                Text(service.displayName)
                    .lineLimit(1)
                if let subtitle = service.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(service.addressLabel)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            primaryActionButton

            Menu {
                Button("Open in Browser") {
                    if let url = service.url {
                        NSWorkspace.shared.open(url)
                    }
                }
                .disabled(service.url == nil)

                Button("Copy URL") {
                    if let url = service.url {
                        copyToPasteboard(url.absoluteString)
                    }
                }
                .disabled(service.url == nil)

                Button("Reveal in Finder") {
                    if let cwd = service.workingDirectory {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: cwd)
                    }
                }
                .disabled(service.workingDirectory == nil)

                Divider()

                Button("Kill Process…", role: .destructive) {
                    showingKillConfirm = true
                }
                .disabled(store.pendingKillIDs.contains(service.id))
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
        )
        .sheet(isPresented: $showingKillConfirm) {
            KillConfirmSheet(
                service: service,
                store: store,
                errorMessage: $errorMessage
            )
        }
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
            Button("Copy") {
                copyToPasteboard(service.addressLabel)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    private func copyToPasteboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
