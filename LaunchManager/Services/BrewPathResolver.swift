import Foundation

enum BrewPathResolver {
    static let candidatePaths = [
        "/opt/homebrew/bin/brew",
        "/usr/local/bin/brew",
    ]

    static func resolve(using shell: ShellRunner = DefaultShellRunner()) -> String? {
        for path in candidatePaths where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        if let output = try? shell.run("/usr/bin/which", arguments: ["brew"]).trimmingCharacters(in: .whitespacesAndNewlines),
           !output.isEmpty,
           FileManager.default.isExecutableFile(atPath: output) {
            return output
        }
        return nil
    }
}
