# LaunchManager 中英双语本地化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 所有界面文字跟随系统语言，支持简体中文（zh-Hans）和英文（en）。

**Architecture:** 使用 Xcode String Catalog（`.xcstrings`），以中文字符串为 key，String Catalog 提供英文译文。Model 层 `TriggerType.rawValue` 改为英文 key 并加 `localizedName`；`Scope.directoryHint` 返回 `LocalizedStringKey`；`AgentRowView` 的动态字符串用 `LocalizedStringKey`/`String(localized:)` 处理。其余 View 层代码无需改动。

**Tech Stack:** SwiftUI `LocalizedStringKey`, `String(localized:)` (macOS 12+), Xcode String Catalog `.xcstrings`

---

### Task 1: 添加 English localization 到 Xcode 项目

**Files:**
- Modify: `LaunchManager.xcodeproj/project.pbxproj`

- [ ] **Step 1: 定位 knownRegions**

```bash
grep -n "knownRegions\|developmentRegion" LaunchManager.xcodeproj/project.pbxproj
```

找到类似：
```
developmentRegion = "zh-Hans";
...
knownRegions = (
    "zh-Hans",
    Base,
);
```

- [ ] **Step 2: 添加 en**

将 `knownRegions` 改为（`developmentRegion` 保持 `zh-Hans` 不变）：
```
knownRegions = (
    en,
    "zh-Hans",
    Base,
);
```

- [ ] **Step 3: 编译验证**

```bash
xcodebuild -project LaunchManager.xcodeproj -scheme LaunchManager -configuration Debug build 2>&1 | grep -E "error:|Build succeeded|Build FAILED"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add LaunchManager.xcodeproj/project.pbxproj
git commit -m "chore: add English to project localizations"
```

---

### Task 2: 新建 Localizable.xcstrings 并注册到项目

**Files:**
- Create: `LaunchManager/Localizable.xcstrings`
- Modify: `LaunchManager.xcodeproj/project.pbxproj`

- [ ] **Step 1: 创建 String Catalog 文件**

将以下内容写入 `LaunchManager/Localizable.xcstrings`（完整、无占位条目）：

