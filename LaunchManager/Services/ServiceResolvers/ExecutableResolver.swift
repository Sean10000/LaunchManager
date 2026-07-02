import Foundation

struct ExecutableResolver {
    private static let map: [String: ClassificationHit] = [
        "redis-server": ClassificationHit(displayName: "Redis", category: .cache, generatesURL: false, identityKind: .realService),
        "redis": ClassificationHit(displayName: "Redis", category: .cache, generatesURL: false, identityKind: .realService),
        "postgres": ClassificationHit(displayName: "PostgreSQL", category: .database, generatesURL: false, identityKind: .realService),
        "postgresql": ClassificationHit(displayName: "PostgreSQL", category: .database, generatesURL: false, identityKind: .realService),
    ]

    func resolve(executable: String) -> ClassificationHit? {
        let name = (executable as NSString).lastPathComponent.lowercased()
        return Self.map[name]
    }
}
