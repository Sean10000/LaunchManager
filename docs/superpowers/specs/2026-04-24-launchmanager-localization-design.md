# LaunchManager 中英双语本地化 设计文档

**日期:** 2026-04-24
**项目:** LaunchManager (macOS SwiftUI, macOS 13+)

---

## 1. 目标

所有界面文字跟随系统语言显示：系统语言为中文时显示中文，英文时显示英文。支持语言：**简体中文（zh-Hans）** + **英文（en）**。

---

## 2. 方案

使用 **Xcode String Catalog（`.xcstrings`）**，这是 Xcode 15+ 的官方本地化格式：

- 单一 JSON 文件管理所有语言，Git diff 清晰
- Xcode 可自动从代码中提取 `LocalizedStringKey` 字符串
- macOS 13+ 完全支持

**开发语言（Development Language）：简体中文（zh-Hans）**

保持代码中现有的中文字符串作为 key，无需改动 View 层的 `Text("中文")` 调用。String Catalog 存储从 zh-Hans key 到 en 译文的映射。找不到译文时回退到中文 key 本身。

---

## 3. 改动范围

### 3.1 Xcode 项目设置

在 `LaunchManager.xcodeproj` 的 Localizations 中加入 **English**（目前只有 zh-Hans）。

### 3.2 新建文件

`LaunchManager/Localizable.xcstrings` — String Catalog，包含约 80 个条目的 zh-Hans → en 翻译表。

### 3.3 Model 层改动（LaunchItem.swift）

**TriggerType：** rawValue 目前是中文字符串并直接用于 UI 显示，需拆分：

```swift
// 原来
enum TriggerType: String, CaseIterable, Hashable {
    case calendar  = "定时"
    case interval  = "间隔"
    case atLoad    = "登录时"
    case watchPath = "监视路径"
}

// 改后：rawValue 改为英文内部 key，加 localizedName 供 UI 使用
enum TriggerType: String, CaseIterable, Hashable {
    case calendar  = "calendar"
    case interval  = "interval"
    case atLoad    = "atLoad"
    case watchPath = "watchPath"

    var localizedName: LocalizedStringKey {
        switch self {
        case .calendar:  return "定时"
        case .interval:  return "间隔"
        case .atLoad:    return "登录时"
        case .watchPath: return "监视路径"
        }
    }
}
```

`localizedName` 返回的仍是中文 key，String Catalog 提供英文译文。

**Scope.directoryHint：** 返回类型从 `String` 改为 `LocalizedStringKey`，字符串内容不变，`SidebarView` 中 `Text(scope.directoryHint)` 自动获得本地化能力。

### 3.4 View 层改动

**EditAgentSheet.swift** — `Text($0.rawValue)` 改为 `Text($0.localizedName)`（1 处）。

**AgentRowView.swift** — 两处需要处理：

1. `statusTooltip: String` → `statusTooltip: LocalizedStringKey`，对应 `.help(statusTooltip)` 保持不变（SwiftUI 的 `.help()` 接受 `LocalizedStringKey`）。字符串中的插值（PID、exit code）用 `LocalizedStringKey` 的原生插值语法：
   ```swift
   var statusTooltip: LocalizedStringKey {
       if let pid = item.pid { return "运行中 (PID \(pid))" }
       ...
   }
   ```

2. `triggerDescription: String` — 包含动态值（秒数、时间、路径），改用 `String(localized:)` API（macOS 12+，本项目 macOS 13+ 满足）：
   ```swift
   case .interval:
       return String(localized: "每 \(item.startInterval ?? 0) 秒")
   ```

其余 View 文件（SidebarView、LogViewerSheet、OnboardingView、AboutView、AgentListView、InvalidPlistRowView、ContentView）中的 `Text("中文")` 已是 `LocalizedStringKey`，无需修改代码，只需 String Catalog 提供译文。

---

## 4. 翻译表（完整）

### LaunchItem.swift（Model 层）

| 中文 key | 英文译文 |
|---|---|
| 定时 | Calendar |
| 间隔 | Interval |
| 登录时 | At Login |
| 监视路径 | Watch Path |
| 用户级 · ~/Library | User · ~/Library |
| 全局 · /Library | Global · /Library |
| 系统级 · /Library | System · /Library |

### AgentRowView.swift

| 中文 key | 英文译文 |
|---|---|
| 运行中 (PID %lld) | Running (PID %lld) |
| 上次执行：正常退出 (0) | Last run: exited normally (0) |
| 已停止 (信号 %lld) | Stopped (signal %lld) |
| 上次执行：退出码 %lld | Last run: exit code %lld |
| 已加载，等待触发 | Loaded, waiting to trigger |
| 未加载 | Not loaded |
| 程序 | Program |
| 触发 | Trigger |
| 路径 | Path |
| 卸载 | Unload |
| 查看日志 | View Logs |
| 停止 | Stop |
| 启动 | Start |
| 加载 | Load |
| 确认删除 "%@"？ | Delete "%@"? |
| 此操作将 unload 并永久删除 plist 文件，无法撤销。 | This will unload and permanently delete the plist file. This cannot be undone. |
| 每 %lld 秒 | Every %lld seconds |
| 每天 | Every day |
| 周%lld | Weekday %lld |
| 登录时 | At login |
| 监视路径：%@ | Watch path: %@ |

### EditAgentSheet.swift

