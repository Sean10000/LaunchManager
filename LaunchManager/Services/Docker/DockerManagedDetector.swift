import Foundation

enum DockerManagedDetector {
    private static let pathHints = [
        ".colima", "/colima/", "com.docker", "docker-desktop",
        "/docker/", ".lima/", "lima-docker", "vpnkit",
    ]

    static func isDockerManaged(_ process: ListeningProcess) -> Bool {
        let exe = (process.executable as NSString).lastPathComponent.lowercased()
        if exe == "docker-proxy" || exe == "vpnkit" || exe == "com.docker.backend" {
            return true
        }

        let cmd = process.command.lowercased()
        if cmd.contains("docker-proxy") || cmd.contains("com.docker") {
            return true
        }

        for hint in pathHints {
            if cmd.contains(hint) { return true }
            if let cwd = process.workingDirectory?.lowercased(), cwd.contains(hint) {
                return true
            }
        }
        return false
    }
}
