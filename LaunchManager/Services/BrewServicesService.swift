import Foundation

struct BrewServicesService {
    private let shell: ShellRunner
    private let privilege: PrivilegeService
    private let brewPath: String?
    private let systemDaemonDirectory: String

    init(
        shell: ShellRunner = DefaultShellRunner(),
        privilege: PrivilegeService = PrivilegeService(),
        brewPath: String? = BrewPathResolver.resolve(),
        systemDaemonDirectory: String = "/Library/LaunchDaemons"
    ) {
        self.shell = shell
        self.privilege = privilege
        self.brewPath = brewPath
        self.systemDaemonDirectory = systemDaemonDirectory
    }

    var isBrewAvailable: Bool { brewPath != nil }

    func listServices(scope: HomebrewServiceScope) throws -> [HomebrewService] {
        guard let brewPath else { return [] }
        switch scope {
        case .user:
            return try listUserServices(brewPath: brewPath)
        case .root:
            return try listRootServices(brewPath: brewPath)
        }
    }

    func start(_ name: String, scope: HomebrewServiceScope) throws {
        try runBrew(["services", "start", name], scope: scope)
    }

    func stop(_ name: String, scope: HomebrewServiceScope) throws {
        try runBrew(["services", "stop", name], scope: scope)
    }

    func restart(_ name: String, scope: HomebrewServiceScope) throws {
        try runBrew(["services", "restart", name], scope: scope)
    }

    // MARK: - Private

    private struct BrewServiceRecord: Decodable {
        let name: String
        let status: String
        let user: String?
        let file: String?
        let exit_code: Int?
    }

    private func listUserServices(brewPath: String) throws -> [HomebrewService] {
        let output = try shell.run(brewPath, arguments: ["services", "list", "--json"])
        return try decodeServices(from: output, scope: .user)
    }

    private func listRootServices(brewPath: String) throws -> [HomebrewService] {
        let output = try shell.run(brewPath, arguments: ["services", "list", "--json"])
        let installed = try decodeServices(from: output, scope: .user)
        return installed.map { service in
            let daemonPath = "\(systemDaemonDirectory)/\(service.label).plist"
            let hasDaemon = FileManager.default.fileExists(atPath: daemonPath)
            let status = hasDaemon ? statusForSystemLabel(service.label) : .none
            return HomebrewService(
                name: service.name,
                scope: .root,
                status: status,
                runAsUser: "root",
                plistPath: hasDaemon ? daemonPath : service.plistPath,
                exitCode: service.exitCode
            )
        }
    }

    private func decodeServices(from output: String, scope: HomebrewServiceScope) throws -> [HomebrewService] {
        let records = try JSONDecoder().decode([BrewServiceRecord].self, from: Data(output.utf8))
        return records.map {
            HomebrewService(
                name: $0.name,
                scope: scope,
                status: HomebrewServiceStatus(brewStatus: $0.status),
                runAsUser: $0.user,
                plistPath: $0.file,
                exitCode: $0.exit_code
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func statusForSystemLabel(_ label: String) -> HomebrewServiceStatus {
        guard let output = try? shell.run("/bin/launchctl", arguments: ["print", "system/\(label)"]) else {
            return .none
        }
        if output.contains("Could not find service") {
            return .none
        }
        if output.contains("state = running") {
            return .started
        }
        if output.contains("state = not running") {
            return .stopped
        }
        return .unknown
    }

    private func runBrew(_ arguments: [String], scope: HomebrewServiceScope) throws {
        guard let brewPath else {
            throw BrewServicesError.brewNotFound
        }
        let command = ([brewPath] + arguments).map(shellQuote).joined(separator: " ")
        if scope.requiresPrivilege {
            try privilege.run(command)
        } else {
            _ = try shell.run(brewPath, arguments: arguments)
        }
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

enum BrewServicesError: LocalizedError {
    case brewNotFound

    var errorDescription: String? {
        switch self {
        case .brewNotFound:
            return String(localized: "未找到 Homebrew。请先安装 Homebrew 或确认 brew 在 PATH 中。")
        }
    }
}
