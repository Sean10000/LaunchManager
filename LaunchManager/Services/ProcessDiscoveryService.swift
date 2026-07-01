import Foundation

struct LsofRow: Equatable {
    let pid: Int32
    let port: Int
    let executable: String
}

final class ProcessDiscoveryService: Sendable {
    private let shell: ShellRunner

    init(shell: ShellRunner = DefaultShellRunner()) {
        self.shell = shell
    }

    static func extractPort(from nameField: String) -> Int? {
        let trimmed = nameField.replacingOccurrences(of: " (LISTEN)", with: "")
        guard let colon = trimmed.lastIndex(of: ":") else { return nil }
        let portStr = String(trimmed[trimmed.index(after: colon)...])
        return Int(portStr)
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
