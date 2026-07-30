import Foundation

struct CronJob: Identifiable, Hashable {
    let id: UUID
    var scope: CrontabScope
    var minute: String
    var hour: String
    var dayOfMonth: String
    var month: String
    var weekday: String
    var runAsUser: String?
    var command: String
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        scope: CrontabScope = .user,
        minute: String,
        hour: String,
        dayOfMonth: String,
        month: String,
        weekday: String,
        runAsUser: String? = nil,
        command: String,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.scope = scope
        self.minute = minute
        self.hour = hour
        self.dayOfMonth = dayOfMonth
        self.month = month
        self.weekday = weekday
        self.runAsUser = runAsUser
        self.command = command
        self.isEnabled = isEnabled
    }

    var scheduleFields: [String] {
        [minute, hour, dayOfMonth, month, weekday]
    }

    var scheduleDescription: String {
        CronScheduleDescriber.describe(
            minute: minute,
            hour: hour,
            dayOfMonth: dayOfMonth,
            month: month,
            weekday: weekday
        )
    }
}

enum CrontabLine: Identifiable, Hashable {
    case blank(id: UUID)
    case comment(id: UUID, text: String)
    case environment(id: UUID, key: String, value: String)
    case job(CronJob)
    case raw(id: UUID, line: String)

    var id: UUID {
        switch self {
        case .blank(let id), .comment(let id, _), .environment(let id, _, _), .raw(let id, _):
            return id
        case .job(let job):
            return job.id
        }
    }
}

enum CronScheduleDescriber {
    static func describe(
        minute: String,
        hour: String,
        dayOfMonth: String,
        month: String,
        weekday: String
    ) -> String {
        let m = minute, h = hour, dom = dayOfMonth, mon = month, dow = weekday

        if m == "*" && h == "*" && dom == "*" && mon == "*" && dow == "*" {
            return String(localized: "每分钟")
        }
        if m == "0" && h == "*" && dom == "*" && mon == "*" && dow == "*" {
            return String(localized: "每小时整点")
        }
        if dom == "*" && mon == "*" && dow == "*" && h != "*" && m != "*" {
            return String(localized: "每天 \(h):\(pad(m))")
        }
        if dom == "*" && mon == "*" && h != "*" && m != "*" && dow != "*" {
            let day = weekdayName(dow) ?? "周\(dow)"
            return String(localized: "每\(day) \(h):\(pad(m))")
        }
        if dow == "*" && mon == "*" && h != "*" && m != "*" && dom != "*" {
            return String(localized: "每月 \(dom) 日 \(h):\(pad(m))")
        }
        return "\(m) \(h) \(dom) \(mon) \(dow)"
    }

    private static func pad(_ value: String) -> String {
        value.count == 1 ? "0\(value)" : value
    }

    private static func weekdayName(_ value: String) -> String? {
        switch value {
        case "0", "7": return String(localized: "周日")
        case "1": return String(localized: "周一")
        case "2": return String(localized: "周二")
        case "3": return String(localized: "周三")
        case "4": return String(localized: "周四")
        case "5": return String(localized: "周五")
        case "6": return String(localized: "周六")
        default: return nil
        }
    }
}
