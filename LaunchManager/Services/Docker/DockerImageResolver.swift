import Foundation

struct DockerImageResolver {
    func resolve(image: String) -> ClassificationHit? {
        let lower = image.lowercased()
        if lower.contains("redis") {
            return .init(displayName: "Redis", category: .cache, generatesURL: false, identityKind: .realService)
        }
        if lower.contains("postgres") || lower.contains("postgresql") {
            return .init(displayName: "PostgreSQL", category: .database, generatesURL: false, identityKind: .realService)
        }
        if lower.contains("next") {
            return .init(displayName: "Next.js", category: .web, generatesURL: true, identityKind: .realService)
        }
        return nil
    }
}