| 中文 key | 英文译文 |
|---|---|
| 基本信息 | Basic Info |
| Label | Label |
| 程序路径 | Program Path |
| 如 com.example.mytask | e.g. com.example.mytask |
| 如 /usr/local/bin/mytool | e.g. /usr/local/bin/mytool |
| 选择… | Choose… |
| 每行一个参数 | One argument per line |
| 触发方式 | Trigger |
| 类型 | Type |
| 星期 | Weekday |
| 每天 | Every Day |
| 周一 | Mon |
| 周二 | Tue |
| 周三 | Wed |
| 周四 | Thu |
| 周五 | Fri |
| 周六 | Sat |
| 周日 | Sun |
| 时间 | Time |
| 时 | Hour |
| 分 | Min |
| 每隔 | Every |
| 秒执行一次 | seconds |
| 监视路径 | Watch Path |
| 登录或加载时执行一次 | Run once at login or load |
| 选项 | Options |
| 加载时自动运行 | Run at Load |
| 保持存活（崩溃后自动重启）| Keep Alive (auto-restart on crash) |
| 日志路径（可选） | Log Paths (Optional) |
| 标准输出 StandardOutPath | Standard Output Path |
| 标准错误 StandardErrorPath | Standard Error Path |
| 新建 Agent | New Agent |
| 编辑 Agent | Edit Agent |
| 取消 | Cancel |
| 保存 | Save |
| 错误 | Error |
| 确定 | OK |

### LogViewerSheet.swift

| 中文 key | 英文译文 |
|---|---|
| 文件日志 | File Logs |
| 系统日志 | System Logs |
| 过滤关键字 | Filter |
| （日志为空） | (Log is empty) |
| （无日志） | (No logs) |
| 清空日志 | Clear Logs |
| 未配置日志文件路径 | No Log File Configured |
| 在编辑 Agent 时填写 StandardOutPath / StandardErrorPath 即可启用。 | Set StandardOutPath or StandardErrorPath when editing the agent. |
| 关闭 | Close |

### OnboardingView.swift

| 中文 key | 英文译文 |
|---|---|
| 欢迎使用 LaunchManager | Welcome to LaunchManager |
| macOS 定时任务与开机启动管理 | Manage macOS scheduled tasks and startup items |
| 管理启动项 | Manage Launch Items |
| 浏览 LaunchAgent 和 LaunchDaemon，无需打开终端 | Browse LaunchAgents and LaunchDaemons without a terminal |
| 自定义调度 | Custom Scheduling |
| 按时间、间隔或路径变化触发，灵活配置执行计划 | Trigger by time, interval, or path changes |
| 查看 XML | View XML |
| 直接在界面打开 plist 配置文件，一键查看原始内容 | Open plist files directly to view raw XML content |
| 加载 vs 运行 | Load vs. Running |
| 加载：launchd 登记该任务。运行：任务当前正在执行 | Load: launchd registers the task. Running: the task is currently executing. |
| 关于删除操作 | About Deletion |
| 删除 plist 仅移除自动执行配置，不影响应用本身。删除后该任务不再自动运行（如开机自启或定时执行）。系统级操作需要管理员密码授权。 | Deleting a plist only removes the automatic execution schedule — it does not affect the app itself. The task will no longer run automatically. System-level operations require administrator password. |
| 开始使用 | Get Started |

### AboutView.swift

| 中文 key | 英文译文 |
|---|---|
| 版本 %@ | Version %@ |
| macOS 定时任务与开机启动管理工具 | macOS launch item manager for scheduled tasks and startup entries |
| MIT License · 开源免费 | MIT License · Free & Open Source |
| 关闭 | Close |

### AgentListView.swift

| 中文 key | 英文译文 |
|---|---|
| 没有 Agent | No Agents |
| 此分类下暂无 LaunchAgent / Daemon | No LaunchAgents or Daemons in this category |
| 新建 | New |
| 刷新 | Refresh |
| 搜索 Label 或路径 | Search by label or path |

### InvalidPlistRowView.swift

| 中文 key | 英文译文 |
|---|---|
| ⚠️ 无法解析 | ⚠️ Invalid |
| 路径 | Path |
| 此文件为空或格式无效，无法作为 launchd 条目加载。 | This file is empty or has an invalid format and cannot be loaded as a launchd entry. |
| 此操作将永久删除该 plist 文件，无法撤销。 | This will permanently delete the plist file. This cannot be undone. |
| 删除 | Delete |

### ContentView.swift / LaunchManagerApp.swift

| 中文 key | 英文译文 |
|---|---|
| 错误 | Error |
| 确定 | OK |
| 关于 LaunchManager | About LaunchManager |

---

## 5. 不在本次范围

- 繁体中文、日文等其他语言
- 错误信息（`LocalizedError.errorDescription`，来自 Service 层）
- 系统 API 谓词字符串（`subsystem ==` 等传给 `log` 命令的参数）

---

## 6. 文件变动清单

| 文件 | 改动 |
|---|---|
| `LaunchManager.xcodeproj/project.pbxproj` | 添加 English localization |
| `LaunchManager/Localizable.xcstrings`（新建）| ~80 条 zh-Hans→en 翻译 |
| `Models/LaunchItem.swift` | `TriggerType` rawValue → 英文 key + `localizedName`；`Scope.directoryHint` 返回 `LocalizedStringKey` |
| `Views/AgentRowView.swift` | `statusTooltip` 改为 `LocalizedStringKey`；`triggerDescription` 用 `String(localized:)` |
| `Views/EditAgentSheet.swift` | `Text($0.rawValue)` → `Text($0.localizedName)` |
