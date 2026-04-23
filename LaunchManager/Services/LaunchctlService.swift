import Foundation

struct LaunchctlService {
    var shell: ShellRunner
    var privilege: PrivilegeService

    init(shell: ShellRunner = DefaultShellRunner(),
         privilege: PrivilegeService = PrivilegeService()) {
        self.shell = shell
        self.privilege = privilege
    }

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

    func load(_ url: URL, privileged: Bool) throws {
        if privileged {
            try privilege.run("/bin/launchctl load \(url.path)")
        } else {
            _ = try shell.run("/bin/launchctl", arguments: ["load", url.path])
        }
    }

    func unload(_ url: URL, privileged: Bool) throws {
        if privileged {
            try privilege.run("/bin/launchctl unload \(url.path)")
        } else {
            _ = try shell.run("/bin/launchctl", arguments: ["unload", url.path])
        }
    }

    func start(_ label: String, privileged: Bool) throws {
        if privileged {
            try privilege.run("/bin/launchctl start \(label)")
        } else {
            _ = try shell.run("/bin/launchctl", arguments: ["start", label])
        }
    }

    func stop(_ label: String, privileged: Bool) throws {
        if privileged {
            try privilege.run("/bin/launchctl stop \(label)")
        } else {
            _ = try shell.run("/bin/launchctl", arguments: ["stop", label])
        }
    }
}
