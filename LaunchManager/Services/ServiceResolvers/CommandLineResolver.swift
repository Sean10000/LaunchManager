import Foundation

struct CommandLineResolver {
    private struct Rule {
        let patterns: [String]
        let hit: ClassificationHit
    }

    private static let rules: [Rule] = [
        Rule(
            patterns: ["next dev", "next start", "next-server", "/next ", "/.bin/next", "node_modules/next"],
            hit: ClassificationHit(displayName: "Next.js", category: .web, generatesURL: true, identityKind: .realService)
        ),
    ]

    func resolve(command: String) -> ClassificationHit? {
        let lowered = command.lowercased()
        for rule in Self.rules {
            if rule.patterns.contains(where: { lowered.contains($0) }) {
                return rule.hit
            }
        }
        return nil
    }
}
