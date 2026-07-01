import Foundation

struct CommandLineResolver {
    private struct Rule {
        let patterns: [String]
        let hit: ClassificationHit
    }

    private static let rules: [Rule] = [
        Rule(
            patterns: ["next dev", "next start"],
            hit: ClassificationHit(displayName: "Next.js", category: .web, generatesURL: true)
        ),
        Rule(
            patterns: ["vite"],
            hit: ClassificationHit(displayName: "Vite", category: .web, generatesURL: true)
        ),
        Rule(
            patterns: ["nuxt"],
            hit: ClassificationHit(displayName: "Nuxt", category: .web, generatesURL: true)
        ),
        Rule(
            patterns: ["uvicorn"],
            hit: ClassificationHit(displayName: "FastAPI", category: .web, generatesURL: true)
        ),
        Rule(
            patterns: ["gunicorn"],
            hit: ClassificationHit(displayName: "Flask", category: .web, generatesURL: true)
        ),
        Rule(
            patterns: ["manage.py runserver"],
            hit: ClassificationHit(displayName: "Django", category: .web, generatesURL: true)
        ),
        Rule(
            patterns: ["cargo run"],
            hit: ClassificationHit(displayName: "Rust", category: .web, generatesURL: true)
        ),
        Rule(
            patterns: ["go run"],
            hit: ClassificationHit(displayName: "Go", category: .web, generatesURL: true)
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
