# Design: 表单 UX 改进 + 删除双密码 Bug 修复

**日期:** 2026-04-23  
**状态:** 已批准

## 背景

用户反馈三个问题：
1. 删除 System Agent / System Daemon 时弹出两次密码框
2. 新建 Agent 表单中无法区分必填和可选字段
3. 输入框视觉不够醒目，背景色无法和 label 文字区分

## 问题一：删除 System plist 弹两次密码

### 根因

`PlistService.delete()` 对 privileged scope 连续调用两次 `privilege.run()`：

```swift
try? launchctl.unload(item.plistURL, privileged: item.scope.requiresPrivilege)
// ↑ 内部调用 privilege.run("/bin/launchctl unload ...") → 弹窗 #1

if item.scope.requiresPrivilege {
    try privilege.run("rm \(item.plistURL.path)")  // → 弹窗 #2
}
```

每次 `NSAppleScript` 执行都会独立触发系统授权弹窗，两条命令 = 两次弹窗。

### 修复方案

将 unload + rm 合并为一条 shell 命令，在单次 `privilege.run()` 内完成：

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

**文件：** `LaunchManager/Services/PlistService.swift`

---

## 问题二 & 三：EditAgentSheet 表单视觉改进

### 设计方案（B 方案）

**必填字段**（Label、Program）：
- 输入框背景：`Color(.displayP3, red: 0.1, green: 0.14, blue: 0.22)`（深蓝色调）
- 字段名后加红色星号：`Text(" *").foregroundStyle(.red)`
- 输入框 overlay 蓝色边框：`RoundedRectangle(cornerRadius: 6).stroke(Color.blue.opacity(0.5), lineWidth: 1)`

**可选字段**（参数、日志路径等）：
- 保持系统默认样式，不做特殊处理
- "日志路径" Section 标题改为 "日志路径（可选）"

### 必填字段范围

仅 Label 和 Program 两个字段，与现有 Save 按钮 `.disabled(label.isEmpty || program.isEmpty)` 逻辑一致，不引入新的必填逻辑。

### 实现方式

在 `EditAgentSheet.swift` 中提取一个 `requiredField` ViewBuilder，避免重复样式代码：

```swift
@ViewBuilder
private func requiredField(label: String, content: some View) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 0) {
            Text(label)
            Text(" *").foregroundStyle(.red)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        content
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.displayP3, red: 0.1, green: 0.14, blue: 0.22))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.blue.opacity(0.5), lineWidth: 1)
            )
    }
}
```

**文件：** `LaunchManager/Views/EditAgentSheet.swift`

---

## 不在本次范围内

- 表单验证错误提示（如 label 格式不合法）
- 其他字段的必填/可选状态变更
- 键盘焦点管理
