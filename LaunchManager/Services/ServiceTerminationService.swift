import Foundation

enum ServiceTerminationError: LocalizedError {
    case blocked(String)
    case dockerFailed(String)
    case processFailed(Error)

    var errorDescription: String? {
        switch self {
        case .blocked(let message): return message
        case .dockerFailed(let message): return message
        case .processFailed(let error): return error.localizedDescription
        }
    }
}

struct ServiceTerminationService: Sendable {
    private let processKiller = ProcessKillService()
    private let docker = DockerContainerService()

    func terminate(_ service: Service) async throws {
        switch service.stopMethod {
        case .process(let pid):
            do {
                try await processKiller.kill(pid: pid)
            } catch {
                throw ServiceTerminationError.processFailed(error)
            }
        case .dockerContainer(let reference, _):
            do {
                try await docker.stopContainer(reference: reference)
            } catch {
                throw ServiceTerminationError.dockerFailed(
                    "无法停止 Docker 容器：\(error.localizedDescription)"
                )
            }
        case .blocked(let reason):
            throw ServiceTerminationError.blocked(reason)
        }
    }
}
