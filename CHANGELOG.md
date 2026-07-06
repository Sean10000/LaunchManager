# Changelog

All notable changes to LaunchManager are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- **EnvironmentVariables** — key-value editor in agent form.
- **Override status** — shows jobs disabled via `launchctl override`; **启用** button calls `launchctl enable`.
- **Directory watching** — agent list auto-refreshes when plist folders change (FSEvents) and when the app returns to foreground.

### Improved
- **Form save safety** — blocks form save when plist contains keys the form cannot represent; lists unsupported keys and directs users to XML mode.
- **launchctl errors** — load/unload/start/stop/enable failures show a short hint plus raw `launchctl` output.

<!-- Add changes here as you develop. Run ./scripts/release.sh patch to publish. -->

## [1.6.4] - 2026-07-04


### Added
- **Plist XML editor** — Form | XML tabs in agent editor; paste XML to create new jobs; extra plist keys preserved in XML mode.
- **Import plist** — import external `.plist` into user/global Agent or LaunchDaemon directories.
- **Clone job** — duplicate an existing Launch Agent/Daemon with a new Label.
- **Services → Launch Agent** — prefill a new user Agent from a running local service (command, working directory).
- **WorkingDirectory** — optional field in agent form.
- **Startup update check** — once per day, compares the running app to GitHub Releases; shows a sheet with DMG download link, Homebrew upgrade commands (copy), and options to skip a version or remind later.
- **Check for Updates** — manual check from the About window.

### Changed
- **Launch Agents sidebar** — User Agents, System Agents, and LaunchDaemons merged into a single **Launch Agents** entry; the detail view groups items by scope with collapsible sections (same pattern as Services).
- **New Agent** — toolbar **New** is now a menu to pick user / global Agent or LaunchDaemon scope before opening the editor.
- **Agent search** — search runs across all three scopes in one view.

### Improved
- **Services row layout** — port/address stays visible when display name or Docker image subtitle is long; Docker subtitle uses compose service or short image name.
- **New Agent templates link** — footer button on the new-agent sheet opens [launchmanager.dev/templates](https://www.launchmanager.dev/templates).
- **Services groups** — Docker and local instance sections can be collapsed/expanded via the group header (helpful when many services are listed).
- **DMG install UX** — release DMGs include an **Applications** folder shortcut beside the app for drag-to-install (via `create-dmg`); README Direct Download instructions updated.
- **Release tooling** — shared `package-dmg.sh` for local builds and CI; `build-dmg.sh` outputs to `build/LaunchManager.dmg`.

## [1.6.3] - 2026-07-04


### Changed
- **Release automation** — version in `Version.xcconfig`, CHANGELOG-driven releases, GitHub Actions builds DMG and updates Homebrew tap.

## [1.6.2] - 2026-07-04

### Fixed
- **Chinese and Unicode paths** — paths like `/Applications/启动器.app` no longer show as `???` or mojibake; mojibake repair no longer corrupts valid CJK text.
- **TCP Services empty list** — inherit shell environment for `lsof`/`ps`; treat `lsof` exit 1 with no stderr as “no listeners”; count root-owned processes as alive when signal check returns EPERM.
- **Services scan in GUI apps** — run shell tools with `C.UTF-8` locale without replacing the inherited environment.

### Improved
- **Process command lines** — read UTF-8 argv from the kernel (`KERN_PROCARGS2`) before falling back to `ps`.
- **Services UI** — “显示全部” toggle (default on for first launch), clearer empty states and scan-error messaging.
- **Path display** — consistent `FilePathNormalizer.display()` across Services, Agents, and kill confirmations.

## [1.6.1] - 2026-07-03

### Added
- **Help menu** — opens https://www.launchmanager.dev/help from the menu bar.

### Improved
- **Full English UI** — complete String Catalog coverage; interface follows system language (English or Chinese).
- **Unicode paths** — correct display of non-ASCII paths (e.g. Chinese `.app` names) in Services via native macOS APIs and UTF-8 shell locale.

### Fixed
- Build error in process discovery (`cwdFromLsof` instance call).
- Octal-encoded path decoding from `lsof` output.

## [1.6.0] - 2026-07-02

### Added
- **Services module:** sidebar entry to scan local TCP listening processes (3s polling).
- **Three-tier identification:** host mechanisms (docker-proxy, Colima, SSH forward, etc.) → high-confidence services (Next.js, Redis, PostgreSQL) → user custom display names.
- **Docker integration:** resolve container name, image, and Compose labels via `docker ps`; stop containers with `docker stop` instead of killing docker-proxy.
- **Grouped list:** Docker and local instance sections in the Services view.

### Scope
- **Host-local TCP `LISTEN` only** — processes bound on your Mac
- **Docker published ports on Mac** — via `docker ps` port mapping
- **Does not include** remote VM/NAS/LAN services or outbound-only (`ESTABLISHED`) connections
- **TCP only** in v1.6 (no UDP)

### Improved
- Full process names from `ps command=` (avoids lsof ~8 character truncation).
- Docker CLI lookup via known install paths with `/usr/bin/env docker` PATH fallback (no zsh dependency).

## [1.5.1]

### Fixed
- **Start / Stop 点击反馈：** 启动、停止、载入、移除操作立即显示 spinner 与进行中状态，整行锁定防连点误操作。
- **Stop 一次生效：** 停止后轮询直到 PID 清除再结束 pending，避免需点击两次才显示已停止。

## [1.5.0]

### Added
- **Login Items 说明页：** 侧边栏新增「Login Items」入口，说明 Launchd（LaunchAgent / LaunchDaemon）与系统「登录项」的区别，并提供按钮跳转到「系统设置 → 通用 → 登录项」。
- **侧边栏交互：** 分类与 Login Items 使用按钮行，修复部分环境下点击侧边栏无法切换页面的问题。

### Notes
- Login Items 仍由 macOS 系统设置管理；本应用不读取 BTM 列表、不提供开关。

## [1.4.1]

### Fixed
- **Localization:**「载入」「移除」and the delete confirmation message now show in English on English macOS (were missing from the String Catalog since v1.4.0).

## [1.4.0]

### Fixed
- **Log viewer:** No longer freezes the app — system logs load lazily, output is capped, and lines render incrementally instead of one giant text block (v2ex feedback).
- **LaunchDaemons permissions:** System Agent/Daemon plists are now saved as `root:wheel` with mode `644`, fixing load failures after create ([#3](https://github.com/Sean10000/LaunchManager/issues/3)).
- **Intel Macs:** Release builds are now universal (`arm64` + `x86_64`) ([#2](https://github.com/Sean10000/LaunchManager/issues/2)).

### Improved
- launchctl API cleanup: uses `bootstrap`/`bootout`/`kickstart`/`kill` only; removed stale duplicate sources with deprecated `load`/`unload`.
- UI: “载入” / “移除” instead of legacy load/unload wording.
