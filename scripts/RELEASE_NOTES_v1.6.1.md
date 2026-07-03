## LaunchManager v1.6.1

### Added
- **Help menu** — opens https://www.launchmanager.dev/help from the menu bar.

### Improved
- **Full English UI** — complete String Catalog coverage; interface follows system language (English or Chinese).
- **Unicode paths** — correct display of non-ASCII paths (e.g. Chinese `.app` names) in Services via native macOS APIs and UTF-8 shell locale.

### Fixed
- Build error in process discovery (`cwdFromLsof` instance call).
- Octal-encoded path decoding from `lsof` output.

### Installation

```bash
brew tap Sean10000/tap
brew upgrade --cask launchmanager
```

Or download **LaunchManager.dmg** below and drag to Applications.

> First launch: right-click → Open (app is not notarized).
