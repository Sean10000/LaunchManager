import Foundation

struct ServiceClassifier {
    private let executable = ExecutableResolver()
    private let commandLine = CommandLineResolver()
    private let project = ProjectResolver()

    func classify(_ process: ListeningProcess) -> Service {
        let cmdHit = commandLine.resolve(command: process.command)
        let exeHit = executable.resolve(executable: process.executable)
        let hit = cmdHit ?? exeHit

        let displayName = hit?.displayName ?? process.executable
        let category = hit?.category ?? .other
        let subtitle = process.workingDirectory.flatMap { project.resolve(workingDirectory: $0) }
        let url: URL? = (hit?.generatesURL == true)
            ? URL(string: "http://localhost:\(process.port)")
            : nil
        let health: ServiceHealth = ProcessDiscoveryService.isProcessAlive(pid: process.pid)
            ? .healthy : .down

        return Service(
            displayName: displayName,
            subtitle: subtitle,
            category: category,
            health: health,
            port: process.port,
            host: "localhost",
            pid: process.pid,
            executable: process.executable,
            command: process.command,
            workingDirectory: process.workingDirectory,
            url: url
        )
    }

    func classifyAll(_ processes: [ListeningProcess]) -> [Service] {
        processes.map(classify)
    }
}
