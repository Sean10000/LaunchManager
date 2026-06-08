import Foundation

@MainActor
final class AgentStore: ObservableObject {
    @Published var items: [LaunchItem] = []
    @Published var invalidItems: [InvalidPlist] = []
    @Published var pendingOperations: [String: PendingOperation] = [:]

    private let plistService: PlistService
    private let launchctlService: LaunchctlService
    private let privilegeService: PrivilegeService

    init(plistService: PlistService = PlistService(),
         launchctlService: LaunchctlService = LaunchctlService(),
         privilegeService: PrivilegeService = PrivilegeService()) {
        self.plistService = plistService
        self.launchctlService = launchctlService
        self.privilegeService = privilegeService
    }

    func refresh() {
        let (scanned, invalid) = plistService.scanAll()
        let statuses = (try? launchctlService.listAll()) ?? [:]
        items = scanned.map { item in
            var copy = item
            if let s = statuses[item.label] {
                copy.isLoaded     = true
                copy.pid          = s.pid
                copy.lastExitCode = s.exitCode
            }
            return copy
        }
        invalidItems = invalid
    }

    func bootstrap(_ item: LaunchItem, onError: @escaping (String) -> Void = { _ in }) {
        runPending(item.label, .loading, onError: onError) {
            try await self.runLaunchctl(scope: item.scope) {
                try self.launchctlService.bootstrap(item.plistURL, scope: item.scope)
            }
            await self.refresh()
        }
    }

    func bootout(_ item: LaunchItem, onError: @escaping (String) -> Void = { _ in }) {
        runPending(item.label, .unloading, onError: onError) {
            try await self.runLaunchctl(scope: item.scope) {
                try self.launchctlService.bootout(item.plistURL, scope: item.scope)
            }
            await self.refresh()
        }
    }

    func start(_ item: LaunchItem, onError: @escaping (String) -> Void = { _ in }) {
        runPending(item.label, .starting, onError: onError) {
            try await self.runLaunchctl(scope: item.scope) {
                try self.launchctlService.start(item.label, scope: item.scope)
            }
            await self.refresh()
            try? await Task.sleep(nanoseconds: 800_000_000)
            await self.refresh()
        }
    }

    func stop(_ item: LaunchItem, onError: @escaping (String) -> Void = { _ in }) {
        runPending(item.label, .stopping, onError: onError) {
            try await self.runLaunchctl(scope: item.scope) {
                try self.launchctlService.stop(item.label, scope: item.scope)
            }
            await self.refresh()
            try? await Task.sleep(nanoseconds: 400_000_000)
            await self.refresh()
        }
    }

    func save(_ item: LaunchItem) throws {
        try plistService.save(item, privilege: privilegeService)
        refresh()
    }

    func delete(_ item: LaunchItem) throws {
        try plistService.delete(item, launchctl: launchctlService, privilege: privilegeService)
        refresh()
    }

    func deleteInvalid(_ item: InvalidPlist) throws {
        if item.scope.requiresPrivilege {
            try privilegeService.run("rm \(item.url.path)")
        } else {
            try FileManager.default.removeItem(at: item.url)
        }
        refresh()
    }

    // MARK: - Private

    private func runPending(
        _ label: String,
        _ operation: PendingOperation,
        onError: @escaping (String) -> Void,
        work: @escaping () async throws -> Void
    ) {
        guard pendingOperations[label] == nil else { return }
        pendingOperations[label] = operation
        Task {
            defer { pendingOperations.removeValue(forKey: label) }
            do {
                try await work()
            } catch PrivilegeError.cancelled {
                // user dismissed admin dialog — no alert
            } catch {
                onError(error.localizedDescription)
            }
        }
    }

    private func runLaunchctl(
        scope: LaunchItem.Scope,
        _ block: @escaping @Sendable () throws -> Void
    ) async throws {
        if scope.requiresPrivilege {
            try await MainActor.run { try block() }
        } else {
            try await Task.detached { try block() }.value
        }
    }
}
