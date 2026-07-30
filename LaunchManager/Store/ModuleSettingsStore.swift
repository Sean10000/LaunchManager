import Foundation

struct ModuleSettings: Equatable, Codable {
    var agents: Bool = true
    var crontab: Bool = true
    var loginItems: Bool = true
    var services: Bool = true

    func isEnabled(_ module: AppModule) -> Bool {
        switch module {
        case .agents: return agents
        case .crontab: return crontab
        case .loginItems: return loginItems
        case .services: return services
        }
    }

    mutating func setEnabled(_ module: AppModule, enabled: Bool) -> Bool {
        var draft = self
        switch module {
        case .agents: draft.agents = enabled
        case .crontab: draft.crontab = enabled
        case .loginItems: draft.loginItems = enabled
        case .services: draft.services = enabled
        }
        guard draft.enabledCount > 0 else { return false }
        self = draft
        return true
    }

    mutating func enableAll() {
        agents = true
        crontab = true
        loginItems = true
        services = true
    }

    var enabledModules: [AppModule] {
        AppModule.allCases.filter(isEnabled)
    }

    var enabledCount: Int {
        enabledModules.count
    }

    var firstEnabledSelection: SidebarSelection {
        enabledModules.first?.sidebarSelection ?? .agents
    }
}

@MainActor
final class ModuleSettingsStore: ObservableObject {
    @Published private(set) var settings: ModuleSettings

    private static let storageKey = "enabledAppModules"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(ModuleSettings.self, from: data) {
            settings = decoded.enabledCount > 0 ? decoded : ModuleSettings()
        } else {
            settings = ModuleSettings()
        }
    }

    func isEnabled(_ module: AppModule) -> Bool {
        settings.isEnabled(module)
    }

    @discardableResult
    func setEnabled(_ module: AppModule, enabled: Bool) -> Bool {
        var draft = settings
        guard draft.setEnabled(module, enabled: enabled) else { return false }
        settings = draft
        persist()
        return true
    }

    func enableAll() {
        var draft = settings
        draft.enableAll()
        settings = draft
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
