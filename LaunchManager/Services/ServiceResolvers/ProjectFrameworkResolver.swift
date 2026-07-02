import Foundation

/// Detects framework from project marker files — high-confidence matches only.
struct ProjectFrameworkResolver {
    func resolve(workingDirectory: String?) -> ClassificationHit? {
        guard let workingDirectory else { return nil }
        let base = URL(fileURLWithPath: workingDirectory, isDirectory: true)
        guard FileManager.default.fileExists(atPath: base.path) else { return nil }

        if fileExists(in: base, names: ["next.config.js", "next.config.mjs", "next.config.ts"]) {
            return .init(displayName: "Next.js", category: .web, generatesURL: true, identityKind: .realService)
        }
        return nil
    }

    private func fileExists(in directory: URL, names: [String]) -> Bool {
        names.contains { FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path) }
    }
}
