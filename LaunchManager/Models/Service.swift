import Foundation

enum ServiceCategory: String, Equatable, Sendable {
    case web, database, cache, ai, proxy, hostMechanism, other
}

enum ServiceRuntimeGroup: String, CaseIterable, Equatable, Sendable {
    case docker
    case instance

    var title: String {
        switch self {
        case .docker: return "Docker"
        case .instance: return String(localized: "本地实例")
        }
    }

    var systemImage: String {
        switch self {
        case .docker: return "shippingbox"
        case .instance: return "desktopcomputer"
        }
    }
}

struct Service: Identifiable, Hashable, Sendable {
    var id: String { "\(pid)-\(port)" }
    let identityKey: String
    let autoDisplayName: String
    let displayName: String
    let identityKind: ServiceIdentityKind
    let runtimeGroup: ServiceRuntimeGroup
    let subtitle: String?
    let category: ServiceCategory
    let health: ServiceHealth
    let port: Int
    let host: String
    let pid: Int32
    let executable: String
    let command: String
    let workingDirectory: String?
    let processDirectory: String?
    let url: URL?
    let dockerInfo: DockerContainerInfo?
    let stopMethod: ServiceStopMethod

    var addressLabel: String {
        if let url { return url.absoluteString }
        return "\(host):\(port)"
    }

    var isDockerManaged: Bool {
        dockerInfo != nil || usesDockerStop
    }

    var usesDockerStop: Bool {
        if case .dockerContainer = stopMethod { return true }
        return false
    }

    var killAllowed: Bool {
        if case .blocked = stopMethod { return false }
        return true
    }

    var killBlockedReason: String? {
        if case .blocked(let reason) = stopMethod { return reason }
        return nil
    }

    var brewFormulaName: String? {
        BrewManagedSupport.formulaName(fromExecutable: executable)
    }

    var isHomebrewManaged: Bool {
        brewFormulaName != nil
    }

    var brewLaunchdLabel: String? {
        brewFormulaName.map { BrewManagedSupport.label(forFormula: $0) }
    }
}
