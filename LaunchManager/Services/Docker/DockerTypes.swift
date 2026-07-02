import Foundation

struct DockerContainerInfo: Equatable, Hashable, Sendable {
    let id: String
    let name: String
    let image: String
    let composeProject: String?
    let composeService: String?
    let publishedHostPorts: [Int]

    var stopReference: String { name }

    var shortID: String {
        id.count > 12 ? String(id.prefix(12)) : id
    }

    /// Preferred human label before image-based classification.
    var containerLabel: String {
        if let composeService, !composeService.isEmpty { return composeService }
        return name.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

enum ServiceStopMethod: Equatable, Hashable, Sendable {
    case process(pid: Int32)
    case dockerContainer(reference: String, containerName: String)
    /// docker-proxy / colima listener without a resolvable container — never SIGKILL the proxy.
    case blocked(reason: String)
}
