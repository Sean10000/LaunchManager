import Foundation

@MainActor
final class HomebrewServiceStore: ObservableObject {
    @Published private(set) var servicesByScope: [HomebrewServiceScope: [HomebrewService]] = [:]
    @Published private(set) var isRefreshing = false
    @Published private(set) var brewAvailable = true
    @Published var pendingOperations: [String: PendingOperation] = [:]

    private let service: BrewServicesService
    private var refreshTask: Task<Void, Never>?

    init(service: BrewServicesService = BrewServicesService()) {
        self.service = service
        self.brewAvailable = service.isBrewAvailable
    }

    var services: [HomebrewService] {
        HomebrewServiceScope.allCases.flatMap { services(for: $0) }
    }

    var servicesByLabel: [String: HomebrewService] {
        Dictionary(services.map { ($0.label, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func services(for scope: HomebrewServiceScope) -> [HomebrewService] {
        servicesByScope[scope] ?? []
    }

    func refresh(notifyAgentsOnComplete: Bool = false) {
        refreshTask?.cancel()
        isRefreshing = true
        let brewService = service

        refreshTask = Task {
            let available = brewService.isBrewAvailable
            var updated: [HomebrewServiceScope: [HomebrewService]] = [:]

            if available {
                for scope in HomebrewServiceScope.allCases {
                    if Task.isCancelled { return }
                    let items = await Task.detached(priority: .userInitiated) {
                        (try? brewService.listServices(scope: scope)) ?? []
                    }.value
                    updated[scope] = items
                }
            }

            guard !Task.isCancelled else {
                isRefreshing = false
                return
            }

            brewAvailable = available
            servicesByScope = available ? updated : [:]
            isRefreshing = false

            if notifyAgentsOnComplete {
                NotificationCenter.default.post(name: .brewServicesDidChange, object: nil)
            }
        }
    }

    func start(_ item: HomebrewService, onError: @escaping (String) -> Void = { _ in }) {
        runPending(item, .starting, operationName: String(localized: "启动"), onError: onError) {
            try self.service.start(item.name, scope: item.scope)
            self.refreshAfterMutation()
        }
    }

    func stop(_ item: HomebrewService, onError: @escaping (String) -> Void = { _ in }) {
        runPending(item, .stopping, operationName: String(localized: "停止"), onError: onError) {
            try self.service.stop(item.name, scope: item.scope)
            self.refreshAfterMutation()
        }
    }

    func restart(_ item: HomebrewService, onError: @escaping (String) -> Void = { _ in }) {
        runPending(item, .restarting, operationName: String(localized: "重启"), onError: onError) {
            try self.service.restart(item.name, scope: item.scope)
            self.refreshAfterMutation()
        }
    }

    // MARK: - Private

    private func refreshAfterMutation() {
        refresh(notifyAgentsOnComplete: true)
    }

    private func runPending(
        _ item: HomebrewService,
        _ operation: PendingOperation,
        operationName: String,
        onError: @escaping (String) -> Void,
        work: @escaping () throws -> Void
    ) {
        guard pendingOperations[item.id] == nil else { return }
        pendingOperations[item.id] = operation
        Task {
            defer { pendingOperations.removeValue(forKey: item.id) }
            do {
                try work()
            } catch PrivilegeError.cancelled {
                // user dismissed admin dialog
            } catch let error as ShellError {
                onError(brewErrorMessage(operation: operationName, detail: error.localizedDescription))
            } catch {
                onError(brewErrorMessage(operation: operationName, detail: error.localizedDescription))
            }
        }
    }

    private func brewErrorMessage(operation: String, detail: String) -> String {
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "\(operation)失败" }
        return "\(operation)失败：\(trimmed)"
    }
}
