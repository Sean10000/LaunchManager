## LaunchManager v1.5.1

### Fixed
- **Start / Stop 点击反馈：** 启动、停止、载入、移除操作立即显示 spinner 与进行中状态，整行锁定防连点误操作。
- **Stop 一次生效：** 停止后轮询直到 PID 清除再结束 pending，避免需点击两次才显示已停止。

### Installation

```bash
brew tap Sean10000/tap
brew upgrade --cask launchmanager
```

Or download **LaunchManager.dmg** below and drag to Applications.

> First launch: right-click → Open (app is not notarized).
