import Foundation

enum LaunchctlErrorFormatter {
    static func message(operation: String, detail: String) -> String {
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return String(localized: "\(operation)失败")
        }
        let hint = friendlyHint(for: trimmed)
        if let hint {
            return String(localized: "\(operation)失败：\(hint)\n\n\(trimmed)")
        }
        return String(localized: "\(operation)失败：\(trimmed)")
    }

    private static func friendlyHint(for detail: String) -> String? {
        let lower = detail.lowercased()
        if lower.contains("input/output error") || lower.contains("operation not permitted") {
            return String(localized: "权限不足或路径无法访问")
        }
        if lower.contains("no such file") || lower.contains("not found") {
            return String(localized: "文件或路径不存在")
        }
        if lower.contains("service already loaded") || lower.contains("already loaded") {
            return String(localized: "服务已载入")
        }
        if lower.contains("not loaded") || lower.contains("no such process") {
            return String(localized: "服务未载入或已停止")
        }
        if lower.contains("bootstrap failed") {
            return String(localized: "plist 无法载入，请检查语法与路径")
        }
        if lower.contains("permission denied") {
            return String(localized: "权限被拒绝")
        }
        return nil
    }
}

extension ShellError {
    var launchctlUserMessage: String {
        if case .nonZeroExit(_, let output) = self {
            return output
        }
        return localizedDescription
    }
}
