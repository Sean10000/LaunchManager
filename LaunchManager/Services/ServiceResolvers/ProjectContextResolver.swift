import Foundation

struct ProjectContext {
    let projectDirectory: String?
    let projectName: String?
    let processDirectory: String?
}

/// Resolves a meaningful project directory from cwd and/or command line paths.
struct ProjectContextResolver {
    private let projectName = ProjectResolver()
    private let framework = ProjectFrameworkResolver()

    private static let homePath = FileManager.default.homeDirectoryForCurrentUser.path

    func resolve(process: ListeningProcess) -> ProjectContext {
        let rawCwd = process.workingDirectory
        let processDirectory = rawCwd.flatMap { isTrivialPath($0) ? nil : $0 }

        if let cwd = rawCwd, let root = findProjectRoot(startingAt: cwd) {
            return ProjectContext(
                projectDirectory: root,
                projectName: projectName.resolve(workingDirectory: root),
                processDirectory: processDirectory
            )
        }

        for path in extractAbsolutePaths(from: process.command) {
            if let root = findProjectRoot(startingAt: path) {
                return ProjectContext(
                    projectDirectory: root,
                    projectName: projectName.resolve(workingDirectory: root),
                    processDirectory: processDirectory
                )
            }
        }

        return ProjectContext(projectDirectory: nil, projectName: nil, processDirectory: processDirectory)
    }

    func frameworkHint(for context: ProjectContext) -> ClassificationHit? {
        framework.resolve(workingDirectory: context.projectDirectory)
    }

    func findProjectRoot(startingAt path: String) -> String? {
        var url = URL(fileURLWithPath: path, isDirectory: true)
        if !url.hasDirectoryPath {
            url = url.deletingLastPathComponent()
        }

        for _ in 0..<12 {
            if hasProjectMarker(at: url) {
                return url.path
            }
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { break }
            url = parent
        }
        return nil
    }

    private func hasProjectMarker(at directory: URL) -> Bool {
        let names = ["package.json", "pyproject.toml", "Cargo.toml", "go.mod", "docker-compose.yml", "docker-compose.yaml"]
        return names.contains { FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path) }
    }

    private func isTrivialPath(_ path: String) -> Bool {
        let normalized = (path as NSString).standardizingPath
        if normalized == Self.homePath { return true }
        if normalized == "/" { return true }
        if normalized.hasPrefix("/var/") || normalized.hasPrefix("/System/") { return true }
        if normalized == "/private/var/root" { return true }
        return false
    }

    private func extractAbsolutePaths(from command: String) -> [String] {
        let pattern = #"(/[^\s'\"]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(command.startIndex..., in: command)
        return regex.matches(in: command, range: range).compactMap { match in
            guard let r = Range(match.range(at: 1), in: command) else { return nil }
            var path = String(command[r])
            while path.hasSuffix("/") { path.removeLast() }
            return path.isEmpty ? nil : path
        }
    }
}
