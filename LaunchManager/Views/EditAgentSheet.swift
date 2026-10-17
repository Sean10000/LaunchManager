import AppKit
import SwiftUI

struct EditAgentSheet: View {
    let existingItem: LaunchItem?
    let defaultScope: LaunchItem.Scope
    @ObservedObject var store: AgentStore
    @Environment(\.dismiss) private var dismiss

    @State private var editorMode: EditorMode
    @State private var label: String
    @State private var program: String
    @State private var argumentsText: String
    @State private var workingDirectory: String
    @State private var useCalendar: Bool
    @State private var calendarRows: [CalendarFormRow]
    @State private var useInterval: Bool
    @State private var intervalAmount: Int
    @State private var intervalUnit: IntervalUnit
    @State private var useWatchPath: Bool
    @State private var watchPath: String
    @State private var runAtLoad: Bool
    @State private var keepAlive: Bool
    @State private var stdoutPath: String
    @State private var stderrPath: String
    @State private var envVarRows: [EnvVarRow]
    @State private var xmlText: String
    @State private var xmlError: String?
    @State private var formDisabledReason: String?
    @State private var errorMessage: String?

    private let plistService = PlistService()

    init(
        existingItem: LaunchItem?,
        defaultScope: LaunchItem.Scope,
        store: AgentStore,
        draft: LaunchAgentDraft? = nil,
        initialXml: String? = nil
    ) {
        self.existingItem = existingItem
        self.defaultScope = defaultScope
        self.store = store

        let i = existingItem
        let d = draft

        _editorMode = State(initialValue: initialXml != nil ? .xml : .form)
        _label = State(initialValue: d?.label ?? i?.label ?? "")
        _program = State(initialValue: d?.program ?? i?.program ?? "")
        _argumentsText = State(initialValue: d?.programArguments.joined(separator: "\n") ?? i?.programArguments.joined(separator: "\n") ?? "")
        _workingDirectory = State(initialValue: d?.workingDirectory ?? i?.workingDirectory ?? "")
        let sourceIntervals = i?.calendarIntervals ?? []
        let calendarFormRows = CalendarFormRow.rows(from: sourceIntervals)
        let split = IntervalUnit.split(seconds: i?.startInterval ?? 60)
        _useCalendar = State(initialValue: !calendarFormRows.isEmpty)
        _calendarRows = State(initialValue: calendarFormRows)
        _useInterval = State(initialValue: i?.startInterval != nil)
        _intervalAmount = State(initialValue: split.amount)
        _intervalUnit = State(initialValue: split.unit)
        _useWatchPath = State(initialValue: !(i?.watchPaths.isEmpty ?? true))
        _watchPath = State(initialValue: i?.watchPaths.first ?? "")
        _runAtLoad = State(initialValue: d?.runAtLoad ?? i?.runAtLoad ?? false)
        _keepAlive = State(initialValue: d?.keepAlive ?? i?.keepAlive ?? false)
        _stdoutPath = State(initialValue: i?.standardOutPath ?? "")
        _stderrPath = State(initialValue: i?.standardErrorPath ?? "")
        _envVarRows = State(initialValue: Self.envRows(from: i?.environmentVariables ?? [:]))
        _xmlText = State(initialValue: initialXml ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("编辑模式", selection: $editorMode) {
                Text("表单").tag(EditorMode.form)
                Text("XML").tag(EditorMode.xml)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 12)
            .onChange(of: editorMode) { _, mode in
                switch mode {
                case .xml:
                    loadXmlFromCurrentState()
                case .form:
                    syncFormFromXmlIfPossible()
                }
            }

            if editorMode == .form {
                if let reason = formDisabledReason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .padding(.top, 8)
                }
                formContent
            } else {
                xmlContent
            }

            if existingItem == nil {
                templatesFooter
            }
        }
        .frame(minWidth: 480, minHeight: 360)
        .navigationTitle(existingItem == nil ? "新建 Agent" : "编辑 Agent")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { saveItem() }
                    .disabled(!canSave)
            }
        }
        .alert("错误", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("确定") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear {
            if editorMode == .xml && xmlText.isEmpty {
                loadXmlFromCurrentState()
            }
            validateXmlText()
            checkFormCompatibilityFromDisk()
        }
        .onChange(of: xmlText) { _, _ in
            validateXmlText()
        }
    }

    private var formContent: some View {
        Form {
            Section("基本信息") {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 0) {
                            Text("Label").font(.caption).foregroundStyle(.secondary)
                            Text(" *").font(.caption).foregroundStyle(.red)
                        }
                        TextField("如 com.example.mytask", text: $label)
                            .textFieldStyle(.roundedBorder)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 0) {
                            Text("程序路径").font(.caption).foregroundStyle(.secondary)
                            Text(" *").font(.caption).foregroundStyle(.red)
                        }
                        HStack {
                            TextField("如 /usr/local/bin/mytool", text: $program)
                                .textFieldStyle(.roundedBorder)
                            Button("选择…") { pickProgram() }
                        }
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        TextEditor(text: $argumentsText)
                            .font(.system(.body, design: .monospaced))
                            .frame(height: 64)
                            .background(Color(.textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color(.separatorColor), lineWidth: 1)
                            )
                        Text("每行一个参数").font(.caption).foregroundStyle(.secondary)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("工作目录").font(.caption).foregroundStyle(.secondary)
                        TextField("WorkingDirectory（可选）", text: $workingDirectory)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }

            Section("触发方式") {
                Toggle("定时", isOn: $useCalendar)
                    .onChange(of: useCalendar) { _, on in
                        if on, calendarRows.isEmpty {
                            calendarRows = [CalendarFormRow()]
                        }
                        if !on { calendarRows = [] }
                    }
                if useCalendar {
                    ForEach($calendarRows) { $row in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .center, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("频率").font(.caption).foregroundStyle(.secondary)
                                    Picker("", selection: $row.frequency) {
                                        Text("每天").tag(CalendarFrequency.daily)
                                        ForEach(1...7, id: \.self) { d in
                                            Text(["", "周一", "周二", "周三", "周四", "周五", "周六", "周日"][d])
                                                .tag(CalendarFrequency.weekday(d))
                                        }
                                        Text("每月").tag(CalendarFrequency.monthly)
                                    }
                                    .labelsHidden()
                                    .pickerStyle(.menu)
                                    .fixedSize(horizontal: true, vertical: false)
                                }
                                if row.frequency == .monthly {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("日").font(.caption).foregroundStyle(.secondary)
                                        TextField("", value: $row.monthDay, format: .number)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 52)
                                            .multilineTextAlignment(.center)
                                            .lineLimit(1)
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("每隔月数").font(.caption).foregroundStyle(.secondary)
                                        TextField("", value: $row.monthStep, format: .number)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 52)
                                            .multilineTextAlignment(.center)
                                            .lineLimit(1)
                                    }
                                }
                                HStack(alignment: .bottom, spacing: 6) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("时")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .fixedSize(horizontal: true, vertical: false)
                                        TextField("", value: $row.hour, format: .number)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 52)
                                            .multilineTextAlignment(.center)
                                            .lineLimit(1)
                                    }
                                    Text(":")
                                        .foregroundStyle(.secondary)
                                        .padding(.bottom, 6)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("分")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .fixedSize(horizontal: true, vertical: false)
                                        TextField("", value: $row.minute, format: .number)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 52)
                                            .multilineTextAlignment(.center)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 0)
                                if calendarRows.count > 1 {
                                    Button {
                                        calendarRows.removeAll { $0.id == row.id }
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                            if row.frequency == .monthly {
                                Text(row.monthStep <= 1
                                    ? String(localized: "按自然月：每月这一天触发")
                                    : String(
                                        format: String(localized: "按自然月：每 %lld 个月的这一天触发"),
                                        locale: .current,
                                        Int64(max(row.monthStep, 1))
                                    ))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button {
                        calendarRows.append(CalendarFormRow())
                    } label: {
                        Label("添加时段", systemImage: "plus")
                    }
                }

                Toggle("间隔", isOn: $useInterval)
                if useInterval {
                    HStack(spacing: 8) {
                        Text("每隔")
                            .fixedSize(horizontal: true, vertical: false)
                        TextField("数量", value: $intervalAmount, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 72)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(1)
                        Picker("", selection: $intervalUnit) {
                            ForEach(IntervalUnit.allCases) { unit in
                                Text(unit.localizedName).tag(unit)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    Text("按固定时长重复，与自然月无关")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle("监视路径", isOn: $useWatchPath)
                if useWatchPath {
                    TextField("监视路径", text: $watchPath)
                }
            }

            Section("选项") {
                Toggle("加载时自动运行", isOn: $runAtLoad)
                Toggle("保持存活（崩溃后自动重启）", isOn: $keepAlive)
            }

            Section("环境变量 EnvironmentVariables（可选）") {
                if envVarRows.isEmpty {
                    Text("无环境变量").font(.caption).foregroundStyle(.secondary)
                }
                ForEach($envVarRows) { $row in
                    HStack(spacing: 8) {
                        TextField("KEY", text: $row.key)
                            .textFieldStyle(.roundedBorder)
                        TextField("value", text: $row.value)
                            .textFieldStyle(.roundedBorder)
                        Button {
                            envVarRows.removeAll { $0.id == row.id }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Button {
                    envVarRows.append(EnvVarRow())
                } label: {
                    Label("添加变量", systemImage: "plus")
                }
            }

            Section("日志路径（可选）") {
                TextField("标准输出 StandardOutPath", text: $stdoutPath)
                TextField("标准错误 StandardErrorPath", text: $stderrPath)
            }
        }
        .formStyle(.grouped)
        .disabled(formDisabledReason != nil)
    }

    private var xmlContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $xmlText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 280)
                .padding(4)
                .background(Color(.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(.separatorColor), lineWidth: 1)
                )
                .padding(.horizontal)

            if let xmlError {
                Text(xmlError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }

    private var canSave: Bool {
        switch editorMode {
        case .form:
            return formDisabledReason == nil && !label.isEmpty && !program.isEmpty
        case .xml:
            return xmlError == nil && !xmlText.isEmpty
        }
    }

    private var templatesFooter: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                if let url = URL(string: "https://www.launchmanager.dev/templates") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("浏览 Launch Agent 模板…", systemImage: "safari")
            }
            .buttonStyle(.link)
            .padding(.vertical, 10)
        }
    }

    private func pickProgram() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            program = url.path
        }
    }

    private func loadXmlFromCurrentState() {
        if let existingItem {
            xmlText = (try? plistService.readXml(from: existingItem.plistURL)) ?? formGeneratedXml()
        } else {
            xmlText = formGeneratedXml()
        }
        validateXmlText()
    }

    private func formGeneratedXml() -> String {
        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: plistService.toDictionary(formLaunchItem()),
            format: .xml,
            options: 0
        ), let string = String(data: data, encoding: .utf8) else {
            return ""
        }
        return string
    }

    private func syncFormFromXmlIfPossible() {
        formDisabledReason = nil
        switch plistService.validateXml(xmlText) {
        case .failure:
            formDisabledReason = String(localized: "当前 plist 含表单无法完整表示的内容，请使用 XML 模式编辑。")
        case .success(let dict):
            if let reason = plistService.formIncompatibilityReason(for: dict) {
                formDisabledReason = reason
                return
            }
            guard let parsed = parseLaunchItem(from: dict) else {
                formDisabledReason = String(localized: "当前 plist 含表单无法完整表示的内容，请使用 XML 模式编辑。")
                return
            }
            applyFormFields(from: parsed)
        }
    }

    private func checkFormCompatibilityFromDisk() {
        guard editorMode == .form, let existingItem else { return }
        guard let dict = try? plistService.readDictionary(from: existingItem.plistURL) else { return }
        formDisabledReason = plistService.formIncompatibilityReason(for: dict)
    }

    private static func envRows(from variables: [String: String]) -> [EnvVarRow] {
        variables.keys.sorted().map { EnvVarRow(key: $0, value: variables[$0] ?? "") }
    }

    private var environmentVariablesFromRows: [String: String] {
        envVarRows.reduce(into: [:]) { result, row in
            let key = row.key.trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { return }
            result[key] = row.value
        }
    }

    private func parseLaunchItem(from dict: [String: Any]) -> LaunchItem? {
        guard let label = dict["Label"] as? String else { return nil }

        var program = ""
        var programArguments: [String] = []
        if let args = dict["ProgramArguments"] as? [String], !args.isEmpty {
            program = args[0]
            programArguments = Array(args.dropFirst())
        } else if let prog = dict["Program"] as? String {
            program = prog
        } else {
            return nil
        }

        let calendarIntervals = plistService.parseCalendarIntervals(from: dict["StartCalendarInterval"])
        let startInterval = dict["StartInterval"] as? Int
            ?? (dict["StartInterval"] as? NSNumber)?.intValue
        let watchPaths = dict["WatchPaths"] as? [String] ?? []

        let scope = existingItem?.scope ?? defaultScope
        let plistURL = existingItem?.plistURL ?? scope.directoryURL.appendingPathComponent("\(label).plist")

        return LaunchItem(
            label: label,
            plistURL: plistURL,
            scope: scope,
            program: program,
            programArguments: programArguments,
            calendarIntervals: calendarIntervals,
            startInterval: startInterval,
            watchPaths: watchPaths,
            runAtLoad: dict["RunAtLoad"] as? Bool ?? false,
            keepAlive: dict["KeepAlive"] as? Bool ?? false,
            standardOutPath: dict["StandardOutPath"] as? String,
            standardErrorPath: dict["StandardErrorPath"] as? String,
            workingDirectory: dict["WorkingDirectory"] as? String,
            environmentVariables: plistService.parseEnvironmentVariables(dict["EnvironmentVariables"]),
            isLoaded: existingItem?.isLoaded ?? false,
            isDisabledByOverride: existingItem?.isDisabledByOverride ?? false,
            pid: existingItem?.pid,
            lastExitCode: existingItem?.lastExitCode
        )
    }

    private func applyFormFields(from item: LaunchItem) {
        label = item.label
        program = item.program
        argumentsText = item.programArguments.joined(separator: "\n")
        workingDirectory = item.workingDirectory ?? ""
        calendarRows = CalendarFormRow.rows(from: item.calendarIntervals)
        useCalendar = !calendarRows.isEmpty
        useInterval = item.startInterval != nil
        let split = IntervalUnit.split(seconds: item.startInterval ?? 60)
        intervalAmount = split.amount
        intervalUnit = split.unit
        useWatchPath = !item.watchPaths.isEmpty
        watchPath = item.watchPaths.first ?? ""
        runAtLoad = item.runAtLoad
        keepAlive = item.keepAlive
        stdoutPath = item.standardOutPath ?? ""
        stderrPath = item.standardErrorPath ?? ""
        envVarRows = Self.envRows(from: item.environmentVariables)
    }

    private func validateXmlText() {
        switch plistService.validateXml(xmlText) {
        case .success:
            xmlError = nil
        case .failure(let err):
            xmlError = err.localizedDescription
        }
    }

    private func formLaunchItem() -> LaunchItem {
        let scope = existingItem?.scope ?? defaultScope
        let args = argumentsText.components(separatedBy: "\n").filter { !$0.isEmpty }
        let plistURL = existingItem?.plistURL ??
            scope.directoryURL.appendingPathComponent("\(label).plist")

        let calendars = useCalendar ? calendarRows.flatMap(\.asIntervals) : []
        let start: Int? = useInterval
            ? max(1, intervalAmount) * intervalUnit.secondsMultiplier
            : nil

        return LaunchItem(
            label: label,
            plistURL: plistURL,
            scope: scope,
            program: program,
            programArguments: args,
            calendarIntervals: calendars,
            startInterval: start,
            watchPaths: useWatchPath
                ? (watchPath.trimmingCharacters(in: .whitespaces).isEmpty ? [] : [watchPath])
                : [],
            runAtLoad: runAtLoad,
            keepAlive: keepAlive,
            standardOutPath: stdoutPath.isEmpty ? nil : stdoutPath,
            standardErrorPath: stderrPath.isEmpty ? nil : stderrPath,
            workingDirectory: workingDirectory.isEmpty ? nil : workingDirectory,
            environmentVariables: environmentVariablesFromRows,
            isLoaded: existingItem?.isLoaded ?? false,
            isDisabledByOverride: existingItem?.isDisabledByOverride ?? false,
            pid: existingItem?.pid,
            lastExitCode: existingItem?.lastExitCode
        )
    }

    private func saveItem() {
        let scope = existingItem?.scope ?? defaultScope

        if editorMode == .xml {
            guard case .success(let dict) = plistService.validateXml(xmlText),
                  let label = dict["Label"] as? String else {
                errorMessage = xmlError ?? String(localized: "Invalid plist")
                return
            }
            let plistURL = existingItem?.plistURL ??
                scope.directoryURL.appendingPathComponent("\(label).plist")
            do {
                try store.saveRawXml(xmlText, to: plistURL, scope: scope)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            return
        }

        do {
            try store.save(formLaunchItem())
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum EditorMode: String, CaseIterable {
    case form
    case xml
}

private enum IntervalUnit: String, CaseIterable, Identifiable, Hashable {
    case seconds
    case minutes
    case hours
    case days

    var id: String { rawValue }

    var secondsMultiplier: Int {
        switch self {
        case .seconds: return 1
        case .minutes: return 60
        case .hours: return 3_600
        case .days: return 86_400
        }
    }

    var localizedName: LocalizedStringKey {
        switch self {
        case .seconds: return "秒"
        case .minutes: return "分钟"
        case .hours: return "小时"
        case .days: return "天"
        }
    }

    /// Prefer the largest fixed unit that divides evenly (300 → 5 minutes).
    static func split(seconds: Int) -> (amount: Int, unit: IntervalUnit) {
        let value = max(seconds, 1)
        for unit: IntervalUnit in [.days, .hours, .minutes] where value % unit.secondsMultiplier == 0 {
            return (value / unit.secondsMultiplier, unit)
        }
        return (value, .seconds)
    }
}

private enum CalendarFrequency: Hashable {
    case daily
    case weekday(Int)
    case monthly
}

private struct EnvVarRow: Identifiable {
    let id = UUID()
    var key: String
    var value: String

    init(key: String = "", value: String = "") {
        self.key = key
        self.value = value
    }
}

private struct CalendarFormRow: Identifiable, Equatable {
    let id: UUID
    var frequency: CalendarFrequency
    var monthDay: Int
    var monthStep: Int
    var hour: Int
    var minute: Int

    init(
        id: UUID = UUID(),
        frequency: CalendarFrequency = .daily,
        monthDay: Int = 1,
        monthStep: Int = 1,
        hour: Int = 8,
        minute: Int = 0
    ) {
        self.id = id
        self.frequency = frequency
        self.monthDay = monthDay
        self.monthStep = monthStep
        self.hour = hour
        self.minute = minute
    }

    init(from interval: LaunchItem.CalendarInterval) {
        if let day = interval.day, interval.weekday == nil {
            self.init(
                frequency: .monthly,
                monthDay: day,
                monthStep: 1,
                hour: interval.hour ?? 8,
                minute: interval.minute
            )
        } else if let weekday = interval.weekday {
            self.init(
                frequency: .weekday(weekday),
                hour: interval.hour ?? 8,
                minute: interval.minute
            )
        } else {
            self.init(
                frequency: .daily,
                hour: interval.hour ?? 8,
                minute: interval.minute
            )
        }
    }

    static func rows(from intervals: [LaunchItem.CalendarInterval]) -> [CalendarFormRow] {
        if let monthly = detectMonthlyGroup(intervals) {
            var rows = monthly.remainder.map { CalendarFormRow(from: $0) }
            rows.insert(
                CalendarFormRow(
                    frequency: .monthly,
                    monthDay: monthly.day,
                    monthStep: monthly.every,
                    hour: monthly.hour,
                    minute: monthly.minute
                ),
                at: 0
            )
            return rows
        }
        return intervals.map { CalendarFormRow(from: $0) }
    }

    var asIntervals: [LaunchItem.CalendarInterval] {
        switch frequency {
        case .daily:
            return [LaunchItem.CalendarInterval(hour: hour, minute: minute)]
        case .weekday(let day):
            return [LaunchItem.CalendarInterval(weekday: day, hour: hour, minute: minute)]
        case .monthly:
            return Self.monthlyIntervals(
                every: monthStep,
                day: monthDay,
                hour: hour,
                minute: minute
            )
        }
    }

    private static func monthlyIntervals(
        every n: Int,
        day: Int,
        hour: Int,
        minute: Int
    ) -> [LaunchItem.CalendarInterval] {
        let step = min(max(n, 1), 12)
        let dom = min(max(day, 1), 31)
        let h = min(max(hour, 0), 23)
        let m = min(max(minute, 0), 59)
        if step == 1 {
            return [LaunchItem.CalendarInterval(hour: h, minute: m, day: dom)]
        }
        return stride(from: 1, through: 12, by: step).map { month in
            LaunchItem.CalendarInterval(hour: h, minute: m, day: dom, month: month)
        }
    }

    private static func detectMonthlyGroup(
        _ intervals: [LaunchItem.CalendarInterval]
    ) -> (every: Int, day: Int, hour: Int, minute: Int, remainder: [LaunchItem.CalendarInterval])? {
        var monthly: [LaunchItem.CalendarInterval] = []
        var remainder: [LaunchItem.CalendarInterval] = []
        for ci in intervals {
            if ci.day != nil, ci.weekday == nil {
                monthly.append(ci)
            } else {
                remainder.append(ci)
            }
        }
        guard !monthly.isEmpty else { return nil }

        let day = monthly[0].day!
        let hour = monthly[0].hour ?? 0
        let minute = monthly[0].minute
        guard monthly.allSatisfy({
            $0.day == day && ($0.hour ?? 0) == hour && $0.minute == minute
        }) else { return nil }

        if monthly.count == 1, monthly[0].month == nil {
            return (1, day, hour, minute, remainder)
        }

        let months = monthly.compactMap(\.month).sorted()
        guard months.count == monthly.count, let first = months.first, first == 1, months.count >= 2 else {
            return nil
        }
        let step = months[1] - months[0]
        guard step >= 1 else { return nil }
        let expected = Array(stride(from: 1, through: 12, by: step))
        guard months == expected else { return nil }
        return (step, day, hour, minute, remainder)
    }
}
