import Foundation

@MainActor
final class ServiceStore: ObservableObject {
    @Published private(set) var services: [Service] = []
    @Published private(set) var pendingKillIDs: Set<String> = []
    @Published var lastScanError: String?
    @Published var showAll: Bool {
        didSet { UserDefaults.standard.set(showAll, forKey: "servicesShowAll") }
    }

    private let discovery: ProcessScanning
    private let killer = ProcessKillService()
    private var timerTask: Task<Void, Never>?

    init(discovery: ProcessScanning = ProcessDiscoveryService()) {
        self.discovery = discovery
        self.showAll = UserDefaults.standard.bool(forKey: "servicesShowAll")
    }

    func startPolling(isActive: Bool) {
        timerTask?.cancel()
        guard isActive else { return }
        timerTask = Task {
            while !Task.isCancelled {
                refresh()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    func refresh() {
        let discovery = discovery
        let showAll = showAll
        Task {
            do {
                let filtered = try await Task.detached {
                    let processes = try discovery.scan()
                    let classifier = ServiceClassifier()
                    let filter = DevServiceFilter()
                    let classified = classifier.classifyAll(processes)
                    return filter.filter(classified, showAll: showAll)
                }.value
                services = filtered
                lastScanError = nil
            } catch {
                lastScanError = error.localizedDescription
            }
        }
    }

    func kill(_ service: Service, onError: @escaping (String) -> Void) {
        guard !pendingKillIDs.contains(service.id) else { return }
        pendingKillIDs.insert(service.id)
        Task {
            do {
                try await killer.kill(pid: service.pid)
                pendingKillIDs.remove(service.id)
                refresh()
            } catch {
                pendingKillIDs.remove(service.id)
                onError(error.localizedDescription)
            }
        }
    }
}
