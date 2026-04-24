import SwiftUI

struct EditAgentSheet: View {
    let existingItem: LaunchItem?
    let defaultScope: LaunchItem.Scope
    @ObservedObject var store: AgentStore
    @Environment(\.dismiss) private var dismiss

    @State private var label: String
    @State private var program: String
    @State private var argumentsText: String
    @State private var triggerType: LaunchItem.TriggerType
    @State private var weekday: Int?
    @State private var hour: Int
    @State private var minute: Int
    @State private var startInterval: Int
    @State private var watchPath: String
    @State private var runAtLoad: Bool
    @State private var keepAlive: Bool
    @State private var stdoutPath: String
    @State private var stderrPath: String
    @State private var errorMessage: String?

    init(existingItem: LaunchItem?, defaultScope: LaunchItem.Scope, store: AgentStore) {
        self.existingItem = existingItem
        self.defaultScope = defaultScope
        self.store = store
        let i = existingItem
        _label         = State(initialValue: i?.label ?? "")
        _program       = State(initialValue: i?.program ?? "")
        _argumentsText = State(initialValue: i?.programArguments.joined(separator: "\n") ?? "")
        _triggerType   = State(initialValue: i?.triggerType ?? .atLoad)
        _weekday       = State(initialValue: i?.calendarInterval?.weekday)
        _hour          = State(initialValue: i?.calendarInterval?.hour ?? 8)
        _minute        = State(initialValue: i?.calendarInterval?.minute ?? 0)
        _startInterval = State(initialValue: i?.startInterval ?? 60)
        _watchPath     = State(initialValue: i?.watchPaths.first ?? "")
        _runAtLoad     = State(initialValue: i?.runAtLoad ?? false)
        _keepAlive     = State(initialValue: i?.keepAlive ?? false)
        _stdoutPath    = State(initialValue: i?.standardOutPath ?? "")
        _stderrPath    = State(initialValue: i?.standardErrorPath ?? "")
    }

    var body: some View {
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
                }
            }

            Section("触发方式") {
                Picker("类型", selection: $triggerType) {
                    ForEach(LaunchItem.TriggerType.allCases, id: \.self) {
                        Text($0.localizedName).tag($0)
                    }
                }
                .pickerStyle(.segmented)

                switch triggerType {
                case .calendar:
                    HStack {
                        Text("星期")
                        Picker("", selection: $weekday) {
                            Text("每天").tag(Int?.none)
                            ForEach(1...7, id: \.self) { d in
                                Text(["", "周一", "周二", "周三", "周四", "周五", "周六", "周日"][d])
                                    .tag(Int?.some(d))
                            }
                        }
                        .frame(width: 80)
                        Spacer()
                        Text("时间")
                        TextField("时", value: $hour, format: .number).frame(width: 44)
                        Text(":")
                        TextField("分", value: $minute, format: .number).frame(width: 44)
                    }
                case .interval:
                    HStack {
                        Text("每隔")
                        TextField("秒", value: $startInterval, format: .number).frame(width: 80)
                        Text("秒执行一次")
                    }
                case .watchPath:
                    TextField("监视路径", text: $watchPath)
                case .atLoad:
                    Text("登录或加载时执行一次").foregroundStyle(.secondary)
                }
            }

            Section("选项") {
                Toggle("加载时自动运行", isOn: $runAtLoad)
                Toggle("保持存活（崩溃后自动重启）", isOn: $keepAlive)
            }

            Section("日志路径（可选）") {
                TextField("标准输出 StandardOutPath", text: $stdoutPath)
                TextField("标准错误 StandardErrorPath", text: $stderrPath)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, minHeight: 360)
        .navigationTitle(existingItem == nil ? "新建 Agent" : "编辑 Agent")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { saveItem() }
                    .disabled(label.isEmpty || program.isEmpty)
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
    }

    private func pickProgram() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            program = url.path
        }
    }

    private func saveItem() {
        let scope    = existingItem?.scope ?? defaultScope
        let args     = argumentsText.components(separatedBy: "\n").filter { !$0.isEmpty }
        let plistURL = existingItem?.plistURL ??
            scope.directoryURL.appendingPathComponent("\(label).plist")

        let item = LaunchItem(
            label: label, plistURL: plistURL, scope: scope,
            program: program, programArguments: args,
            triggerType: triggerType,
            calendarInterval: triggerType == .calendar
                ? LaunchItem.CalendarInterval(weekday: weekday, hour: hour, minute: minute)
                : nil,
            startInterval: triggerType == .interval ? startInterval : nil,
            watchPaths: triggerType == .watchPath ? [watchPath] : [],
            runAtLoad: runAtLoad, keepAlive: keepAlive,
            standardOutPath:   stdoutPath.isEmpty  ? nil : stdoutPath,
            standardErrorPath: stderrPath.isEmpty  ? nil : stderrPath,
            isLoaded: existingItem?.isLoaded ?? false,
            pid: existingItem?.pid,
            lastExitCode: existingItem?.lastExitCode
        )
        do {
            try store.save(item)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
