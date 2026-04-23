import Foundation

struct PlistService {

    func scanAll() -> (items: [LaunchItem], invalid: [InvalidPlist]) {
        var items: [LaunchItem] = []
        var invalid: [InvalidPlist] = []
        for scope in LaunchItem.Scope.allCases {
            let (scopeItems, scopeInvalid) = scanDirectory(scope.directoryURL, scope: scope)
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
            isLoaded: false, pid: nil, lastExitCode: nil
        )
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
        return dict
    }

    func save(_ item: LaunchItem, privilege: PrivilegeService) throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: toDictionary(item), format: .xml, options: 0)
        if item.scope.requiresPrivilege {
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent(item.plistURL.lastPathComponent)
            try data.write(to: tmp)
            try privilege.run("mv \(tmp.path) \(item.plistURL.path)")
        } else {
            try data.write(to: item.plistURL)
        }
    }

    func delete(_ item: LaunchItem,
                launchctl: LaunchctlService,
                privilege: PrivilegeService) throws {
        if item.scope.requiresPrivilege {
            let domain = item.scope == .systemDaemon ? "system" : "gui/\(getuid())"
            try privilege.run("/bin/launchctl bootout \(domain) \(item.plistURL.path); rm \(item.plistURL.path)")
        } else {
            try? launchctl.unload(item.plistURL, scope: item.scope)
            try FileManager.default.removeItem(at: item.plistURL)
        }
    }
}
