## LaunchManager v1.4.0

### Fixes
- **Log viewer:** No longer freezes the app — system logs load lazily, output is capped, and lines render incrementally instead of one giant text block (v2ex feedback).
- **LaunchDaemons permissions:** System Agent/Daemon plists are now saved as `root:wheel` with mode `644`, fixing load failures after create ([#3](https://github.com/Sean10000/LaunchManager/issues/3)).
- **Intel Macs:** Release builds are now universal (`arm64` + `x86_64`) ([#2](https://github.com/Sean10000/LaunchManager/issues/2)).

### Improvements
- launchctl API cleanup: uses `bootstrap`/`bootout`/`kickstart`/`kill` only; removed stale duplicate sources with deprecated `load`/`unload`.
- UI: “载入” / “移除” instead of legacy load/unload wording.

### Installation

```bash
brew tap Sean10000/tap
brew upgrade --cask launchmanager
```

Or download **LaunchManager.dmg** below and drag to Applications.

> First launch: right-click → Open (app is not notarized).
