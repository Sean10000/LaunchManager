import SwiftUI

struct EditCronSheet: View {
    let existingJob: CronJob?
    let scope: CrontabScope
    @ObservedObject var store: CrontabStore
    @Binding var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    @State private var preset: SchedulePreset
    @State private var minute: String
    @State private var hour: String
    @State private var dayOfMonth: String
    @State private var month: String
    @State private var weekday: String
    @State private var runAsUser: String
    @State private var command: String
    @State private var isEnabled: Bool

    init(
        existingJob: CronJob?,
        scope: CrontabScope,
        store: CrontabStore,
        errorMessage: Binding<String?>
    ) {
        self.existingJob = existingJob
        self.scope = existingJob?.scope ?? scope
        self.store = store
        _errorMessage = errorMessage

        let job = existingJob
        _minute = State(initialValue: job?.minute ?? "0")
        _hour = State(initialValue: job?.hour ?? "8")
        _dayOfMonth = State(initialValue: job?.dayOfMonth ?? "*")
        _month = State(initialValue: job?.month ?? "*")
        _weekday = State(initialValue: job?.weekday ?? "*")
        _runAsUser = State(initialValue: job?.runAsUser ?? NSUserName())
        _command = State(initialValue: job?.command ?? "")
        _isEnabled = State(initialValue: job?.isEnabled ?? true)
        _preset = State(initialValue: SchedulePreset.detect(
            minute: job?.minute ?? "0",
            hour: job?.hour ?? "8",
            dayOfMonth: job?.dayOfMonth ?? "*",
            month: job?.month ?? "*",
            weekday: job?.weekday ?? "*"
        ))
    }

