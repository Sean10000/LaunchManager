import Foundation

struct ProjectResolver {
    func resolve(workingDirectory: String) -> String? {
        let base = URL(fileURLWithPath: workingDirectory, isDirectory: true)
        if let name = readPackageJsonName(at: base) { return name }
        if let name = readTomlName(at: base.appendingPathComponent("pyproject.toml"), section: "project") {
            return name
        }
        if let name = readTomlName(at: base.appendingPathComponent("Cargo.toml"), section: "package") {
            return name
        }
        return nil
    }

    private func readPackageJsonName(at directory: URL) -> String? {
        let url = directory.appendingPathComponent("package.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = json["name"] as? String,
              !name.isEmpty else {
            return nil
        }
        return name
    }

    private func readTomlName(at url: URL, section: String) -> String? {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let header = "[\(section)]"
        guard let sectionRange = contents.range(of: header) else { return nil }

        let afterSection = contents[sectionRange.upperBound...]
        let sectionBody: Substring
        if let nextHeader = afterSection.range(of: "\n[", options: [], range: nil, locale: nil) {
            sectionBody = afterSection[..<nextHeader.lowerBound]
        } else {
            sectionBody = afterSection
        }

        for line in sectionBody.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("name") else { continue }
            if let value = parseTomlStringValue(from: trimmed) {
                return value
            }
        }
        return nil
    }

    private func parseTomlStringValue(from line: String) -> String? {
        guard let equals = line.firstIndex(of: "=") else { return nil }
        var value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
        guard let first = value.first, first == "\"" || first == "'" else { return nil }
        value.removeFirst()
        if let end = value.firstIndex(of: first) {
            let name = String(value[..<end])
            return name.isEmpty ? nil : name
        }
        return nil
    }
}
