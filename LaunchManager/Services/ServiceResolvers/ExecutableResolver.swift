import Foundation

struct ExecutableResolver {
    private static let map: [String: ClassificationHit] = [
        "node": ClassificationHit(displayName: "Node.js", category: .web, generatesURL: false),
        "python": ClassificationHit(displayName: "Python", category: .web, generatesURL: false),
        "python3": ClassificationHit(displayName: "Python", category: .web, generatesURL: false),
        "redis-server": ClassificationHit(displayName: "Redis", category: .cache, generatesURL: false),
        "postgres": ClassificationHit(displayName: "PostgreSQL", category: .database, generatesURL: false),
        "mongod": ClassificationHit(displayName: "MongoDB", category: .database, generatesURL: false),
        "ollama": ClassificationHit(displayName: "Ollama", category: .ai, generatesURL: false),
        "nginx": ClassificationHit(displayName: "Nginx", category: .proxy, generatesURL: true),
        "docker-proxy": ClassificationHit(displayName: "Docker", category: .proxy, generatesURL: false),
    ]

    func resolve(executable: String) -> ClassificationHit? {
        let name = (executable as NSString).lastPathComponent.lowercased()
        return Self.map[name]
    }
}
