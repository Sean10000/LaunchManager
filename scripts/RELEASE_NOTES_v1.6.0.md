## LaunchManager v1.6.0

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

### Installation

```bash
brew tap Sean10000/tap
brew upgrade --cask launchmanager
```

Or download **LaunchManager.dmg** below and drag to Applications.

> First launch: right-click → Open (app is not notarized).
