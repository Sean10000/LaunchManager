## LaunchManager v1.5.0

### New
- **Login Items 说明页：** 侧边栏新增「Login Items」入口，说明 Launchd（LaunchAgent / LaunchDaemon）与系统「登录项」的区别，并提供按钮跳转到「系统设置 → 通用 → 登录项」。
- **侧边栏交互：** 分类与 Login Items 使用按钮行，修复部分环境下点击侧边栏无法切换页面的问题。

### Notes
- Login Items 仍由 macOS 系统设置管理；本应用不读取 BTM 列表、不提供开关。

### Installation

```bash
brew tap Sean10000/tap
brew upgrade --cask launchmanager
```

Or download **LaunchManager.dmg** below and drag to Applications.

> First launch: right-click → Open (app is not notarized).
