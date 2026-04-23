import Foundation

struct LaunchctlService {
    var shell: ShellRunner
    var privilege: PrivilegeService

    init(shell: ShellRunner = DefaultShellRunner(),
         privilege: PrivilegeService = PrivilegeService()) {
        self.shell = shell
        self.privilege = privilege
    }

    // MARK: - List

    func listAll() throws -> [String: (pid: Int?, exitCode: Int?)] {
        let output = try shell.run("/bin/launchctl", arguments: ["list"])
        return parseListOutput(output)
    }

    func parseListOutput(_ output: String) -> [String: (pid: Int?, exitCode: Int?)] {
        var result: [String: (pid: Int?, exitCode: Int?)] = [:]
        let lines = output.components(separatedBy: "\n").dropFirst()
        for line in lines {
            let cols = line.components(separatedBy: "\t")
            guard cols.count == 3 else { continue }
            let pidStr  = cols[0].trimmingCharacters(in: .whitespaces)
            let codeStr = cols[1].trimmingCharacters(in: .whitespaces)
            let label   = cols[2].trimmingCharacters(in: .whitespaces)
            guard !label.isEmpty else { continue }
            result[label] = (pid: pidStr == "-" ? nil : Int(pidStr),
                             exitCode: Int(codeStr))
        }
        return result
    }

    // MARK: - Load / Unload (bootstrap / bootout)

    func load(_ url: URL, scope: LaunchItem.Scope) throws {
        let domain = launchdDomain(for: scope)
        if scope.requiresPrivilege {
            try privilege.run("/bin/launchctl bootstrap \(domain) \(url.path)")
        } else {
            _ = try shell.run("/bin/launchctl", arguments: ["bootstrap", domain, url.path])
        }
    }

    func unload(_ url: URL, scope: LaunchItem.Scope) throws {
        let domain = launchdDomain(for: scope)
        if scope.requiresPrivilege {
            try privilege.run("/bin/launchctl bootout \(domain) \(url.path)")
        } else {
            _ = try shell.run("/bin/launchctl", arguments: ["bootout", domain, url.path])
        }
    }

    // MARK: - Start / Stop (kickstart / kill)

    func start(_ label: String, scope: LaunchItem.Scope) throws {
        let target = "\(launchdDomain(for: scope))/\(label)"
        if scope.requiresPrivilege {
            try privilege.run("/bin/launchctl kickstart \(target)")
        } else {
            _ = try shell.run("/bin/launchctl", arguments: ["kickstart", target])
        }
    }

    func stop(_ label: String, scope: LaunchItem.Scope) throws {
        let target = "\(launchdDomain(for: scope))/\(label)"
        // kill returns non-zero when process isn't running — treat as success
        if scope.requiresPrivilege {
            try? privilege.run("/bin/launchctl kill SIGTERM \(target)")
        } else {
            _ = try? shell.run("/bin/launchctl", arguments: ["kill", "SIGTERM", target])
        }
    }

    // MARK: - Helpers

    private func launchdDomain(for scope: LaunchItem.Scope) -> String {
        switch scope {
        case .systemDaemon:         return "system"
        case .userAgent, .systemAgent: return "gui/\(getuid())"
        }
    }
}
