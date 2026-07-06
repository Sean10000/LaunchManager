import Foundation

@MainActor
final class CrontabStore: ObservableObject {
    @Published private(set) var linesByScope: [CrontabScope: [CrontabLine]] = [:]
    @Published private(set) var isRefreshing = false

    private let service: CrontabService
    private let privilegeService: PrivilegeService

    init(
        service: CrontabService = CrontabService(),
        privilegeService: PrivilegeService = PrivilegeService()
    ) {
        self.service = service
        self.privilegeService = privilegeService
    }

    var jobs: [CronJob] {
        CrontabScope.allCases.flatMap { jobs(for: $0) }
    }

    func lines(for scope: CrontabScope) -> [CrontabLine] {
        linesByScope[scope] ?? []
    }

    func jobs(for scope: CrontabScope) -> [CronJob] {
        CrontabParser.jobs(from: lines(for: scope), scope: scope)
    }

    func preambleLines(for scope: CrontabScope) -> [CrontabLine] {
        lines(for: scope).filter { line in
            switch line {
            case .job:
                return false
            default:
                return true
            }
        }
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        var updated: [CrontabScope: [CrontabLine]] = [:]
        for scope in CrontabScope.allCases {
            do {
                updated[scope] = try service.parseCrontab(scope: scope)
            } catch {
                updated[scope] = linesByScope[scope] ?? []
            }
        }
        linesByScope = updated
    }

    func save(job: CronJob, replacing existingID: UUID?) throws {
        var updated = lines(for: job.scope)
        if let existingID,
           let index = updated.firstIndex(where: { $0.id == existingID }) {
            updated[index] = .job(job)
        } else {
            if !updated.isEmpty, case .blank = updated.last {
                updated[updated.count - 1] = .job(job)
            } else {
                if !updated.isEmpty {
                    updated.append(.blank(id: UUID()))
                }
                updated.append(.job(job))
            }
        }
        try persist(updated, scope: job.scope)
    }

    func deleteJob(id: UUID, scope: CrontabScope) throws {
        var updated = lines(for: scope)
        updated.removeAll { $0.id == id }
        while updated.last.map({ if case .blank = $0 { return true } else { return false } }) == true {
            updated.removeLast()
        }
        try persist(updated, scope: scope)
    }

    func setEnabled(id: UUID, scope: CrontabScope, enabled: Bool) throws {
        var updated = lines(for: scope)
        guard let index = updated.firstIndex(where: { $0.id == id }),
              case .job(var job) = updated[index] else { return }
        job.isEnabled = enabled
        updated[index] = .job(job)
        try persist(updated, scope: scope)
    }

    // MARK: - Private

    private func persist(_ updated: [CrontabLine], scope: CrontabScope) throws {
        try service.saveCrontab(
            lines: updated,
            scope: scope,
            privilege: scope.requiresPrivilege ? privilegeService : nil
        )
        linesByScope[scope] = updated
    }
}
