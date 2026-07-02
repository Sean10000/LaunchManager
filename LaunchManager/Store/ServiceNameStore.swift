import Foundation

/// Persists user-assigned display names keyed by port + executable (stable across PID changes).
final class ServiceNameStore {
    static let shared = ServiceNameStore()

    private let defaults: UserDefaults
    private let defaultsKey = "serviceCustomDisplayNames"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    static func identityKey(port: Int, executable: String, dockerContainer: DockerContainerInfo? = nil) -> String {
        if let dockerContainer {
            let name = dockerContainer.name
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                .lowercased()
            return "\(port):docker:\(name)"
        }
        let name = (executable as NSString).lastPathComponent.lowercased()
        return "\(port):\(name)"
    }

    static func identityKey(port: Int, executable: String) -> String {
        identityKey(port: port, executable: executable, dockerContainer: nil)
    }

    func customName(for identityKey: String) -> String? {
        let trimmed = names[identityKey]?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed
    }

    func setCustomName(_ name: String?, for identityKey: String) {
        var map = names
        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            map[identityKey] = name.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            map.removeValue(forKey: identityKey)
        }
        names = map
    }

    func hasCustomName(for identityKey: String) -> Bool {
        customName(for: identityKey) != nil
    }

    private var names: [String: String] {
        get { defaults.dictionary(forKey: defaultsKey) as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: defaultsKey) }
    }
}
