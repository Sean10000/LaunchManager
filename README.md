# LaunchManager

A macOS app for managing launchd LaunchAgents and LaunchDaemons — view, create, edit, and control your system's scheduled tasks from a clean native UI.

![macOS](https://img.shields.io/badge/macOS-14%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.10-orange) ![License](https://img.shields.io/badge/license-MIT-green) ![Built with Claude](https://img.shields.io/badge/Built%20with-Claude-blueviolet?logo=anthropic)

## Features

- **Browse** all LaunchAgents and LaunchDaemons across User, System Agent, and System Daemon scopes
- **Create & edit** plist jobs with a form UI — no manual XML editing required
- **Control** jobs: load, unload, start, stop
- **View logs** — both file-based stdout/stderr logs and system log (via `log show`)
- **Handle invalid plists** — empty or malformed plist files are shown inline with an option to delete them
- **Privilege escalation** for system-level operations (prompts for admin password when needed)

## Requirements

- macOS 14 Sonoma or later
- Xcode 16 or later (to build from source)

## Installation

### Build from Source

```bash
git clone https://github.com/Sean10000/LaunchManager.git
cd LaunchManager
open LaunchManager.xcodeproj
```

Build and run with Xcode (`⌘R`).

## Usage

1. Select a scope from the sidebar: **User Agents**, **System Agents**, or **System Daemons**
2. Click **+** to create a new job, or click the pencil icon to edit an existing one
3. Use the row buttons to **load / start / stop** a job
4. Expand a row (chevron) to see details and view logs

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
| **App must stay running** | ❌ Not required | ❌ Not required | ⚠️ Required | ❌ Not required |
| **AI assistant** | ❌ | ✅ (7 LLM providers) | ❌ | ❌ |
| **XML / Expert editor** | ❌ | ✅ | ❌ | ❌ |
| **Open Source** | ✅ MIT | ❌ | ❌ | ❌ |
| **macOS requirement** | 14 Sonoma+ | 11 Big Sur+ | 14 Sonoma+ | — |

> LaunchManager is ideal if you want a **free, native, open-source** tool for everyday launchd management.
> For power users needing an AI assistant or expert XML editor, [LaunchControl](https://www.soma-zone.com/LaunchControl/) is the most feature-complete paid option.

## Project Structure

```
LaunchManager/
├── Models/          # LaunchItem, InvalidPlist data models
├── Services/        # PlistService, LaunchctlService, PrivilegeService, ShellRunner
├── Store/           # AgentStore (ObservableObject)
└── Views/           # SwiftUI views
```

## License

MIT — see [LICENSE](LICENSE).

## Acknowledgements

Built with [Claude](https://claude.ai) (Anthropic) — AI pair programmer for design, implementation, and code review.
