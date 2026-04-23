import SwiftUI

struct InvalidPlistRowView: View {
    let item: InvalidPlist
    @ObservedObject var store: AgentStore
    @Binding var errorMessage: String?

    @State private var isExpanded = false
    @State private var showingDeleteConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(nsColor: .tertiaryLabelColor))
                    .frame(width: 8, height: 8)
                Text(item.url.lastPathComponent)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text("⚠️ 无法解析")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if isExpanded {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 8) {
                        Text("路径")
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .leading)
                        Text(item.url.path)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .font(.caption)
                    Text("此文件为空或格式无效，无法作为 launchd 条目加载。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
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
            "确认删除 \(item.url.lastPathComponent)？",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                do { try store.deleteInvalid(item) }
                catch { errorMessage = error.localizedDescription }
            }
        } message: {
            Text("此操作将永久删除该 plist 文件，无法撤销。")
        }
    }
}
