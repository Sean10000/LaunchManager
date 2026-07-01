import Foundation

enum ServiceCategory: String, Equatable, Sendable {
    case web, database, cache, ai, proxy, other
}

struct Service: Identifiable, Hashable, Sendable {
    var id: String { "\(pid)-\(port)" }
    let displayName: String
    let subtitle: String?
    let category: ServiceCategory
    let health: ServiceHealth
    let port: Int
    let host: String
    let pid: Int32
    let executable: String
    let command: String
    let workingDirectory: String?
    let url: URL?

    var addressLabel: String {
        if let url { return url.absoluteString }
        return "\(host):\(port)"
    }
}