```json
{
  "sourceLanguage" : "zh-Hans",
  "strings" : {
    "（日志为空）" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "(Log is empty)" } } }
    },
    "（无日志）" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "(No logs)" } } }
    },
    "上次执行：正常退出 (0)" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Last run: exited normally (0)" } } }
    },
    "上次执行：退出码 %lld" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Last run: exit code %lld" } } }
    },
    "MIT License · 开源免费" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "MIT License · Free & Open Source" } } }
    },
    "卸载" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Unload" } } }
    },
    "删除" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Delete" } } }
    },
    "删除 plist 仅移除自动执行配置，不影响应用本身。删除后该任务不再自动运行（如开机自启或定时执行）。系统级操作需要管理员密码授权。" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Deleting a plist only removes the automatic execution schedule — it does not affect the app itself. The task will no longer run automatically. System-level operations require administrator password." } } }
    },
    "保存" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Save" } } }
    },
    "保持存活（崩溃后自动重启）" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Keep Alive (auto-restart on crash)" } } }
    },
    "停止" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Stop" } } }
    },
    "全局 · /Library" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Global · /Library" } } }
    },
    "分" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Min" } } }
    },
    "刷新" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Refresh" } } }
    },
    "加载" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Load" } } }
    },
    "加载 vs 运行" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Load vs. Running" } } }
    },
    "加载：launchd 登记该任务。运行：任务当前正在执行" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Load: launchd registers the task. Running: the task is currently executing." } } }
    },
    "加载时自动运行" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Run at Load" } } }
    },
    "取消" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Cancel" } } }
    },
    "在编辑 Agent 时填写 StandardOutPath / StandardErrorPath 即可启用。" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Set StandardOutPath or StandardErrorPath when editing the agent." } } }
    },
    "基本信息" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Basic Info" } } }
    },
    "定时" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Calendar" } } }
    },
    "已加载，等待触发" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Loaded, waiting to trigger" } } }
    },
    "已停止 (信号 %lld)" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Stopped (signal %lld)" } } }
    },
    "开始使用" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Get Started" } } }
    },
    "关于 LaunchManager" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "About LaunchManager" } } }
    },
    "关于删除操作" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "About Deletion" } } }
    },
    "关闭" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Close" } } }
    },
    "其" : { "comment" : "unused — intentionally omitted" },
    "启动" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Start" } } }
    },
    "如 /usr/local/bin/mytool" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "e.g. /usr/local/bin/mytool" } } }
    },
    "如 com.example.mytask" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "e.g. com.example.mytask" } } }
    },
    "媒体" : { "comment" : "unused — intentionally omitted" },
    "嗯" : { "comment" : "unused — intentionally omitted" },
    "大" : { "comment" : "unused — intentionally omitted" },
    "日志 — %@" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Logs — %@" } } }
    },
    "日志路径（可选）" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Log Paths (Optional)" } } }
    },
    "时" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Hour" } } }
    },
    "时间" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Time" } } }
    },
    "星期" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Weekday" } } }
    },
    "未加载" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Not loaded" } } }
    },
    "未配置日志文件路径" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "No Log File Configured" } } }
    },
    "查看 XML" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "View XML" } } }
    },
    "查看日志" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "View Logs" } } }
    },
    "标准输出 StandardOutPath" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Standard Output Path" } } }
    },
    "标准错误 StandardErrorPath" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Standard Error Path" } } }
    },
    "欢迎使用 LaunchManager" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Welcome to LaunchManager" } } }
    },
    "版本 %@" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Version %@" } } }
    },
    "用户级 · ~/Library" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "User · ~/Library" } } }
    },
    "登录时" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "At Login" } } }
    },
    "登录或加载时执行一次" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Run once at login or load" } } }
    },
    "确定" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "OK" } } }
    },
    "确认删除 %@？" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Delete %@?" } } }
    },
    "程序" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Program" } } }
    },
    "程序路径" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Program Path" } } }
    },
    "系统级 · /Library" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "System · /Library" } } }
    },
    "管理启动项" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Manage Launch Items" } } }
    },
    "类型" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Type" } } }
    },
    "编辑 Agent" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Edit Agent" } } }
    },
    "自定义调度" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Custom Scheduling" } } }
    },
    "触发" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Trigger" } } }
    },
    "触发方式" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Trigger" } } }
    },
    "路径" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Path" } } }
    },
    "运行中 (PID %lld)" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Running (PID %lld)" } } }
    },
    "选择…" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Choose…" } } }
    },
    "选项" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Options" } } }
    },
    "间隔" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Interval" } } }
    },
    "错误" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Error" } } }
    },
    "监视路径" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Watch Path" } } }
    },
    "监视路径：%@" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Watch path: %@" } } }
    },
    "直接在界面打开 plist 配置文件，一键查看原始内容" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Open plist files directly to view raw XML content" } } }
    },
    "系统日志" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "System Logs" } } }
    },
    "文件日志" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "File Logs" } } }
    },
    "浏览 LaunchAgent 和 LaunchDaemon，无需打开终端" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Browse LaunchAgents and LaunchDaemons without a terminal" } } }
    },
    "没有 Agent" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "No Agents" } } }
    },
    "清空日志" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Clear Logs" } } }
    },
    "每 %lld 秒" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Every %lld seconds" } } }
    },
    "每天" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Every day" } } }
    },
    "每行一个参数" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "One argument per line" } } }
    },
    "每隔" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Every" } } }
    },
    "此分类下暂无 LaunchAgent / Daemon" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "No LaunchAgents or Daemons in this category" } } }
    },
    "此文件为空或格式无效，无法作为 launchd 条目加载。" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "This file is empty or has an invalid format and cannot be loaded as a launchd entry." } } }
    },
    "此操作将 unload 并永久删除 plist 文件，无法撤销。" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "This will unload and permanently delete the plist file. This cannot be undone." } } }
    },
    "此操作将永久删除该 plist 文件，无法撤销。" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "This will permanently delete the plist file. This cannot be undone." } } }
    },
    "按时间、间隔或路径变化触发，灵活配置执行计划" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Trigger by time, interval, or path changes" } } }
    },
    "新建" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "New" } } }
    },
    "新建 Agent" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "New Agent" } } }
    },
    "秒执行一次" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "seconds" } } }
    },
    "搜索 Label 或路径" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Search by label or path" } } }
    },
    "macOS 定时任务与开机启动管理" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Manage macOS scheduled tasks and startup items" } } }
    },
    "macOS 定时任务与开机启动管理工具" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "macOS launch item manager for scheduled tasks and startup entries" } } }
    },
    "过滤关键字" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Filter" } } }
    },
    "周一" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Mon" } } }
    },
    "周二" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Tue" } } }
    },
    "周三" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Wed" } } }
    },
    "周四" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Thu" } } }
    },
    "周五" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Fri" } } }
    },
    "周六" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Sat" } } }
    },
    "周日" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Sun" } } }
    },
    "周%lld" : {
      "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Weekday %lld" } } }
    }
  },
  "version" : "1.0"
}
```

