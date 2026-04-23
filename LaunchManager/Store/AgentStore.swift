import Foundation

@MainActor
final class AgentStore: ObservableObject {
    @Published var items: [LaunchItem] = []
    @Published var invalidItems: [InvalidPlist] = []

    private let plistService     = PlistService()
    private let launchctlService = LaunchctlService()
    private let privilegeService = PrivilegeService()

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

    func load(_ item: LaunchItem) throws {
        try launchctlService.load(item.plistURL, privileged: item.scope.requiresPrivilege)
        refresh()
    }

    func unload(_ item: LaunchItem) throws {
        try launchctlService.unload(item.plistURL, privileged: item.scope.requiresPrivilege)
        refresh()
    }

    func start(_ item: LaunchItem) throws {
        try launchctlService.start(item.label, privileged: item.scope.requiresPrivilege)
        refresh()
    }

    func stop(_ item: LaunchItem) throws {
        try launchctlService.stop(item.label, privileged: item.scope.requiresPrivilege)
        refresh()
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
}
