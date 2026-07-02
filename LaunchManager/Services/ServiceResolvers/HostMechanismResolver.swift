import Foundation

/// Detects port-forwarding / VM / system hosting layers — not the app behind them.
struct HostMechanismResolver {
    func resolve(process: ListeningProcess) -> ClassificationHit? {
        let exe = (process.executable as NSString).lastPathComponent.lowercased()
        let cmd = process.command.lowercased()

        if cmd.contains(".colima") || exe == "colima" || cmd.contains("/colima/") {
            return .init(
                displayName: "Colima",
                category: .hostMechanism,
                generatesURL: false,
                identityKind: .hostMechanism
            )
        }

        if exe == "docker-proxy" || cmd.contains("docker-proxy") {
            return .init(
                displayName: "Docker 端口转发",
                category: .hostMechanism,
                generatesURL: false,
                identityKind: .hostMechanism
            )
        }

        if exe == "launchd" || cmd.hasPrefix("/sbin/launchd") || cmd.hasPrefix("/usr/libexec/launchd") {
            return .init(
                displayName: "系统服务 (launchd)",
                category: .hostMechanism,
                generatesURL: false,
                identityKind: .hostMechanism
            )
        }

        if exe == "ssh", hasSSHPortForward(in: process.command) {
            return .init(
                displayName: "SSH 端口转发",
                category: .hostMechanism,
                generatesURL: false,
                identityKind: .hostMechanism
            )
        }

        if exe == "limactl" || cmd.contains(".lima/") {
            return .init(
                displayName: "Lima VM",
                category: .hostMechanism,
                generatesURL: false,
                identityKind: .hostMechanism
            )
        }

        return nil
    }

    private func hasSSHPortForward(in command: String) -> Bool {
        command.range(of: #"-[LR]\s"#, options: .regularExpression) != nil
            || command.range(of: #"-[LR]\d"#, options: .regularExpression) != nil
    }
}