- [ ] **Step 2: 将 Localizable.xcstrings 注册到 Xcode 项目**

最可靠的方法：在 Xcode 中 **File → New → File → String Catalog**，命名 `Localizable`，保存到 `LaunchManager/` 目录，Xcode 自动处理 `project.pbxproj`。然后用以下命令替换自动生成的空内容：

```bash
# 验证 Xcode 已在正确位置创建了文件
ls LaunchManager/Localizable.xcstrings
```

若文件存在，用 Write 工具将 Step 1 的 JSON 内容覆盖写入该文件。

若要手动编辑 `project.pbxproj`（不推荐），参考已有 `.swift` 文件的 PBXBuildFile/PBXFileReference 格式，为 `Localizable.xcstrings` 添加对应条目，`lastKnownFileType = text.json.xcstrings`。

- [ ] **Step 3: 编译验证**

```bash
xcodebuild -project LaunchManager.xcodeproj -scheme LaunchManager -configuration Debug build 2>&1 | grep -E "error:|Build succeeded|Build FAILED"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add LaunchManager/Localizable.xcstrings LaunchManager.xcodeproj/project.pbxproj
git commit -m "feat: add Localizable.xcstrings with zh-Hans→en translations (~80 strings)"
```

---

### Task 3: 更新 LaunchItem.swift（Model 层）

**Files:**
- Modify: `LaunchManager/Models/LaunchItem.swift`

- [ ] **Step 1: TriggerType — rawValue 改英文 key，加 localizedName**

找到（约第 57-62 行）：
```swift
enum TriggerType: String, CaseIterable, Hashable {
    case calendar  = "定时"
    case interval  = "间隔"
    case atLoad    = "登录时"
    case watchPath = "监视路径"
}
```

