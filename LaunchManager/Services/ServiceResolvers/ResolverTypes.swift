import Foundation

enum ServiceIdentityKind: String, Equatable, Sendable {
    /// Confident match (Next.js, Redis, PostgreSQL, …)
    case realService
    /// Port-forward / VM / system hosting layer
    case hostMechanism
    /// Fallback to raw executable name
    case unidentified
}

struct ClassificationHit: Equatable {
    var displayName: String
    var category: ServiceCategory
    var generatesURL: Bool
    var identityKind: ServiceIdentityKind = .realService
}
