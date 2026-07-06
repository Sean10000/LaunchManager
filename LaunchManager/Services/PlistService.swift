import Foundation

enum PlistValidationError: Error, Equatable {
    case invalidFormat(String)
    case missingLabel
}

extension PlistValidationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidFormat(let message):
            return message
        case .missingLabel:
            return String(localized: "Plist must contain a Label key")
        }
    }
}

struct PlistService {
    /// Keys the form editor reads and writes. Any other key on disk requires XML mode.
    static let formManagedKeys: Set<String> = [
        "Label", "Program", "ProgramArguments",
        "StartCalendarInterval", "StartInterval", "WatchPaths",
        "RunAtLoad", "KeepAlive",
        "StandardOutPath", "StandardErrorPath", "WorkingDirectory",
        "EnvironmentVariables",
    ]

    /// When set (e.g. in unit tests), overrides `LaunchItem.Scope.directoryURL` for scan and clone destinations.
    var scopeDirectoryOverrides: [LaunchItem.Scope: URL] = [:]

    func directoryURL(for scope: LaunchItem.Scope) -> URL {
        scopeDirectoryOverrides[scope] ?? scope.directoryURL
    }

    func readDictionary(from url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        guard let dict = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw PlistValidationError.invalidFormat("Root must be a dictionary")
        }
        return dict
    }

    func extraKeys(in dict: [String: Any]) -> [String] {
        dict.keys.filter { !Self.formManagedKeys.contains($0) }.sorted()
    }

    func formIncompatibilityReason(for dict: [String: Any]) -> String? {
        let extra = extraKeys(in: dict)
        if !extra.isEmpty {
            return String(localized: "此 plist 包含表单不支持的键：\(extra.joined(separator: ", "))。请使用 XML 模式编辑。")
        }
        if let keepAlive = dict["KeepAlive"], keepAlive is Bool == false {
            return String(localized: "KeepAlive 使用了表单不支持的格式，请使用 XML 模式编辑。")
        }
        let triggers = [
            dict["StartCalendarInterval"] != nil,
            dict["StartInterval"] != nil,
            dict["WatchPaths"] != nil,
        ].filter { $0 }.count
        if triggers > 1 {
            return String(localized: "存在多个触发器，请使用 XML 模式编辑。")
        }
        return nil
    }

    func scanAll() -> (items: [LaunchItem], invalid: [InvalidPlist]) {
        var items: [LaunchItem] = []
        var invalid: [InvalidPlist] = []
        for scope in LaunchItem.Scope.allCases {
            let (scopeItems, scopeInvalid) = scanDirectory(directoryURL(for: scope), scope: scope)
            items.append(contentsOf: scopeItems)
            invalid.append(contentsOf: scopeInvalid)
        }
        return (items, invalid)
    }

    func scanDirectory(_ dir: URL, scope: LaunchItem.Scope) -> (items: [LaunchItem], invalid: [InvalidPlist]) {
        var items: [LaunchItem] = []
        var invalid: [InvalidPlist] = []
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ) else { return (items, invalid) }
        for url in contents where url.pathExtension == "plist" {
            if let item = parsePlist(at: url, scope: scope) {
                items.append(item)
            } else {
                invalid.append(InvalidPlist(url: url, scope: scope))
            }
        }
        return (items, invalid)
    }

    func parsePlist(at url: URL, scope: LaunchItem.Scope) -> LaunchItem? {
        guard let data = try? Data(contentsOf: url),
              let raw = try? PropertyListSerialization.propertyList(
                  from: data, options: [], format: nil),
              let dict = raw as? [String: Any],
              let label = dict["Label"] as? String
        else { return nil }

        var program = ""
        var programArguments: [String] = []
        if let args = dict["ProgramArguments"] as? [String], !args.isEmpty {
            program = args[0]
            programArguments = Array(args.dropFirst())
        } else if let prog = dict["Program"] as? String {
            program = prog
        }

        var triggerType: LaunchItem.TriggerType = .atLoad
        var calendarInterval: LaunchItem.CalendarInterval?
        var startInterval: Int?
        var watchPaths: [String] = []

        if let ci = dict["StartCalendarInterval"] as? [String: Int] {
            triggerType = .calendar
            calendarInterval = LaunchItem.CalendarInterval(
                weekday: ci["Weekday"],
                hour: ci["Hour"],
                minute: ci["Minute"] ?? 0
            )
        } else if let si = dict["StartInterval"] as? Int {
            triggerType = .interval
            startInterval = si
        } else if let wp = dict["WatchPaths"] as? [String] {
            triggerType = .watchPath
            watchPaths = wp
        }

        return LaunchItem(
            label: label, plistURL: url, scope: scope,
            program: program, programArguments: programArguments,
            triggerType: triggerType, calendarInterval: calendarInterval,
            startInterval: startInterval, watchPaths: watchPaths,
            runAtLoad: dict["RunAtLoad"] as? Bool ?? false,
            keepAlive: dict["KeepAlive"] as? Bool ?? false,
            standardOutPath: dict["StandardOutPath"] as? String,
            standardErrorPath: dict["StandardErrorPath"] as? String,
            workingDirectory: dict["WorkingDirectory"] as? String,
            environmentVariables: parseEnvironmentVariables(dict["EnvironmentVariables"]),
            isLoaded: false, isDisabledByOverride: false, pid: nil, lastExitCode: nil
        )
    }

    func parseEnvironmentVariables(_ value: Any?) -> [String: String] {
        guard let dict = value as? [String: Any] else { return [:] }
        var result: [String: String] = [:]
        for (key, val) in dict {
            if let string = val as? String {
                result[key] = string
            }
        }
        return result
    }

    func toDictionary(_ item: LaunchItem) -> [String: Any] {
        var dict: [String: Any] = ["Label": item.label]
        if item.programArguments.isEmpty {
            dict["Program"] = item.program
        } else {
            dict["ProgramArguments"] = [item.program] + item.programArguments
        }
        switch item.triggerType {
        case .calendar:
            if let ci = item.calendarInterval {
                var d: [String: Int] = ["Minute": ci.minute]
                if let w = ci.weekday { d["Weekday"] = w }
                if let h = ci.hour    { d["Hour"] = h }
                dict["StartCalendarInterval"] = d
            }
        case .interval:
            if let si = item.startInterval { dict["StartInterval"] = si }
        case .watchPath:
            if !item.watchPaths.isEmpty { dict["WatchPaths"] = item.watchPaths }
        case .atLoad:
            break
        }
        if item.runAtLoad  { dict["RunAtLoad"]  = true }
        if item.keepAlive  { dict["KeepAlive"]  = true }
        if let o = item.standardOutPath   { dict["StandardOutPath"]   = o }
        if let e = item.standardErrorPath { dict["StandardErrorPath"] = e }
        if let wd = item.workingDirectory { dict["WorkingDirectory"] = wd }
        if !item.environmentVariables.isEmpty { dict["EnvironmentVariables"] = item.environmentVariables }
        return dict
    }

    func save(_ item: LaunchItem, privilege: PrivilegeService) throws {
        if FileManager.default.fileExists(atPath: item.plistURL.path) {
            let dict = try readDictionary(from: item.plistURL)
            if let reason = formIncompatibilityReason(for: dict) {
                throw PlistValidationError.invalidFormat(reason)
            }
        }
        let data = try PropertyListSerialization.data(
            fromPropertyList: toDictionary(item), format: .xml, options: 0)
        if item.scope.requiresPrivilege {
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent(item.plistURL.lastPathComponent)
            try data.write(to: tmp)
            let dest = shellQuote(item.plistURL.path)
            let src = shellQuote(tmp.path)
            try privilege.run("mv \(src) \(dest) && chown root:wheel \(dest) && chmod 644 \(dest)")
        } else {
            try data.write(to: item.plistURL)
        }
    }

    func validateXml(_ string: String) -> Result<[String: Any], PlistValidationError> {
        guard let data = string.data(using: .utf8) else {
            return .failure(.invalidFormat("Invalid UTF-8"))
        }
        do {
            guard let dict = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
                return .failure(.invalidFormat("Root must be a dictionary"))
            }
            guard dict["Label"] is String else {
                return .failure(.missingLabel)
            }
            return .success(dict)
        } catch {
            return .failure(.invalidFormat(error.localizedDescription))
        }
    }

    func readXml(from url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let xmlData = try PropertyListSerialization.data(
            fromPropertyList: try PropertyListSerialization.propertyList(from: data, options: [], format: nil),
            format: .xml,
            options: 0)
        guard let string = String(data: xmlData, encoding: .utf8) else {
            throw PlistValidationError.invalidFormat("Cannot encode XML")
        }
        return string
    }

    func saveRawXml(_ string: String, to url: URL, scope: LaunchItem.Scope, privilege: PrivilegeService) throws {
        switch validateXml(string) {
        case .failure(let err):
            throw err
        case .success(let dict):
            let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
            if scope.requiresPrivilege {
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
                try data.write(to: tmp)
                let dest = shellQuote(url.path)
                let src = shellQuote(tmp.path)
                try privilege.run("mv \(src) \(dest) && chown root:wheel \(dest) && chmod 644 \(dest)")
            } else {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url)
            }
        }
    }

    func clonePlist(from sourceURL: URL, newLabel: String, targetScope: LaunchItem.Scope, targetDirectory: URL? = nil, privilege: PrivilegeService = PrivilegeService()) throws -> URL {
        let xml = try readXml(from: sourceURL)
        var dict: [String: Any]
        switch validateXml(xml) {
        case .failure(let err):
            throw err
        case .success(let d):
            dict = d
        }
        dict["Label"] = newLabel
        let dir = targetDirectory ?? directoryURL(for: targetScope)
        let dest = dir.appendingPathComponent("\(newLabel).plist")
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        guard let destString = String(data: data, encoding: .utf8) else {
            throw PlistValidationError.invalidFormat("Cannot encode XML")
        }
        try saveRawXml(destString, to: dest, scope: targetScope, privilege: privilege)
        return dest
    }

    private func shellQuote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    func delete(_ item: LaunchItem,
                launchctl: LaunchctlService,
                privilege: PrivilegeService) throws {
        if item.scope.requiresPrivilege {
            let domain = item.scope == .systemDaemon ? "system" : "gui/\(getuid())"
            try privilege.run("/bin/launchctl bootout \(domain) \(item.plistURL.path); rm \(item.plistURL.path)")
        } else {
            try? launchctl.bootout(item.plistURL, scope: item.scope)
            try FileManager.default.removeItem(at: item.plistURL)
        }
    }
}