替换为：
```swift
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

- [ ] **Step 2: Scope.directoryHint — 返回类型改为 LocalizedStringKey**

找到（约第 34-40 行）：
```swift
var directoryHint: String {
    switch self {
    case .userAgent:    return "用户级 · ~/Library"
    case .systemAgent:  return "全局 · /Library"
    case .systemDaemon: return "系统级 · /Library"
    }
}
```

替换为：
```swift
var directoryHint: LocalizedStringKey {
    switch self {
    case .userAgent:    return "用户级 · ~/Library"
    case .systemAgent:  return "全局 · /Library"
    case .systemDaemon: return "系统级 · /Library"
    }
}
```

- [ ] **Step 3: 编译验证**

```bash
xcodebuild -project LaunchManager.xcodeproj -scheme LaunchManager -configuration Debug build 2>&1 | grep -E "error:|Build succeeded|Build FAILED"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add LaunchManager/Models/LaunchItem.swift
git commit -m "feat: localize TriggerType display names and Scope.directoryHint"
```

---

### Task 4: 更新 EditAgentSheet.swift

**Files:**
- Modify: `LaunchManager/Views/EditAgentSheet.swift`

- [ ] **Step 1: Text($0.rawValue) → Text($0.localizedName)**

找到：
```swift
ForEach(LaunchItem.TriggerType.allCases, id: \.self) {
    Text($0.rawValue).tag($0)
}
```

替换为：
```swift
ForEach(LaunchItem.TriggerType.allCases, id: \.self) {
    Text($0.localizedName).tag($0)
}
```

- [ ] **Step 2: 编译验证**

```bash
xcodebuild -project LaunchManager.xcodeproj -scheme LaunchManager -configuration Debug build 2>&1 | grep -E "error:|Build succeeded|Build FAILED"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add LaunchManager/Views/EditAgentSheet.swift
git commit -m "feat: use localizedName for TriggerType picker in EditAgentSheet"
```

---

### Task 5: 更新 AgentRowView.swift

**Files:**
- Modify: `LaunchManager/Views/AgentRowView.swift`

- [ ] **Step 1: statusTooltip — String 改为 LocalizedStringKey**

找到：
```swift
var statusTooltip: String {
    if item.pid != nil { return "运行中 (PID \(item.pid!))" }
    if let code = item.lastExitCode {
        if code == 0  { return "上次执行：正常退出 (0)" }
        if code < 0   { return "已停止 (信号 \(-code))" }
        return "上次执行：退出码 \(code)"
    }
    return item.isLoaded ? "已加载，等待触发" : "未加载"
}
```

替换为：
```swift
var statusTooltip: LocalizedStringKey {
    if let pid = item.pid { return "运行中 (PID \(pid))" }
    if let code = item.lastExitCode {
        if code == 0  { return "上次执行：正常退出 (0)" }
        if code < 0   { return "已停止 (信号 \(-code))" }
        return "上次执行：退出码 \(code)"
    }
    return item.isLoaded ? "已加载，等待触发" : "未加载"
}
```

- [ ] **Step 2: triggerDescription — 用 String(localized:)**

找到：
```swift
private var triggerDescription: String {
    switch item.triggerType {
    case .calendar:
        guard let ci = item.calendarInterval else { return "定时" }
        let day = ci.weekday.map { "周\($0)" } ?? "每天"
        let h   = ci.hour.map { String(format: "%02d", $0) } ?? "每小时"
        return "\(day) \(h):\(String(format: "%02d", ci.minute))"
    case .interval:
        return "每 \(item.startInterval ?? 0) 秒"
    case .atLoad:
        return "登录时"
    case .watchPath:
        return "监视路径：\(item.watchPaths.first ?? "")"
    }
}
```

替换为：
```swift
private var triggerDescription: String {
    switch item.triggerType {
    case .calendar:
        guard let ci = item.calendarInterval else {
            return String(localized: "定时")
        }
        let day = ci.weekday.map { String(localized: "周\($0)") }
                ?? String(localized: "每天")
        let h = ci.hour.map { String(format: "%02d", $0) } ?? "**"
        return "\(day) \(h):\(String(format: "%02d", ci.minute))"
    case .interval:
        return String(localized: "每 \(item.startInterval ?? 0) 秒")
    case .atLoad:
        return String(localized: "登录时")
    case .watchPath:
        return String(localized: "监视路径：\(item.watchPaths.first ?? "")")
    }
}
```

- [ ] **Step 3: 编译验证**

```bash
xcodebuild -project LaunchManager.xcodeproj -scheme LaunchManager -configuration Debug build 2>&1 | grep -E "error:|Build succeeded|Build FAILED"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add LaunchManager/Views/AgentRowView.swift
git commit -m "feat: localize statusTooltip and triggerDescription in AgentRowView"
```

---

### Task 6: 手动测试

- [ ] **Step 1: 切换系统语言为英文**

System Settings → General → Language & Region → 将 English 拖到列表首位。退出并重新运行 LaunchManager（不需要重启系统）。

- [ ] **Step 2: 验证清单**

| 界面 | 验证点 |
|---|---|
| Sidebar | scope hint 显示 "User · ~/Library"、"Global · /Library"、"System · /Library" |
| 列表行 hover | tooltip 显示英文（"Running (PID …)"、"Not loaded" 等）|
| 列表行展开 | Program / Trigger / Path 标签英文 |
| 列表行展开 | 触发描述英文（"Every 300 seconds"、"At Login" 等）|
| 新建/编辑表单 | Section 标题 Basic Info / Trigger / Options 等英文 |
| Picker | Calendar / Interval / At Login / Watch Path |
| 删除确认弹窗 | "Delete …?" 和 "This will unload…" 英文 |
| Onboarding | 全英文 |
| About | "Version 1.2.0" |
| 日志查看器 | File Logs / System Logs / Filter / Clear Logs |
| ContentUnavailableView | "No Agents" |

- [ ] **Step 3: 切回中文验证**

将系统语言改回中文简体，重启 App，确认所有界面仍显示中文（key 本身即中文，无需译文，自动回退正确）。
