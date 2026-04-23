# 表单 UX 改进 + 删除双密码 Bug 修复 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复删除 System plist 弹两次密码的 bug，并改进 EditAgentSheet 表单的必填字段视觉区分。

**Architecture:** 两个独立改动：PlistService.delete() 合并 privileged 路径的两条 shell 命令为一次调用；EditAgentSheet 提取 requiredField ViewBuilder，为 Label 和 Program 字段加蓝色边框和红色星号。

**Tech Stack:** Swift 5.10, SwiftUI, XCTest

---

## File Map

| 操作 | 文件 | 改动内容 |
|------|------|----------|
| Modify | `LaunchManager/Services/PlistService.swift:124-133` | 合并 privileged delete 为单次 privilege.run() |
| Modify | `LaunchManager/Views/EditAgentSheet.swift` | 添加 requiredField helper，更新 Label/Program 字段样式 |
| Modify | `LaunchManagerTests/LaunchManagerTests.swift` | 添加 delete 非特权路径测试 |

---

### Task 1: 修复 PlistService.delete() 双密码 Bug

**Files:**
- Modify: `LaunchManager/Services/PlistService.swift:124-133`
- Modify: `LaunchManagerTests/LaunchManagerTests.swift`

- [ ] **Step 1: 写失败测试（验证 delete 非特权路径正确删除文件）**

在 `LaunchManagerTests/LaunchManagerTests.swift` 末尾 `PlistServiceTests` class 内追加：

```swift
func test_delete_nonPrivileged_removesFile() throws {
    let plist = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict>
        <key>Label</key><string>com.test.delete</string>
        <key>Program</key><string>/bin/echo</string>
    </dict></plist>
    """
    let url = tmpDir.appendingPathComponent("com.test.delete.plist")
    try plist.write(to: url, atomically: true, encoding: .utf8)
    let item = svc.parsePlist(at: url, scope: .userAgent)!

    struct NoopShell: ShellRunner {
        func run(_ path: String, arguments: [String]) throws -> String { "" }
    }
    let launchctl = LaunchctlService(shell: NoopShell())
    try svc.delete(item, launchctl: launchctl, privilege: PrivilegeService())

    XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
}
```

- [ ] **Step 2: 运行测试，确认通过**（非特权路径现有实现已正确，测试应 PASS）

```bash
cd /Users/sean/LaunchManager/LaunchManager
xcodebuild test -project LaunchManager.xcodeproj -scheme LaunchManager -destination 'platform=macOS' -only-testing:LaunchManagerTests/PlistServiceTests/test_delete_nonPrivileged_removesFile 2>&1 | grep -E "passed|failed|error:"
```

预期：`passed`

- [ ] **Step 3: 修复 PlistService.delete() privileged 路径**

将 `LaunchManager/Services/PlistService.swift` 中 `delete` 函数完整替换为：

```swift
func delete(_ item: LaunchItem,
            launchctl: LaunchctlService,
            privilege: PrivilegeService) throws {
    if item.scope.requiresPrivilege {
        try privilege.run("/bin/launchctl unload \(item.plistURL.path); rm \(item.plistURL.path)")
    } else {
        try? launchctl.unload(item.plistURL, privileged: false)
        try FileManager.default.removeItem(at: item.plistURL)
    }
}
```

- [ ] **Step 4: 运行全部 PlistServiceTests，确认全部通过**

```bash
cd /Users/sean/LaunchManager/LaunchManager
xcodebuild test -project LaunchManager.xcodeproj -scheme LaunchManager -destination 'platform=macOS' -only-testing:LaunchManagerTests/PlistServiceTests 2>&1 | grep -E "Test case|passed|failed"
```

预期：所有 PlistServiceTests 全部 `passed`

- [ ] **Step 5: Commit**

```bash
git add LaunchManager/Services/PlistService.swift LaunchManagerTests/LaunchManagerTests.swift
git commit -m "fix: combine privileged unload+rm into single shell call to avoid double password prompt"
```

---

### Task 2: EditAgentSheet 必填字段视觉区分

**Files:**
- Modify: `LaunchManager/Views/EditAgentSheet.swift`

- [ ] **Step 1: 添加 requiredField helper 并更新 "基本信息" Section**

将 `LaunchManager/Views/EditAgentSheet.swift` 中 `body` 计算属性之前（`init` 结束之后），添加 private helper；同时更新 `Section("基本信息")` 内容。

完整替换 `var body: some View {` 之前到文件末尾之前的部分，即从第 44 行开始的全部 `body` + helper 方法，改为：

```swift
var body: some View {
    Form {
        Section("基本信息") {
            requiredField("Label") {
                TextField("如 com.example.mytask", text: $label)
            }
            requiredField("程序路径") {
                HStack {
                    TextField("/usr/local/bin/mytool", text: $program)
                    Button("选择…") { pickProgram() }
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                TextEditor(text: $argumentsText)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 64)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.secondary.opacity(0.3))
                    )
                Text("参数（每行一个）").font(.caption).foregroundStyle(.secondary)
            }
        }

        Section("触发方式") {
            Picker("类型", selection: $triggerType) {
                ForEach(LaunchItem.TriggerType.allCases, id: \.self) {
                    Text($0.rawValue).tag($0)
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
    .frame(minWidth: 500)
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

private func requiredField<Content: View>(
    _ fieldLabel: String,
    @ViewBuilder content: () -> Content
) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 0) {
            Text(fieldLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(" *")
                .font(.caption)
                .foregroundStyle(.red)
        }
        content()
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.blue.opacity(0.5), lineWidth: 1)
            )
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
```

- [ ] **Step 2: 确认编译通过**

```bash
cd /Users/sean/LaunchManager/LaunchManager
xcodebuild build -project LaunchManager.xcodeproj -scheme LaunchManager -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD"
```

预期：`BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add LaunchManager/Views/EditAgentSheet.swift
git commit -m "feat: add required field highlighting to EditAgentSheet (blue border + red asterisk)"
```

---

### Task 3: 推送并更新版本

- [ ] **Step 1: 推送到 GitHub**

```bash
git push
```

- [ ] **Step 2: 手动测试**

打开 app，点击"+"新建 Agent：
- Label 和程序路径字段应显示蓝色边框 + 上方小标签带红色 `*`
- 日志路径 Section 标题显示"（可选）"
- 删除一个 System Daemon，确认只弹一次密码框
