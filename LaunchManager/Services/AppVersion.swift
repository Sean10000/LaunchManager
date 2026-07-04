import Foundation

struct AppVersion: Equatable, Sendable, Comparable {
    let major: Int
    let minor: Int
    let patch: Int

    static var current: AppVersion {
        let raw = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        return parse(raw) ?? AppVersion(major: 0, minor: 0, patch: 0)
    }

    static func parse(_ string: String) -> AppVersion? {
        var trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("v") || trimmed.hasPrefix("V") {
            trimmed.removeFirst()
        }
        if let dash = trimmed.firstIndex(of: "-") {
            trimmed = String(trimmed[..<dash])
        }
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 1,
              let major = Int(parts[0]) else { return nil }
        let minor = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        let patch = parts.count > 2 ? Int(parts[2]) ?? 0 : 0
        return AppVersion(major: major, minor: minor, patch: patch)
    }

    var displayString: String {
        "\(major).\(minor).\(patch)"
    }

    func isNewer(than other: AppVersion) -> Bool {
        self > other
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}