    var body: some View {
        Form {
            Section("计划") {
                Picker("频率", selection: $preset) {
                    ForEach(SchedulePreset.allCases, id: \.self) { value in
                        Text(value.title).tag(value)
                    }
                }
                .onChange(of: preset) { _, newValue in
                    applyPreset(newValue)
                }

                switch preset {
                case .everyMinute:
                    EmptyView()
                case .hourly:
                    StepperField(title: "分钟", value: $minute, range: 0...59)
                case .daily:
                    StepperField(title: "小时", value: $hour, range: 0...23)
                    StepperField(title: "分钟", value: $minute, range: 0...59)
                case .weekly:
                    Picker("星期", selection: $weekday) {
                        ForEach(WeekdayOption.allCases) { option in
                            Text(option.title).tag(option.value)
                        }
                    }
                    StepperField(title: "小时", value: $hour, range: 0...23)
                    StepperField(title: "分钟", value: $minute, range: 0...59)
                case .monthly:
                    StepperField(title: "日期", value: $dayOfMonth, range: 1...31)
                    StepperField(title: "小时", value: $hour, range: 0...23)
                    StepperField(title: "分钟", value: $minute, range: 0...59)
                case .custom:
                    TextField("分钟", text: $minute)
                    TextField("小时", text: $hour)
                    TextField("日", text: $dayOfMonth)
                    TextField("月", text: $month)
                    TextField("星期", text: $weekday)
                }

                Text(previewSchedule)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("命令") {
                if scope == .system {
                    TextField("运行用户", text: $runAsUser)
                        .font(.system(.body, design: .monospaced))
                }
                TextField("要执行的命令", text: $command, axis: .vertical)
                    .lineLimit(2...6)
                    .font(.system(.body, design: .monospaced))
                Toggle("启用", isOn: $isEnabled)
            }

            if scope.requiresPrivilege {
                Section {
                    Text("保存时将提示输入管理员密码，与系统 LaunchAgent 写入方式相同。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 460, minHeight: 360)
        .navigationTitle(existingJob == nil ? "新建 Cron 任务" : "编辑 Cron 任务")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { save() }
                    .disabled(!canSave)
            }
        }
    }

    private var canSave: Bool {
        let hasUser = scope == .user || !runAsUser.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasUser &&
        !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        [minute, hour, dayOfMonth, month, weekday].allSatisfy { !$0.isEmpty }
    }

    private var previewSchedule: String {
        CronScheduleDescriber.describe(
            minute: minute,
            hour: hour,
            dayOfMonth: dayOfMonth,
            month: month,
            weekday: weekday
        )
    }

    private func applyPreset(_ preset: SchedulePreset) {
        switch preset {
        case .everyMinute:
            minute = "*"; hour = "*"; dayOfMonth = "*"; month = "*"; weekday = "*"
        case .hourly:
            hour = "*"; dayOfMonth = "*"; month = "*"; weekday = "*"
            if minute == "*" { minute = "0" }
        case .daily:
            dayOfMonth = "*"; month = "*"; weekday = "*"
            if hour == "*" { hour = "8" }
            if minute == "*" { minute = "0" }
        case .weekly:
            dayOfMonth = "*"; month = "*"
            if weekday == "*" { weekday = "1" }
            if hour == "*" { hour = "8" }
            if minute == "*" { minute = "0" }
        case .monthly:
            month = "*"; weekday = "*"
            if dayOfMonth == "*" { dayOfMonth = "1" }
            if hour == "*" { hour = "8" }
            if minute == "*" { minute = "0" }
        case .custom:
            break
        }
    }

    private func save() {
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUser = runAsUser.trimmingCharacters(in: .whitespacesAndNewlines)
        let job = CronJob(
            id: existingJob?.id ?? UUID(),
            scope: scope,
            minute: minute,
            hour: hour,
            dayOfMonth: dayOfMonth,
            month: month,
            weekday: weekday,
            runAsUser: scope == .system ? trimmedUser : nil,
            command: trimmedCommand,
            isEnabled: isEnabled
        )
        do {
            try store.save(job: job, replacing: existingJob?.id)
            dismiss()
        } catch PrivilegeError.cancelled {
            // user dismissed admin dialog
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum SchedulePreset: CaseIterable {
    case everyMinute
    case hourly
    case daily
    case weekly
    case monthly
    case custom

    var title: LocalizedStringKey {
        switch self {
        case .everyMinute: return "每分钟"
        case .hourly: return "每小时"
        case .daily: return "每天"
        case .weekly: return "每周"
        case .monthly: return "每月"
        case .custom: return "自定义"
        }
    }

    static func detect(
        minute: String,
        hour: String,
        dayOfMonth: String,
        month: String,
        weekday: String
    ) -> SchedulePreset {
        if minute == "*" && hour == "*" && dayOfMonth == "*" && month == "*" && weekday == "*" {
            return .everyMinute
        }
        if hour == "*" && dayOfMonth == "*" && month == "*" && weekday == "*" {
            return .hourly
        }
        if dayOfMonth == "*" && month == "*" && weekday == "*" {
            return .daily
        }
        if dayOfMonth == "*" && month == "*" && weekday != "*" {
            return .weekly
        }
        if month == "*" && weekday == "*" && dayOfMonth != "*" {
            return .monthly
        }
        return .custom
    }
}

private struct WeekdayOption: Identifiable {
    let value: String
    let title: LocalizedStringKey
    var id: String { value }

    static let allCases: [WeekdayOption] = [
        WeekdayOption(value: "1", title: "周一"),
        WeekdayOption(value: "2", title: "周二"),
        WeekdayOption(value: "3", title: "周三"),
        WeekdayOption(value: "4", title: "周四"),
        WeekdayOption(value: "5", title: "周五"),
        WeekdayOption(value: "6", title: "周六"),
        WeekdayOption(value: "0", title: "周日"),
    ]
}

private struct StepperField: View {
    let title: LocalizedStringKey
    @Binding var value: String
    let range: ClosedRange<Int>

    private var intValue: Int {
        Int(value) ?? range.lowerBound
    }

    var body: some View {
        Stepper(value: Binding(
            get: { intValue },
            set: { value = String($0) }
        ), in: range) {
            HStack {
                Text(title)
                Spacer()
                Text(value)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }
}
