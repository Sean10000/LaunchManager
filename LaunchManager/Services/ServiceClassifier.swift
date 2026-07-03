import Foundation

struct ServiceClassifier {
    private let realService = RealServiceResolver()
    private let hostMechanism = HostMechanismResolver()
    private let projectContext = ProjectContextResolver()
    private let dockerImages = DockerImageResolver()

    func classify(
        _ process: ListeningProcess,
        dockerIndex: DockerContainerIndex,
        nameStore: ServiceNameStore = .shared
    ) -> Service {
        let context = projectContext.resolve(process: process)
        let dockerManaged = DockerManagedDetector.isDockerManaged(process)
        let container = dockerManaged ? dockerIndex.container(forHostPort: process.port) : nil

        if dockerManaged, let container {
            return classifyDockerContainer(
                process: process,
                container: container,
                context: context,
                nameStore: nameStore
            )
        }

        if dockerManaged {
            return classifyBlockedDockerProxy(process: process, context: context, nameStore: nameStore)
        }

        return classifyDirectProcess(process: process, context: context, nameStore: nameStore)
    }

    func classifyAll(
        _ processes: [ListeningProcess],
        dockerIndex: DockerContainerIndex = DockerContainerIndex(containers: []),
        nameStore: ServiceNameStore = .shared
    ) -> [Service] {
        processes.map { classify($0, dockerIndex: dockerIndex, nameStore: nameStore) }
    }

    private func classifyDockerContainer(
        process: ListeningProcess,
        container: DockerContainerInfo,
        context: ProjectContext,
        nameStore: ServiceNameStore
    ) -> Service {
        let identityKey = ServiceNameStore.identityKey(
            port: process.port, executable: process.executable, dockerContainer: container
        )

        let imageHit = dockerImages.resolve(image: container.image)
        let hit: ClassificationHit?
        let identityKind: ServiceIdentityKind
        let autoDisplayName: String

        if let imageHit {
            hit = imageHit
            identityKind = .realService
            autoDisplayName = imageHit.displayName
        } else {
            hit = nil
            identityKind = .realService
            autoDisplayName = container.containerLabel
        }

        let category = hit?.category ?? .other
        let subtitle = dockerSubtitle(container: container, projectName: context.projectName)
        let url: URL? = (hit?.generatesURL == true)
            ? URL(string: "http://localhost:\(process.port)")
            : nil
        let health: ServiceHealth = ProcessDiscoveryService.isProcessAlive(pid: process.pid)
            ? .healthy : .down
        let customName = nameStore.customName(for: identityKey)
        let displayName = customName ?? autoDisplayName

        return Service(
            identityKey: identityKey,
            autoDisplayName: autoDisplayName,
            displayName: displayName,
            identityKind: identityKind,
            runtimeGroup: .docker,
            subtitle: subtitle,
            category: category,
            health: health,
            port: process.port,
            host: "localhost",
            pid: process.pid,
            executable: process.executable,
            command: process.command,
            workingDirectory: context.projectDirectory,
            processDirectory: context.processDirectory,
            url: url,
            dockerInfo: container,
            stopMethod: .dockerContainer(reference: container.stopReference, containerName: container.containerLabel)
        )
    }

    private func classifyBlockedDockerProxy(
        process: ListeningProcess,
        context: ProjectContext,
        nameStore: ServiceNameStore
    ) -> Service {
        let identityKey = ServiceNameStore.identityKey(port: process.port, executable: process.executable)
        let mechanismHit = hostMechanism.resolve(process: process)
        let autoDisplayName = mechanismHit?.displayName ?? String(localized: "Docker 端口转发")
        let customName = nameStore.customName(for: identityKey)
        let health: ServiceHealth = ProcessDiscoveryService.isProcessAlive(pid: process.pid)
            ? .healthy : .down

        return Service(
            identityKey: identityKey,
            autoDisplayName: autoDisplayName,
            displayName: customName ?? autoDisplayName,
            identityKind: .hostMechanism,
            runtimeGroup: .docker,
            subtitle: context.projectName,
            category: .hostMechanism,
            health: health,
            port: process.port,
            host: "localhost",
            pid: process.pid,
            executable: process.executable,
            command: process.command,
            workingDirectory: context.projectDirectory,
            processDirectory: context.processDirectory,
            url: nil,
            dockerInfo: nil,
            stopMethod: .blocked(reason: String(localized: "无法定位 Docker 容器，不能直接终止 docker-proxy（会破坏 Docker 网络）。请使用 docker stop 或在 Docker Desktop 中停止。"))
        )
    }

    private func classifyDirectProcess(
        process: ListeningProcess,
        context: ProjectContext,
        nameStore: ServiceNameStore
    ) -> Service {
        let identityKey = ServiceNameStore.identityKey(port: process.port, executable: process.executable)
        let realHit = realService.resolve(process: process, context: context)
        let mechanismHit = hostMechanism.resolve(process: process)

        let hit: ClassificationHit?
        let identityKind: ServiceIdentityKind
        let autoDisplayName: String

        if let realHit {
            hit = realHit
            identityKind = .realService
            autoDisplayName = realHit.displayName
        } else if let mechanismHit {
            hit = mechanismHit
            identityKind = .hostMechanism
            autoDisplayName = mechanismHit.displayName
        } else {
            hit = nil
            identityKind = .unidentified
            autoDisplayName = (process.executable as NSString).lastPathComponent
        }

        let category = hit?.category ?? .other
        let subtitle = context.projectName
        let url: URL? = (hit?.generatesURL == true)
            ? URL(string: "http://localhost:\(process.port)")
            : nil
        let health: ServiceHealth = ProcessDiscoveryService.isProcessAlive(pid: process.pid)
            ? .healthy : .down
        let customName = nameStore.customName(for: identityKey)
        let displayName = customName ?? autoDisplayName

        return Service(
            identityKey: identityKey,
            autoDisplayName: autoDisplayName,
            displayName: displayName,
            identityKind: identityKind,
            runtimeGroup: .instance,
            subtitle: subtitle,
            category: category,
            health: health,
            port: process.port,
            host: "localhost",
            pid: process.pid,
            executable: process.executable,
            command: process.command,
            workingDirectory: context.projectDirectory,
            processDirectory: context.processDirectory,
            url: url,
            dockerInfo: nil,
            stopMethod: .process(pid: process.pid)
        )
    }

    private func dockerSubtitle(container: DockerContainerInfo, projectName: String?) -> String? {
        var parts: [String] = []
        if let composeProject = container.composeProject {
            parts.append(composeProject)
        } else if let projectName {
            parts.append(projectName)
        }
        if !container.image.isEmpty {
            parts.append(container.image)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
