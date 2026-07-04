#!/bin/bash
# Update Sean10000/homebrew-tap with version and SHA256.
# Usage: ./scripts/update-homebrew-tap.sh 1.6.2 <sha256> [tap_dir]
set -euo pipefail

VERSION="${1:?Usage: update-homebrew-tap.sh VERSION SHA256 [TAP_DIR]}"
SHA256="${2:?Usage: update-homebrew-tap.sh VERSION SHA256 [TAP_DIR]}"
TAP_DIR="${3:-/tmp/homebrew-tap}"
CASK_FILE="$TAP_DIR/Casks/launchmanager.rb"

mkdir -p "$(dirname "$CASK_FILE")"
cat > "$CASK_FILE" <<CASK
cask "launchmanager" do
  version "$VERSION"
  sha256 "$SHA256"

  url "https://github.com/Sean10000/LaunchManager/releases/download/v#{version}/LaunchManager.dmg"
  name "LaunchManager"
  desc "macOS app for managing launchd LaunchAgents and LaunchDaemons"
  homepage "https://github.com/Sean10000/LaunchManager"

  app "LaunchManager.app"

  zap trash: [
    "~/Library/Preferences/com.Sean10000.LaunchManager.plist",
    "~/Library/Application Support/LaunchManager",
  ]
end
CASK

echo "✓ Wrote $CASK_FILE"
