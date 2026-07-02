import Foundation

/// High-confidence real service detection — only overrides when we're sure.
struct RealServiceResolver {
    private let commandLine = CommandLineResolver()
    private let projectFramework = ProjectFrameworkResolver()
    private let executable = ExecutableResolver()

    func resolve(process: ListeningProcess, context: ProjectContext) -> ClassificationHit? {
        if let hit = commandLine.resolve(command: process.command) { return hit }
        if let hit = projectFramework.resolve(workingDirectory: context.projectDirectory) { return hit }
        if let hit = executable.resolve(executable: process.executable) { return hit }
        return nil
    }
}
