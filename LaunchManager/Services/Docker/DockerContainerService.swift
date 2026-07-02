import Foundation

enum DockerCLIError: LocalizedError {
    case notFound

    var errorDescription: String? {
        switch self {
        case .notFound: return "未找到 docker 可执行文件"
        }
    }
}

struct DockerCLI: Sendable {
    private enum LaunchMethod: Sendable {
        case direct(path: String)
        case env
    }

    /// Checked first — GUI apps often have a minimal PATH.
    static func allCandidatePaths(fileManager: FileManager = .default) -> [String] {
        let home = fileManager.homeDirectoryForCurrentUser.path
        return [
            "/usr/local/bin/docker",
            "/opt/homebrew/bin/docker",
            "/Applications/Docker.app/Contents/Resources/bin/docker",
            "\(home)/.docker/bin/docker",
            "/usr/bin/docker",
        ]
    }

    private let shell: ShellRunner
    private let launchMethod: LaunchMethod

    init(shell: ShellRunner = DefaultShellRunner()) throws {
        guard let method = Self.resolveLaunchMethod(shell: shell) else {
            throw DockerCLIError.notFound
        }
        self.shell = shell
        self.launchMethod = method
    }

    init?(optional shell: ShellRunner = DefaultShellRunner()) {
        guard let method = Self.resolveLaunchMethod(shell: shell) else { return nil }
        self.shell = shell
        self.launchMethod = method
    }

    /// Absolute path when known; `"docker"` when resolved via PATH fallback.
    var resolvedPath: String {
        switch launchMethod {
        case .direct(let path): return path
        case .env: return "docker"
        }
    }

    func run(_ arguments: [String]) throws -> String {
        switch launchMethod {
        case .direct(let path):
            return try shell.run(path, arguments: arguments)
        case .env:
            return try Self.runViaEnv(arguments: arguments)
        }
    }

    static func resolveExecutable(fileManager: FileManager = .default) -> String? {
        for path in allCandidatePaths(fileManager: fileManager) where fileManager.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    private static func resolveLaunchMethod(
        fileManager: FileManager = .default,
        shell: ShellRunner = DefaultShellRunner()
    ) -> LaunchMethod? {
        if let path = resolveExecutable(fileManager: fileManager) {
            return .direct(path: path)
        }
        if probeEnvDocker() {
            return .env
        }
        return nil
    }

    /// Prepends common install dirs to the current PATH for `/usr/bin/env docker`.
    static func augmentedPATH(existing: String?) -> String {
        let extras = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/Applications/Docker.app/Contents/Resources/bin",
            FileManager.default.homeDirectoryForCurrentUser.path + "/.docker/bin",
        ]
        let base = existing?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = "/usr/bin:/bin:/usr/sbin:/sbin"
        let current = (base?.isEmpty == false) ? base! : fallback
        return extras.joined(separator: ":") + ":" + current
    }

    private static func probeEnvDocker() -> Bool {
        (try? runViaEnv(arguments: ["--version"])) != nil
    }

    private static func runViaEnv(arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["docker"] + arguments

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = augmentedPATH(existing: env["PATH"])
        process.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()

        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw ShellError.nonZeroExit(code: process.terminationStatus, output: err.isEmpty ? out : err)
        }
        return out
    }
}

struct DockerContainerIndex: Sendable {
    private let byHostPort: [Int: DockerContainerInfo]

    init(containers: [DockerContainerInfo]) {
        var map: [Int: DockerContainerInfo] = [:]
        for container in containers {
            for port in container.publishedHostPorts {
                map[port] = container
            }
        }
        byHostPort = map
    }

    func container(forHostPort port: Int) -> DockerContainerInfo? {
        byHostPort[port]
    }

    static func load(shell: ShellRunner = DefaultShellRunner()) -> DockerContainerIndex {
        guard let cli = DockerCLI(optional: shell) else {
            return DockerContainerIndex(containers: [])
        }
        guard let output = try? cli.run([
            "ps", "--no-trunc",
            "--format", "{{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Ports}}\t{{.Label \"com.docker.compose.service\"}}\t{{.Label \"com.docker.compose.project\"}}",
        ]) else {
            return DockerContainerIndex(containers: [])
        }
        return DockerContainerIndex(containers: parseListing(output))
    }

    static func parseListing(_ output: String) -> [DockerContainerInfo] {
        output.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            parseLine(String(line))
        }
    }

    static func parseLine(_ line: String) -> DockerContainerInfo? {
        let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 4 else { return nil }
        let id = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return nil }

        let namesField = parts[1]
        let name = namesField.split(separator: ",").first.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? namesField
        guard !name.isEmpty else { return nil }

        let image = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
        let portsField = parts[3]
        let composeService = parts.count > 4 ? nilIfEmpty(parts[4]) : nil
        let composeProject = parts.count > 5 ? nilIfEmpty(parts[5]) : nil
        let hostPorts = parseHostPorts(from: portsField)

        return DockerContainerInfo(
            id: id,
            name: name,
            image: image,
            composeProject: composeProject,
            composeService: composeService,
            publishedHostPorts: hostPorts
        )
    }

    static func parseHostPorts(from portsField: String) -> [Int] {
        guard !portsField.isEmpty else { return [] }
        var ports: [Int] = []
        let pattern = #":(\d+)->"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(portsField.startIndex..., in: portsField)
        for match in regex.matches(in: portsField, range: range) {
            guard match.numberOfRanges > 1,
                  let r = Range(match.range(at: 1), in: portsField),
                  let port = Int(portsField[r]) else { continue }
            ports.append(port)
        }
        return ports
    }

    private static func nilIfEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct DockerContainerService: Sendable {
    private let cli: DockerCLI?

    init(shell: ShellRunner = DefaultShellRunner()) {
        self.cli = DockerCLI(optional: shell)
    }

    func stopContainer(reference: String, timeoutSeconds: Int = 10) async throws {
        guard let cli else { throw DockerCLIError.notFound }
        _ = try await Task.detached {
            try cli.run(["stop", "-t", "\(timeoutSeconds)", reference])
        }.value
    }
}
