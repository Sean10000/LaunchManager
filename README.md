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
