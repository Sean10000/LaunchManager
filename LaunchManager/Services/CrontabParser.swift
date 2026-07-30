import Foundation

struct CrontabParser {
    private static let cronFieldPattern = #"^\S+$"#
    private static let userFieldPattern = #"^[A-Za-z_][A-Za-z0-9_-]*$"#

    static let defaultSystemHeader = """
    # /etc/crontab: system-wide crontab
    # minute\thour\tmday\tmonth\twday\twho\tcommand
    """

    static func parse(_ text: String, format: CrontabFormat = .user) -> [CrontabLine] {
        let normalized = text.hasSuffix("\n") ? String(text.dropLast()) : text
        guard !normalized.isEmpty else { return [] }

        return normalized
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { parseLine(String($0), format: format) }
    }

    static func serialize(_ lines: [CrontabLine], format: CrontabFormat = .user) -> String {
        let body = lines.map { serializeLine($0, format: format) }.joined(separator: "\n")
        return body.isEmpty ? "" : body + "\n"
    }

    static func jobs(from lines: [CrontabLine], scope: CrontabScope) -> [CronJob] {
        lines.compactMap { line in
            guard case .job(var job) = line else { return nil }
            job.scope = scope
            return job
        }
    }

    // MARK: - Private

    private static func parseLine(_ line: String, format: CrontabFormat) -> CrontabLine {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return .blank(id: UUID())
        }

        if trimmed.hasPrefix("#") {
            let remainder = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
            if let fields = parseCronFields(remainder, format: format) {
                return makeJobLine(fields: fields, format: format, isEnabled: false)
            }
            return .comment(id: UUID(), text: line)
        }

        if format == .user, let env = parseEnvironment(trimmed) {
            return .environment(id: UUID(), key: env.key, value: env.value)
        }

        if let fields = parseCronFields(trimmed, format: format) {
            return makeJobLine(fields: fields, format: format, isEnabled: true)
        }

        return .raw(id: UUID(), line: line)
    }

    private static func makeJobLine(fields: [String], format: CrontabFormat, isEnabled: Bool) -> CrontabLine {
        switch format {
        case .user:
            return .job(CronJob(
                scope: .user,
                minute: fields[0],
                hour: fields[1],
                dayOfMonth: fields[2],
                month: fields[3],
                weekday: fields[4],
                command: fields[5],
                isEnabled: isEnabled
            ))
        case .system:
            return .job(CronJob(
                scope: .system,
                minute: fields[0],
                hour: fields[1],
                dayOfMonth: fields[2],
                month: fields[3],
                weekday: fields[4],
                runAsUser: fields[5],
                command: fields[6],
                isEnabled: isEnabled
            ))
        }
    }

    private static func parseEnvironment(_ line: String) -> (key: String, value: String)? {
        guard let equalsIndex = line.firstIndex(of: "=") else { return nil }
        let key = String(line[..<equalsIndex])
        guard key.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil else {
            return nil
        }
        let valueStart = line.index(after: equalsIndex)
        return (key, String(line[valueStart...]))
    }

    private static func parseCronFields(_ line: String, format: CrontabFormat) -> [String]? {
        let parts = splitPreservingCommand(line)
        let minimumParts: Int
        let scheduleFieldCount: Int

        switch format {
        case .user:
            minimumParts = 6
            scheduleFieldCount = 5
        case .system:
            minimumParts = 7
            scheduleFieldCount = 6
        }

        guard parts.count >= minimumParts else { return nil }

        let scheduleParts = Array(parts.prefix(scheduleFieldCount))
        guard scheduleParts.prefix(5).allSatisfy({
            $0.range(of: cronFieldPattern, options: .regularExpression) != nil
        }) else {
            return nil
        }

        if format == .system {
            let user = scheduleParts[5]
            guard user.range(of: userFieldPattern, options: .regularExpression) != nil else {
                return nil
            }
        }

        let command = parts.dropFirst(scheduleFieldCount).joined(separator: " ")
        guard !command.isEmpty else { return nil }
        return scheduleParts + [command]
    }

    private static func splitPreservingCommand(_ line: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var inSingleQuote = false
        var inDoubleQuote = false
        var escaped = false

        for character in line {
            if escaped {
                current.append(character)
                escaped = false
                continue
            }

            if character == "\\" {
                escaped = true
                current.append(character)
                continue
            }

            if character == "'" && !inDoubleQuote {
                inSingleQuote.toggle()
                current.append(character)
                continue
            }

            if character == "\"" && !inSingleQuote {
                inDoubleQuote.toggle()
                current.append(character)
                continue
            }

            if character.isWhitespace && !inSingleQuote && !inDoubleQuote {
                if !current.isEmpty {
                    parts.append(current)
                    current = ""
                }
                continue
            }

            current.append(character)
        }

        if !current.isEmpty {
            parts.append(current)
        }
        return parts
    }

    private static func serializeLine(_ line: CrontabLine, format: CrontabFormat) -> String {
        switch line {
        case .blank:
            return ""
        case .comment(_, let text):
            return text
        case .environment(_, let key, let value):
            return "\(key)=\(value)"
        case .job(let job):
            let schedule = job.scheduleFields.joined(separator: " ")
            let body: String
            switch format {
            case .user:
                body = "\(schedule) \(job.command)"
            case .system:
                let user = job.runAsUser ?? "root"
                body = "\(schedule) \(user) \(job.command)"
            }
            return job.isEnabled ? body : "# \(body)"
        case .raw(_, let text):
            return text
        }
    }
}
