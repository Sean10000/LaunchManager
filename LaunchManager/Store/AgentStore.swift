import Foundation

@MainActor
final class AgentStore: ObservableObject {
    @Published var items: [LaunchItem] = []
    @Published var invalidItems: [InvalidPlist] = []
    @Published var pendingOperations: [String: PendingOperation] = [:]

    private let plistService: PlistService
    private let launchctlService: LaunchctlService
    private let privilegeService: PrivilegeService
    private var directoryWatcher: DirectoryWatcher?

    init(plistService: PlistService = PlistService(),
         launchctlService: LaunchctlService = LaunchctlService(),
         privilegeService: PrivilegeService = PrivilegeService()) {
        self.plistService = plistService
        self.launchctlService = launchctlService
        self.privilegeService = privilegeService
    }

    func startWatching() {
        guard directoryWatcher == nil else { return }
        let paths = LaunchItem.Scope.allCases.map { plistService.directoryURL(for: $0) }
        let watcher = DirectoryWatcher { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        watcher.start(watching: paths)
        directoryWatcher = watcher
    }

    func stopWatching() {
        directoryWatcher?.stop()
        directoryWatcher = nil
    }

    func refresh() {
        let (scanned, invalid) = plistService.scanAll()
        let statuses = (try? launchctlService.listAll()) ?? [:]
        let disabledLabels = fetchDisabledLabels()
        items = scanned.map { item in
            var copy = item
            if let s = statuses[item.label] {
                copy.isLoaded     = true
                copy.pid          = s.pid
                copy.lastExitCode = s.exitCode
            }
            copy.isDisabledByOverride = disabledLabels.contains(item.label)
            return copy
        }
        invalidItems = invalid
    }

    func bootstrap(_ item: LaunchItem, onError: @escaping (String) -> Void = { _ in }) {
        runPending(item.label, .loading, operationName: String(localized: "载入"), onError: onError) {
            try await self.runLaunchctl(scope: item.scope) {
                try self.launchctlService.bootstrap(item.plistURL, scope: item.scope)
            }
            await self.refresh()
        }
    }

    func bootout(_ item: LaunchItem, onError: @escaping (String) -> Void = { _ in }) {
        runPending(item.label, .unloading, operationName: String(localized: "移除"), onError: onError) {
            try await self.runLaunchctl(scope: item.scope) {
                try self.launchctlService.bootout(item.plistURL, scope: item.scope)
            }
            await self.refresh()
        }
    }

    func start(_ item: LaunchItem, onError: @escaping (String) -> Void = { _ in }) {
        runPending(item.label, .starting, operationName: String(localized: "启动"), onError: onError) {
            try await self.runLaunchctl(scope: item.scope) {
                try self.launchctlService.start(item.label, scope: item.scope)
            }
            await self.refresh()
            try? await Task.sleep(nanoseconds: 800_000_000)
            await self.refresh()
        }
    }

    func stop(_ item: LaunchItem, onError: @escaping (String) -> Void = { _ in }) {
        runPending(item.label, .stopping, operationName: String(localized: "停止"), onError: onError) {
            try await self.runLaunchctl(scope: item.scope) {
                try self.launchctlService.stop(item.label, scope: item.scope)
            }
            await self.waitUntilStopped(label: item.label, scope: item.scope)
        }
    }

    func enable(_ item: LaunchItem, onError: @escaping (String) -> Void = { _ in }) {
        runPending(item.label, .enabling, operationName: String(localized: "启用"), onError: onError) {
            try await self.runLaunchctl(scope: item.scope) {
                try self.launchctlService.enable(item.label, scope: item.scope)
            }
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

    func saveRawXml(_ xml: String, to url: URL, scope: LaunchItem.Scope) throws {
        try plistService.saveRawXml(xml, to: url, scope: scope, privilege: privilegeService)
        refresh()
    }

    func cloneItem(_ item: LaunchItem, newLabel: String, scope: LaunchItem.Scope) throws {
        let dest = plistService.directoryURL(for: scope).appendingPathComponent("\(newLabel).plist")
        if FileManager.default.fileExists(atPath: dest.path) {
            throw PlistValidationError.invalidFormat(String(localized: "Label 已存在"))
        }
        _ = try plistService.clonePlist(
            from: item.plistURL,
            newLabel: newLabel,
            targetScope: scope,
            privilege: privilegeService
        )
        refresh()
    }

    func importPlist(from sourceURL: URL, scope: LaunchItem.Scope, overwrite: Bool) throws -> LaunchItem {
        let xml = try plistService.readXml(from: sourceURL)
        guard case .success(let dict) = plistService.validateXml(xml),
              let label = dict["Label"] as? String else {
            throw PlistValidationError.missingLabel
        }
        let dest = plistService.directoryURL(for: scope).appendingPathComponent("\(label).plist")
        if FileManager.default.fileExists(atPath: dest.path) && !overwrite {
            throw PlistValidationError.invalidFormat(String(localized: "文件已存在"))
        }
        try plistService.saveRawXml(xml, to: dest, scope: scope, privilege: privilegeService)
        refresh()
        guard let item = items.first(where: { $0.label == label && $0.scope == scope }) else {
            throw PlistValidationError.invalidFormat("Import succeeded but item not found")
        }
        return item
    }

    // MARK: - Private

    private func fetchDisabledLabels() -> Set<String> {
        var labels = Set<String>()
        let guiDomain = "gui/\(getuid())"
        if let gui = try? launchctlService.disabledLabels(domain: guiDomain) {
            labels.formUnion(gui)
        }
        if let system = try? launchctlService.disabledLabels(domain: "system") {
            labels.formUnion(system)
        }
        return labels
    }

    private func runPending(
        _ label: String,
        _ operation: PendingOperation,
        operationName: String,
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
            } catch let error as ShellError {
                onError(LaunchctlErrorFormatter.message(operation: operationName, detail: error.launchctlUserMessage))
            } catch {
                onError(LaunchctlErrorFormatter.message(operation: operationName, detail: error.localizedDescription))
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

    private func pid(for label: String) -> Int? {
        items.first(where: { $0.label == label })?.pid
    }

    /// Poll launchctl list until the job no longer reports a PID (max ~3s), then SIGKILL if needed.
    private func waitUntilStopped(label: String, scope: LaunchItem.Scope) async {
        for _ in 0..<20 {
            refresh()
            if pid(for: label) == nil { return }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        try? await runLaunchctl(scope: scope) {
            try self.launchctlService.stop(label, scope: scope, signal: "SIGKILL")
        }
        for _ in 0..<10 {
            refresh()
            if pid(for: label) == nil { return }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
    }
}
