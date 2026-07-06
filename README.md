# LaunchManager

A macOS app for managing launchd LaunchAgents and LaunchDaemons — view, create, edit, and control your system's scheduled tasks from a clean native UI.

**Website:** [launchmanager.dev](https://www.launchmanager.dev) · **Docs:** [Help](https://www.launchmanager.dev/help) · **Templates:** [launchmanager.dev/templates](https://www.launchmanager.dev/templates)

![Version](https://img.shields.io/badge/version-1.6.4-blue) ![macOS](https://img.shields.io/badge/macOS-14%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.10-orange) ![License](https://img.shields.io/badge/license-MIT-green) ![Built with Claude](https://img.shields.io/badge/Built%20with-Claude-blueviolet?logo=anthropic)

## Star History

<a href="https://www.star-history.com/?repos=Sean10000%2FLaunchManager&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=Sean10000/LaunchManager&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=Sean10000/LaunchManager&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=Sean10000/LaunchManager&type=date&legend=top-left" />
 </picture>
</a>

## Features

### Launch Agents

- **Browse** all LaunchAgents and LaunchDaemons across User, System Agent, and System Daemon scopes in one unified list with collapsible scope groups
- **Search** across all scopes from a single search field
- **Create & edit** plist jobs with a **Form** or **XML** editor — extra plist keys are preserved in XML mode
- **Import plist** — bring external `.plist` files into user/global Agent or LaunchDaemon directories
- **Clone job** — duplicate an existing agent with a new Label
- **Paste XML** — create a new job from clipboard XML
- **Control** jobs: load, unload, start, stop
- **View logs** — both file-based stdout/stderr logs and system log (via `log show`)
- **Handle invalid plists** — empty or malformed plist files are shown inline with an option to delete them
- **Privilege escalation** for system-level operations (prompts for admin password when needed)
- **Agent templates** — quick link to curated examples on [launchmanager.dev/templates](https://www.launchmanager.dev/templates)

### Services

- Discover **host TCP listeners only** (Next.js, Redis, Docker containers published on Mac, etc.)
- Group by Docker vs local instance; collapse/expand sections when many services are listed
- Stop processes or containers safely; rename entries and open URLs
- **Create Launch Agent** from a running local service (prefills command and working directory)

### Other

- **Login Items guide** — explains the difference between launchd and macOS Login Items, with a shortcut to System Settings
- **Auto-update check** — once per day, compares to GitHub Releases; manual **Check for Updates** in About
- **Bilingual UI** — English and Chinese (follows system language)

## Requirements

- macOS 14 Sonoma or later
- Xcode 16 or later (to build from source)

## Installation

### Homebrew (recommended)

```bash
brew tap Sean10000/tap
brew install --cask launchmanager
```

### Direct Download

Download the latest **LaunchManager.dmg** from [Releases](https://github.com/Sean10000/LaunchManager/releases). Open the DMG and drag **LaunchManager** to the **Applications** folder shown in the window.

> **First launch:** right-click the app → Open (required because this build is not notarized by Apple).

### Build from Source

```bash
git clone https://github.com/Sean10000/LaunchManager.git
cd LaunchManager
open LaunchManager.xcodeproj
```

Build and run with Xcode (`⌘R`).

## Releasing

1. Add bullets under `## [Unreleased]` in [CHANGELOG.md](CHANGELOG.md) as you develop.
2. Run `./scripts/release.sh patch` (or `minor`, `major`, or an explicit `X.Y.Z`).
3. GitHub Actions builds the universal DMG, creates the GitHub Release, and updates the Homebrew tap.

Local test build only (no publish):

```bash
./scripts/build-dmg.sh   # → build/LaunchManager.dmg
```

Version numbers live in [Version.xcconfig](Version.xcconfig) only — do not edit `project.pbxproj` by hand.

**CI secret:** set `HOMEBREW_TAP_TOKEN` in repo Settings → Secrets (PAT with push access to `Sean10000/homebrew-tap`).

## Usage

1. Select a section from the sidebar: **Launch Agents**, **Login Items**, or **Services**
2. On **Launch Agents**, use the **New** menu to pick scope (user / global Agent or LaunchDaemon), or **Import** / **Paste XML** from the toolbar
3. Click **+** or edit an existing job; switch between **Form** and **XML** tabs in the editor
4. Use row actions to **load / start / stop**; expand a row (chevron) for details and logs
5. Right-click or use the row menu to **clone** an agent
6. On **Services**, refresh the list, rename entries, open URLs, stop processes/containers, or **create a Launch Agent** from a running service

## Services

The **Services** sidebar scans **TCP ports listening on your Mac** (`lsof -iTCP -sTCP:LISTEN`). It is a local dev-environment view, not a network-wide service discovery tool.

### What it shows

- TCP services **listening on the host** (Next.js, Redis, PostgreSQL, etc.)
- **Docker / Colima** containers whose ports are **published on the Mac** (resolved via `docker ps`)

### What it does not show

- **Outbound connections only** (`ESTABLISHED` where your Mac is the client)
- Services running **inside a VM, NAS, or another machine** on the LAN (unless their port is forwarded so the Mac is listening locally)
- **UDP** listeners (TCP only in current release)

### Quick check

```bash
# Will appear in Services only if the Mac is LISTENing on this port
lsof -iTCP:5666 -sTCP:LISTEN -nP

# Matches any socket involving port 5666 (including remote VM / outbound client)
lsof -i :5666
```

**Example:** A NAS on a VMware VM at `192.168.95.x:5666` — your Mac may only have an outbound `ESTABLISHED` connection to that address. The NAS is not listening on the Mac, so it is **excluded by design**.

## Comparison with Paid Alternatives

| Feature | LaunchManager (Free) | LaunchControl | Lingon Pro 10 | LaunchD Task Scheduler |
|---|---|---|---|---|
| **Price** | Free & Open Source | ~$33 | $23.99 | $5.00 |
| **Distribution** | GitHub Direct | Direct / Homebrew | App Store / Direct | App Store |
| **Browse Agents & Daemons** | ✅ | ✅ | ✅ | ✅ |
| **Create & Edit jobs (GUI)** | ✅ | ✅ | ✅ | ✅ |
| **Load / Unload / Start / Stop** | ✅ | ✅ | ✅ | ✅ |
| **Log viewer** | ✅ File + System log | ✅ Advanced | ✅ | ✅ |
| **System Agent / Daemon support** | ✅ | ✅ | ✅ (Pro) | Limited |
| **Privilege escalation** | ✅ | ✅ | ✅ | — |
| **Invalid plist detection** | ✅ Inline with delete | ❌ | ❌ | ❌ |
| **Local TCP / Docker services view** | ✅ | ❌ | ❌ | ❌ |
| **App must stay running** | ❌ Not required | ❌ Not required | ⚠️ Required | ❌ Not required |
| **AI assistant** | ❌ | ✅ (7 LLM providers) | ❌ | ❌ |
| **XML / Expert editor** | ✅ Form + XML tabs | ✅ Advanced | ❌ | ❌ |
| **Open Source** | ✅ MIT | ❌ | ❌ | ❌ |
| **macOS requirement** | 14 Sonoma+ | 11 Big Sur+ | 14 Sonoma+ | — |

> LaunchManager is ideal if you want a **free, native, open-source** tool for everyday launchd management and local dev service discovery.
> For power users needing an AI assistant or advanced XML tooling (syntax highlighting, diff), [LaunchControl](https://www.soma-zone.com/LaunchControl/) remains the most feature-complete paid option.

## Project Structure

```
LaunchManager/
├── Models/          # LaunchItem, InvalidPlist, LaunchAgentDraft, Service, ListeningProcess
├── Services/        # PlistService, LaunchctlService, UpdateChecker, ProcessDiscovery, Docker/
├── Store/           # AgentStore, ServiceStore, ServiceNameStore
└── Views/           # SwiftUI views (AgentList, ServicesList, EditAgentSheet, …)
```

## License

MIT — see [LICENSE](LICENSE).

## Support

If LaunchManager saved you some time, feel free to buy me a coffee ☕ Americano is better.

<img src="assets/wechat-reward.jpg" width="200" alt="WeChat Reward QR Code" />

## Acknowledgements

Built with [Claude](https://claude.ai) (Anthropic) — AI pair programmer for design, implementation, and code review.
