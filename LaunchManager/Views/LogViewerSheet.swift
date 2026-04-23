import SwiftUI

struct LogViewerSheet: View {
    let item: LaunchItem
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab      = 0
    @State private var fileLogContent   = ""
    @State private var systemLogContent = ""
    @State private var filterText       = ""
    @State private var isLoadingSystem  = false

    var filteredSystemLog: String {
        guard !filterText.isEmpty else { return systemLogContent }
        return systemLogContent
            .components(separatedBy: "\n")
            .filter { $0.localizedCaseInsensitiveContains(filterText) }
            .joined(separator: "\n")
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("文件日志").tag(0)
                Text("系统日志").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()

            Divider()

            if selectedTab == 0 { fileLogTab } else { systemLogTab }
        }
        .frame(minWidth: 620, minHeight: 420)
        .navigationTitle("日志 — \(item.label)")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("关闭") { dismiss() }
            }
        }
        .onAppear {
            loadFileLog()
            loadSystemLog()
        }
    }

    @ViewBuilder
    private var fileLogTab: some View {
        if item.standardOutPath == nil && item.standardErrorPath == nil {
            ContentUnavailableView(
                "未配置日志文件路径",
                systemImage: "doc.text.slash",
                description: Text("在编辑 Agent 时填写 StandardOutPath / StandardErrorPath 即可启用。")
            )
        } else {
            VStack(spacing: 0) {
                ScrollView {
                    Text(fileLogContent.isEmpty ? "（日志为空）" : fileLogContent)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                Divider()
                HStack {
                    Spacer()
                    Button("清空日志") { clearFileLog() }.padding(8)
                }
            }
        }
    }

    @ViewBuilder
    private var systemLogTab: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("过滤关键字", text: $filterText).textFieldStyle(.roundedBorder)
                if isLoadingSystem { ProgressView().scaleEffect(0.7) }
                Button { loadSystemLog() } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .padding(.horizontal).padding(.vertical, 6)
            Divider()
            ScrollView {
                Text(filteredSystemLog.isEmpty ? "（无日志）" : filteredSystemLog)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
    }

    private func loadFileLog() {
        var content = ""
        if let path = item.standardOutPath,
           let text = try? String(contentsOfFile: path) {
            content += "=== stdout (\(path)) ===\n\(text)\n"
        }
        if let path = item.standardErrorPath,
           let text = try? String(contentsOfFile: path) {
            content += "=== stderr (\(path)) ===\n\(text)\n"
        }
        fileLogContent = content
    }

    private func loadSystemLog() {
        isLoadingSystem = true
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
            process.arguments = [
                "show",
                "--predicate",
                "subsystem == \"\(item.label)\" OR process == \"\(item.label)\"",
                "--last", "1h",
                "--style", "compact"
            ]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError  = pipe
            try? process.run()
            process.waitUntilExit()
            let output = String(
                data: pipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                self.systemLogContent = output
                self.isLoadingSystem  = false
            }
        }
    }

    private func clearFileLog() {
        if let path = item.standardOutPath  {
            try? "".write(toFile: path, atomically: true, encoding: .utf8)
        }
        if let path = item.standardErrorPath {
            try? "".write(toFile: path, atomically: true, encoding: .utf8)
        }
        loadFileLog()
    }
}
