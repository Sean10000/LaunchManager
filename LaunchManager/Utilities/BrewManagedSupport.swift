import Foundation

enum BrewManagedSupport {
    static let labelPrefix = "homebrew.mxcl."

    static func isBrewLabel(_ label: String) -> Bool {
        label.hasPrefix(labelPrefix)
    }

    static func formulaName(fromLabel label: String) -> String? {
        guard isBrewLabel(label) else { return nil }
        return String(label.dropFirst(labelPrefix.count))
    }

    static func label(forFormula name: String) -> String {
        labelPrefix + name
    }

    static func formulaName(fromExecutable executable: String) -> String? {
        let normalized = (executable as NSString).standardizingPath

        for prefix in ["/opt/homebrew/opt/", "/usr/local/opt/"] {
            guard normalized.hasPrefix(prefix) else { continue }
            let remainder = normalized.dropFirst(prefix.count)
            guard let formula = remainder.split(separator: "/").first else { continue }
            return String(formula)
        }

        for prefix in ["/opt/homebrew/Cellar/", "/usr/local/Cellar/"] {
            guard normalized.hasPrefix(prefix) else { continue }
            let parts = normalized.split(separator: "/")
            guard let cellarIndex = parts.firstIndex(of: "Cellar"),
                  cellarIndex + 1 < parts.count else { continue }
            return String(parts[cellarIndex + 1])
        }

        if normalized.hasPrefix("/opt/homebrew/bin/") || normalized.hasPrefix("/usr/local/bin/") {
            let name = (normalized as NSString).lastPathComponent
            return name.isEmpty ? nil : name
        }

        return nil
    }

    static func isHomebrewExecutable(_ executable: String) -> Bool {
        formulaName(fromExecutable: executable) != nil
    }
}

extension LaunchItem {
    var isBrewManaged: Bool {
        BrewManagedSupport.isBrewLabel(label)
    }

    var brewFormulaName: String? {
        BrewManagedSupport.formulaName(fromLabel: label)
    }
}

extension HomebrewServiceStore {
    func brewService(for item: LaunchItem) -> HomebrewService? {
        guard let formula = item.brewFormulaName else { return nil }
        let preferredScope: HomebrewServiceScope = item.scope == .systemDaemon ? .root : .user
        if let match = services(for: preferredScope).first(where: { $0.name == formula }) {
            return match
        }
        return services.first { $0.name == formula }
    }

    func unregisteredServices(excludingLabels labels: Set<String>) -> [HomebrewService] {
        services.filter { service in
            !labels.contains(service.label) && service.status == .none
        }
    }
}
