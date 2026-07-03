import Darwin
import Foundation

protocol ProcessScanning: Sendable {
    func scan() throws -> [ListeningProcess]
}

struct LsofRow: Equatable {
    let pid: Int32
    let port: Int
    let executable: String
}

final class ProcessDiscoveryService: Sendable {
    private let shell: ShellRunner
    private let isAlive: @Sendable (Int32) -> Bool

    init(
        shell: ShellRunner = DefaultShellRunner(),
        isAlive: @escaping @Sendable (Int32) -> Bool = ProcessDiscoveryService.isProcessAlive
    ) {
        self.shell = shell
        self.isAlive = isAlive
    }

    static func extractPort(from nameField: String) -> Int? {
        let trimmed = nameField.replacingOccurrences(of: " (LISTEN)", with: "")
        guard let colon = trimmed.lastIndex(of: ":") else { return nil }
        let portStr = String(trimmed[trimmed.index(after: colon)...])
        return Int(portStr)
    }

    /// lsof COMMAND column is truncated (~8 chars); derive full name from ps output.
    static func executableName(from command: String) -> String? {
        var trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.first == "\"" {
            trimmed.removeFirst()
            if let end = trimmed.firstIndex(of: "\"") {
                let path = String(trimmed[..<end])
                let name = (path as NSString).lastPathComponent
                return name.isEmpty ? nil : name
            }
        }

        let first = trimmed.split(separator: " ", maxSplits: 1).first.map(String.init) ?? trimmed
        let name = (first as NSString).lastPathComponent
        return name.isEmpty ? nil : name
    }

    func parseLsofOutput(_ output: String) -> [LsofRow] {
        var rows: [LsofRow] = []
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let s = String(line)
            if s.hasPrefix("COMMAND") { continue }
            let parts = s.split(whereSeparator: { $0.isWhitespace })
            guard parts.count >= 9 else { continue }
            guard let pid = Int32(parts[1]) else { continue }
            let executable = String(parts[0])
            let nameField = parts[8...].joined(separator: " ")
            guard nameField.contains("(LISTEN)") else { continue }
            guard let port = Self.extractPort(from: nameField) else { continue }
            rows.append(LsofRow(pid: pid, port: port, executable: executable))
        }
        return rows
    }
}

extension ProcessDiscoveryService: ProcessScanning {
    static func isProcessAlive(pid: Int32) -> Bool {
        if kill(pid, 0) == 0 { return true }
        // EPERM means the process exists but we cannot signal it (e.g. owned by root).
        return errno == EPERM
    }

    func scan() throws -> [ListeningProcess] {
        let lsofOut = try shell.run("/usr/sbin/lsof", arguments: [
            "-iTCP", "-sTCP:LISTEN", "-nP"
        ])
        let rows = parseLsofOutput(lsofOut)
        var seen = Set<String>()
        var result: [ListeningProcess] = []

        for row in rows {
            let key = "\(row.pid)-\(row.port)"
            guard seen.insert(key).inserted else { continue }
            guard isAlive(row.pid) else { continue }

            let command = resolveCommand(pid: row.pid, shell: shell, fallbackExecutable: row.executable)

            let executable: String = {
                if let path = ProcessPathResolver.executablePath(for: row.pid) {
                    return (path as NSString).lastPathComponent
                }
                return Self.executableName(from: command) ?? row.executable
            }()

            let cwd = ProcessPathResolver.currentWorkingDirectory(for: row.pid)
                ?? cwdFromLsof(shell: shell, pid: row.pid)

            result.append(ListeningProcess(
                pid: row.pid,
                port: row.port,
                protocolName: "tcp",
                command: command,
                executable: executable,
                workingDirectory: cwd
            ))
        }
        return result.sorted { $0.port < $1.port }
    }

    private func cwdFromLsof(shell: ShellRunner, pid: Int32) -> String? {
        let cwdOut = (try? shell.run("/usr/sbin/lsof", arguments: [
            "-a", "-p", "\(pid)", "-d", "cwd", "-Fn"
        ])) ?? ""
        guard let raw = cwdOut.split(separator: "\n")
            .first(where: { $0.hasPrefix("n") })
            .map({ String($0.dropFirst()) }) else { return nil }
        return FilePathNormalizer.display(raw)
    }

    func resolveCommand(pid: Int32, shell: ShellRunner, fallbackExecutable: String) -> String {
        if let kernel = ProcessCommandLineResolver.commandLine(for: pid) {
            return FilePathNormalizer.display(kernel)
        }
        let raw = (try? shell.run("/bin/ps", arguments: ["-p", "\(pid)", "-o", "command="]))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? fallbackExecutable
        return FilePathNormalizer.display(raw)
    }
}
