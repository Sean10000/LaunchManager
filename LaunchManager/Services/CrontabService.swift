import Foundation

struct CrontabService {
    static let systemCrontabPath = "/etc/crontab"

    private let shell: ShellRunner
    private let privilege: PrivilegeService
    var systemCrontabURL: URL

    init(
        shell: ShellRunner = DefaultShellRunner(),
        privilege: PrivilegeService = PrivilegeService(),
        systemCrontabURL: URL = URL(fileURLWithPath: systemCrontabPath)
    ) {
        self.shell = shell
        self.privilege = privilege
        self.systemCrontabURL = systemCrontabURL
    }

    func readUserCrontab() throws -> String {
        do {
            return try shell.run("/usr/bin/crontab", arguments: ["-l"])
        } catch ShellError.nonZeroExit(let code, let output) {
            if code == 1 && output.localizedCaseInsensitiveContains("no crontab") {
                return ""
            }
            throw ShellError.nonZeroExit(code: code, output: output)
        }
    }

    func readSystemCrontab() throws -> String {
        guard FileManager.default.fileExists(atPath: systemCrontabURL.path) else {
            return ""
        }
        return try String(contentsOf: systemCrontabURL, encoding: .utf8) ?? ""
    }

    func writeUserCrontab(_ content: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/crontab")
        process.arguments = ["-"]

        let stdinPipe = Pipe()
        let errPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardError = errPipe
        process.standardOutput = FileHandle.nullDevice

        try process.run()

        let data = Data(content.utf8)
        try stdinPipe.fileHandleForWriting.write(contentsOf: data)
        try stdinPipe.fileHandleForWriting.close()

        process.waitUntilExit()

        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let err = String(data: errData, encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            throw ShellError.nonZeroExit(code: process.terminationStatus, output: err)
        }
    }

    func writeSystemCrontab(_ content: String, privilege: PrivilegeService? = nil) throws {
        let auth = privilege ?? self.privilege
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("launchmanager-crontab-\(UUID().uuidString)")
        try content.write(to: tmp, atomically: true, encoding: .utf8)
        let dest = shellQuote(systemCrontabURL.path)
        let src = shellQuote(tmp.path)
        try auth.run("mv \(src) \(dest) && chown root:wheel \(dest) && chmod 644 \(dest)")
    }

    func parseCrontab(scope: CrontabScope) throws -> [CrontabLine] {
        let text: String
        switch scope {
        case .user:
            text = try readUserCrontab()
        case .system:
            text = try readSystemCrontab()
        }
        return CrontabParser.parse(text, format: scope.parserFormat)
    }

    func saveCrontab(lines: [CrontabLine], scope: CrontabScope, privilege: PrivilegeService? = nil) throws {
        var content = CrontabParser.serialize(lines, format: scope.parserFormat)
        if scope == .system {
            if content.isEmpty {
                content = CrontabParser.defaultSystemHeader + "\n"
            } else if !FileManager.default.fileExists(atPath: systemCrontabURL.path),
                      !content.contains("# /etc/crontab") {
                content = CrontabParser.defaultSystemHeader + "\n\n" + content
            }
        }

        switch scope {
        case .user:
            try writeUserCrontab(content)
        case .system:
            try writeSystemCrontab(content, privilege: privilege)
        }
    }

    // MARK: - Private

    private func shellQuote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
