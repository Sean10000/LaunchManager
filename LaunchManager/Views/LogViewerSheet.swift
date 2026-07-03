import SwiftUI

struct LogViewerSheet: View {
    let item: LaunchItem
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab = 0
    @State private var fileLogLines: [String] = []
    @State private var systemLogLines: [String] = []
    @State private var filterText = ""
    @State private var isLoadingSystem = false
    @State private var systemLogLoaded = false
    @State private var systemLogTruncated = false

    private static let maxFileBytes = 512 * 1024
    private static let maxSystemLines = 2_000
    private static let systemLogWindow = "15m"

    private var filteredSystemLines: [String] {
        guard !filterText.isEmpty else { return systemLogLines }
        return systemLogLines.filter { $0.localizedCaseInsensitiveContains(filterText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("文件日志").tag(0)
                Text("系统日志").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()
            .onChange(of: selectedTab) { _, tab in
                if tab == 1, !systemLogLoaded { loadSystemLog() }
            }

            Divider()

            if selectedTab == 0 { fileLogTab } else { systemLogTab }
        }
        .frame(minWidth: 620, minHeight: 420)
        .navigationTitle(String(localized: "日志 — \(item.label)"))
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("关闭") { dismiss() }
            }
        }
        .onAppear { loadFileLog() }
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
                logLinesView(fileLogLines, emptyMessage: "（日志为空）")
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
            if systemLogTruncated {
                Text(String(localized: "仅显示最近 \(Self.maxSystemLines) 行（最近 \(Self.systemLogWindow)）"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            }
            Divider()
            logLinesView(filteredSystemLines, emptyMessage: systemLogLoaded ? String(localized: "（无日志）") : String(localized: "点击刷新加载系统日志"))
        }
        .onAppear {
            if !systemLogLoaded { loadSystemLog() }
        }
    }

    @ViewBuilder
    private func logLinesView(_ lines: [String], emptyMessage: String) -> some View {
        if lines.isEmpty {
            ContentUnavailableView(emptyMessage, systemImage: "doc.text")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
            }
        }
    }

    private func loadFileLog() {
        var lines: [String] = []
        if let path = item.standardOutPath {
            lines.append("=== stdout (\(path)) ===")
            lines.append(contentsOf: tailLines(of: path))
        }
        if let path = item.standardErrorPath {
            lines.append("=== stderr (\(path)) ===")
            lines.append(contentsOf: tailLines(of: path))
        }
        fileLogLines = lines
    }

    private func tailLines(of path: String) -> [String] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: [.mappedIfSafe]),
              !data.isEmpty else { return [] }
        let slice = data.count > Self.maxFileBytes ? data.suffix(Self.maxFileBytes) : data
        let text = String(decoding: slice, as: UTF8.self)
        var result = text.components(separatedBy: "\n")
        if data.count > Self.maxFileBytes {
            result.insert(String(localized: "…（仅显示文件末尾 \(Self.maxFileBytes / 1024) KB）"), at: 0)
        }
        return result
    }

    private func loadSystemLog() {
        isLoadingSystem = true
        let label = item.label
        Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
            process.arguments = [
                "show",
                "--predicate",
                "subsystem == \"\(label)\" OR process == \"\(label)\"",
                "--last", Self.systemLogWindow,
                "--style", "compact"
            ]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            var lines: [String] = []
            var truncated = false
            do {
                try process.run()
                for try await line in pipe.fileHandleForReading.bytes.lines {
                    lines.append(line)
                    if lines.count > Self.maxSystemLines {
                        truncated = true
                        process.terminate()
                        break
                    }
                }
                process.waitUntilExit()
            } catch {
                lines = [String(localized: "读取系统日志失败：\(error.localizedDescription)")]
            }
            if truncated {
                lines = Array(lines.prefix(Self.maxSystemLines))
            }
            await MainActor.run {
                systemLogLines = lines
                systemLogTruncated = truncated
                systemLogLoaded = true
                isLoadingSystem = false
            }
        }
    }

    private func clearFileLog() {
        if let path = item.standardOutPath {
            try? "".write(toFile: path, atomically: true, encoding: .utf8)
        }
        if let path = item.standardErrorPath {
            try? "".write(toFile: path, atomically: true, encoding: .utf8)
        }
        loadFileLog()
    }
}
