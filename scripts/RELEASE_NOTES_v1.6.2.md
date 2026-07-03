## LaunchManager v1.6.2

### Fixed
- **Chinese and Unicode paths** — paths like `/Applications/启动器.app` no longer show as `???` or mojibake; mojibake repair no longer corrupts valid CJK text.
- **TCP Services empty list** — inherit shell environment for `lsof`/`ps`; treat `lsof` exit 1 with no stderr as “no listeners”; count root-owned processes as alive when signal check returns EPERM.
- **Services scan in GUI apps** — run shell tools with `C.UTF-8` locale without replacing the inherited environment.

### Improved
- **Process command lines** — read UTF-8 argv from the kernel (`KERN_PROCARGS2`) before falling back to `ps`.
- **Services UI** — “显示全部” toggle (default on for first launch), clearer empty states and scan-error messaging.
- **Path display** — consistent `FilePathNormalizer.display()` across Services, Agents, and kill confirmations.

### Installation

```bash
brew tap Sean10000/tap
brew upgrade --cask launchmanager
```

Or download **LaunchManager.dmg** below and drag to Applications.

> First launch: right-click → Open (app is not notarized).
