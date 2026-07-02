import Foundation

@MainActor
final class ServiceStore: ObservableObject {
    @Published private(set) var services: [Service] = []
    @Published private(set) var pendingKillIDs: Set<String> = []
    @Published var lastScanError: String?

    private let discovery: ProcessScanning
    private let terminator = ServiceTerminationService()
    private let nameStore: ServiceNameStore
    private var timerTask: Task<Void, Never>?
    private var isScanning = false

    init(discovery: ProcessScanning = ProcessDiscoveryService(), nameStore: ServiceNameStore = .shared) {
        self.discovery = discovery
        self.nameStore = nameStore
    }

    func startPolling(isActive: Bool) {
        timerTask?.cancel()
        guard isActive else { return }
        timerTask = Task {
            while !Task.isCancelled {
                await performScan()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    func refreshNow() {
        Task { await performScan() }
    }

    func hasCustomName(for service: Service) -> Bool {
        nameStore.hasCustomName(for: service.identityKey)
    }

    func setCustomName(_ name: String, for service: Service) {
        nameStore.setCustomName(name, for: service.identityKey)
        applyCustomNames()
    }

    func clearCustomName(for service: Service) {
        nameStore.setCustomName(nil, for: service.identityKey)
        applyCustomNames()
    }

    func kill(_ service: Service, onError: @escaping (String) -> Void) {
        guard !pendingKillIDs.contains(service.id) else { return }
        pendingKillIDs.insert(service.id)
        Task {
            do {
                try await terminator.terminate(service)
                pendingKillIDs.remove(service.id)
                await performScan()
            } catch {
                pendingKillIDs.remove(service.id)
                onError(error.localizedDescription)
            }
        }
    }

    private func applyCustomNames() {
        services = services.map { service in
            guard let custom = nameStore.customName(for: service.identityKey) else {
                if service.displayName == service.autoDisplayName { return service }
                return service.withDisplayName(service.autoDisplayName)
            }
            if service.displayName == custom { return service }
            return service.withDisplayName(custom)
        }
    }

    private func performScan() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }

        let discovery = discovery
        let nameStore = nameStore

        do {
            let classified = try await Task.detached {
                let processes = try discovery.scan()
                let dockerIndex = DockerContainerIndex.load()
                return ServiceClassifier().classifyAll(
                    processes,
                    dockerIndex: dockerIndex,
                    nameStore: nameStore
                )
            }.value
            services = classified
            lastScanError = nil
        } catch {
            lastScanError = error.localizedDescription
        }
    }
}

private extension Service {
    func withDisplayName(_ name: String) -> Service {
        Service(
            identityKey: identityKey,
            autoDisplayName: autoDisplayName,
            displayName: name,
            identityKind: identityKind,
            runtimeGroup: runtimeGroup,
            subtitle: subtitle,
            category: category,
            health: health,
            port: port,
            host: host,
            pid: pid,
            executable: executable,
            command: command,
            workingDirectory: workingDirectory,
            processDirectory: processDirectory,
            url: url,
            dockerInfo: dockerInfo,
            stopMethod: stopMethod
        )
    }
}
