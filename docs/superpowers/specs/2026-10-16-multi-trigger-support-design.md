# Design: 多触发器支持（解析、表单、列表）

> **Note:** Schedule/form UX for triggers superseded by [`2026-10-20-trigger-rule-model-design.md`](./2026-10-20-trigger-rule-model-design.md); multi-trigger coexistence still in force.

**日期:** 2026-10-16  
**状态:** 已批准  
**范围:** v1 — 多类型触发并存 + 多条日历间隔 + 表单多选 + 列表多行展示

## 背景

当前模型用单一 `triggerType` 表示触发方式，解析时 `if / else if` 只取第一个匹配键。`formIncompatibilityReason` 在存在多个触发键时强制 XML 模式；创建表单用分段控件只能选一种触发。

真实 launchd plist 允许同时存在 `StartCalendarInterval`、`StartInterval`、`WatchPaths`，且 `StartCalendarInterval` 可以是 dict 或 dict 数组。用户因此看到：多触发只能用 XML、列表/详情不完整、新建无法组合触发。

App 内旧「登录时」触发类型并非 launchd 键，语义与 `RunAtLoad` 重叠且易混淆。

## 目标

| 能力 | v1 |
|------|-----|
| 同时解析 / 保存多种触发键 | ✅ |
| `StartCalendarInterval` 单 dict 与 array | ✅ |
| 表单多选触发（定时 / 间隔 / 监视路径） | ✅ |
| 日历多条增删 | ✅ |
| 列表 / 详情多行展示全部触发 | ✅ |
| 「登录时」并入 `RunAtLoad`，去掉假触发类型 | ✅ |
| 表单多监视路径编辑器 | ❌（单路径输入；多路径仍可用 XML） |
| 其它 launchd 触发键（如 `QueueDirectories`、`StartOnMount`） | ❌ |

## 方案选择

| 决策 | 选择 | 理由 |
|------|------|------|
| 数据模型 | **触发器集合**：有值即启用 | 对齐 launchd；避免「主/次触发」假概念 |
| 「登录时」 | 删除 `TriggerType.atLoad`；只用 `runAtLoad` | RunAtLoad 是真键；旧类型只表示「无其它触发」 |
| 表单 UX | 三个独立 Toggle + 各自配置 | 用户选择 A：可勾选多种类型 |
| 列表展示 | 多行，每种/每条各占一行 | 用户选择 B |
| 多触发是否强制 XML | 否 | 表单已覆盖三种常见触发 |

## 架构

### 数据模型

`LaunchItem` / `LaunchAgentDraft`：

- 删除 `triggerType` 与 `TriggerType` 枚举（含 `.atLoad`）
- `calendarInterval: CalendarInterval?` → `calendarIntervals: [CalendarInterval]`
- 保留 `startInterval: Int?`、`watchPaths: [String]`、`runAtLoad: Bool`

语义：

- `calendarIntervals` 非空 → 写 / 读 `StartCalendarInterval`
- `startInterval != nil` → 写 / 读 `StartInterval`
- `watchPaths` 非空 → 写 / 读 `WatchPaths`
- 全部为空且 `runAtLoad == false` 合法（仅加载、手动启动）

### PlistService

**解析 `parsePlist`**

- `StartCalendarInterval`：
  - `[String: Any]`（或 `[String: Int]`）→ 单条 `CalendarInterval`
  - `[[String: Any]]` → 多条
  - 无法识别的元素跳过；若最终列表为空则不启用日历触发
- `StartInterval`、`WatchPaths`：独立解析，不再与日历互斥
- `RunAtLoad`：照旧

**写入 `toDictionary`**

- `calendarIntervals.count == 1` → 写单个 dict
- `count >= 2` → 写 array of dict
- `count == 0` → 不写该键
- `startInterval` / `watchPaths`：有值才写
- `RunAtLoad`：`true` 才写

**表单兼容性 `formIncompatibilityReason`**

- 删除「`triggers > 1` → 强制 XML」
- 保留：未知键、非 Bool 的 `KeepAlive` 等既有规则
- `StartCalendarInterval` 条目以 Weekday / Hour / Minute 为准；条目内其它子键忽略，不因此强制 XML

**保存**

- 表单 `save` 不再因多触发拒绝
- 从磁盘读入后若仅因多触发曾被标为不兼容，改为允许表单

### 表单 UI（EditAgentSheet）

「触发方式」：

1. **定时** Toggle → 日历列表；每条：星期 / 时 / 分；添加 / 删除时段；打开且列表为空时默认一条
2. **间隔** Toggle → 秒数；关闭时不写出 `StartInterval`
3. **监视路径** Toggle → 单路径 TextField，写入 `watchPaths`（0 或 1 个元素）
   - `watchPaths.count > 1` → `formIncompatibilityReason` 提示使用 XML（表单只建模单路径，避免静默丢路径）
   - `count <= 1` → 表单可编辑

选项区保留 **「加载时自动运行」**（`RunAtLoad`）；文案避免「登录时」。不再提供「登录时」触发类型。

XML ↔ 表单同步：识别到的多触发全部填入对应 Toggle；真正不兼容时禁用表单并显示原因。

### 列表 / 详情（AgentRowView）

「触发」多行，固定顺序：

1. 每条日历（如 `每天 08:00`、`周一 18:30`）
2. 间隔（如 `每 300 秒`）
3. 监视路径（每条路径一行：`监视路径：…`）
4. 若 `runAtLoad`：`加载时运行`

若以上皆无：显示 `无自动触发`。

### 模块变更概览

```
LaunchManager/
├── Models/
│   ├── LaunchItem.swift         # 集合模型；删 TriggerType
│   └── LaunchAgentDraft.swift   # 同步字段
├── Services/
│   └── PlistService.swift       # 多触发解析/写入；去掉多触发强制 XML
├── Views/
│   ├── EditAgentSheet.swift     # Toggle 多选 + 多日历
│   └── AgentRowView.swift       # 多行触发描述
└── LaunchManagerTests/
    └── LaunchManagerTests.swift # 解析/回写/兼容性/摘要
```

## 错误处理

- 日历 array 中非法元素：跳过；若全部非法则不启用日历触发
- 表单打开「定时」但保存时列表为空：视为未启用日历（不写键），或保存前自动关 Toggle——实现选前者并在关 Toggle 时清空列表
- 多 `watchPaths`：表单禁用原因明确指向 XML
- 既有「未知键强制 XML」行为不变

## 测试计划

- 解析：日历 + 间隔 + WatchPaths 并存
- 解析：`StartCalendarInterval` 为 array（≥2）与单 dict
- 回写：多日历写出 array；单日历写出 dict
- `formIncompatibilityReason`：仅多触发时返回 `nil`；多 WatchPaths 或未知键仍不兼容
- 列表摘要：多行内容与顺序
- 回归：单触发 plist、draft 默认值、既有 roundtrip

## 非目标

- 表单编辑 `QueueDirectories` / `StartOnMount` / `Sockets` 等
- 监视路径的多行表单编辑器（v1 用 XML）
- 改变 bootstrap / kickstart 行为
