# Design: Invalid Plist 内联显示与删除

**日期:** 2026-04-23  
**状态:** 已批准

## 背景

部分 plist 文件（如 Google Keystone 的占位符文件）内容为空 `<dict/>`，缺少必需的 `Label` 字段，导致 `PlistService.parsePlist` 返回 nil。当前行为是将文件名追加到 `warnings` 数组，在列表底部的警告栏中集中显示。

存在两个 bug：
1. **空 plist 触发 warning**：这类占位符文件无法解析，但不应与真正的格式错误等同
2. **重复警告**：同一文件名存在于多个 scope 目录（如 userAgent 和 systemAgent），因 warnings 只记录文件名，导致同名条目重复出现

## 目标

- 将无效 plist 内联显示在对应 scope 的列表中，让用户可以选择删除
- 消除重复警告（改用完整 URL 作为 key）
- 移除底部 warning 栏，UI 更干净

## 数据模型

新增 `InvalidPlist` struct（位于 `Models/LaunchItem.swift` 或独立文件）：

```swift
struct InvalidPlist: Identifiable {
    var id: URL { url }
    let url: URL
    let scope: LaunchItem.Scope
}
```

- 不复用 `LaunchItem`，避免大量无意义的 Optional 字段
- 用完整 `URL` 作为 id，天然去重且保留路径信息

`AgentStore` 变更：
- 新增 `@Published var invalidItems: [InvalidPlist] = []`
- 移除 `@Published var warnings: [String]`

## 服务层

`PlistService.scanAll()` 签名改为：

```swift
func scanAll() -> (items: [LaunchItem], invalid: [InvalidPlist])
```

解析失败时将完整 URL 包装为 `InvalidPlist` 放入 `invalid` 数组，不再使用文件名字符串。

`AgentStore` 新增删除方法：

```swift
func deleteInvalid(_ item: InvalidPlist) throws {
    if item.scope.requiresPrivilege {
        try privilegeService.run("rm \(item.url.path)")
    } else {
        try FileManager.default.removeItem(at: item.url)
    }
    refresh()
}
```

无效条目不需要 `launchctl unload`（从未被加载），直接删除文件即可。需要 privilege 的 scope（systemAgent、systemDaemon）走 AppleScript 提权。

`AgentStore.refresh()` 同时更新 `items` 和 `invalidItems`。

## UI 层

### AgentListView

新增参数 `invalidItems: [InvalidPlist]`，在正常条目下方追加：

```swift
LazyVStack(spacing: 6) {
    ForEach(items) { item in
        AgentRowView(item: item, store: store, errorMessage: $errorMessage)
    }
    ForEach(invalidItems) { item in
        InvalidPlistRowView(item: item, store: store, errorMessage: $errorMessage)
    }
}
```

移除 `safeAreaInset` 中的 warning 栏。

### InvalidPlistRowView（新文件）

视觉样式：
- 左侧灰色小圆点（`Color(nsColor: .tertiaryLabelColor)`，与未运行条目一致）
- 文件名 monospaced 字体，`.secondary` 颜色
- 右侧：`⚠️` 文字标签 + 垃圾桶按钮（无加载/编辑按钮）
- 展开后显示完整路径 + 说明文字"此文件为空或格式无效"

删除确认使用与 `AgentRowView` 相同的 `confirmationDialog` 模式。

### ContentView

新增 `filteredInvalidItems` 计算属性，按 scope 过滤 `store.invalidItems`，传入 `AgentListView`。

## 不在本次范围内

- 区分"空 plist"与"格式错误 plist"的子类型（统一归为无效）
- 编辑无效 plist 的能力
- 批量删除
