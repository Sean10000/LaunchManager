#!/bin/bash
set -e

# Usage: ./scripts/release.sh 1.1.0
VERSION="$1"

# ── 参数检查 ──────────────────────────────────────────────
if [ -z "$VERSION" ]; then
  echo "Usage: ./scripts/release.sh <version>"
  echo "Example: ./scripts/release.sh 1.1.0"
  exit 1
fi

TAG="v$VERSION"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ARCHIVE_PATH="/tmp/LaunchManager.xcarchive"
DMG_PATH="/tmp/LaunchManager.dmg"
DMG_STAGING="/tmp/LaunchManager-dmg"
TAP_DIR="/tmp/homebrew-tap"
CASK_FILE="$TAP_DIR/Casks/launchmanager.rb"

echo "▶ Releasing LaunchManager $TAG"
echo ""

# ── 1. Build Archive ──────────────────────────────────────
echo "[1/5] Building archive..."
cd "$PROJECT_DIR"
xcodebuild archive \
  -project LaunchManager.xcodeproj \
  -scheme LaunchManager \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  AD_HOC_CODE_SIGNING_ALLOWED=YES \
  DEVELOPMENT_TEAM="" \
  2>&1 | grep -E "error:|ARCHIVE|BUILD"
echo "  ✓ Archive built"

# ── 2. Package DMG ────────────────────────────────────────
echo "[2/5] Packaging DMG..."
APP_PATH=$(find "$ARCHIVE_PATH" -name "LaunchManager.app" -maxdepth 5 | head -1)
rm -rf "$DMG_STAGING" && mkdir "$DMG_STAGING"
cp -r "$APP_PATH" "$DMG_STAGING/"
hdiutil create -volname "LaunchManager" -srcfolder "$DMG_STAGING" -ov -format UDZO "$DMG_PATH" > /dev/null
echo "  ✓ DMG created ($(du -sh "$DMG_PATH" | cut -f1))"

# ── 3. SHA256 ─────────────────────────────────────────────
echo "[3/5] Computing SHA256..."
SHA256=$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')
echo "  ✓ $SHA256"

# ── 4. GitHub Release ─────────────────────────────────────
echo "[4/5] Creating GitHub Release $TAG..."
gh release create "$TAG" "$DMG_PATH" \
  --title "$TAG" \
  --notes "## LaunchManager $TAG

### Installation
\`\`\`bash
brew tap Sean10000/tap
brew install --cask launchmanager
\`\`\`
Or download **LaunchManager.dmg** below and drag to Applications.

> First launch: right-click → Open (app is not notarized)." \
  --repo Sean10000/LaunchManager
echo "  ✓ Release published"

# ── 5. Update Homebrew Tap ────────────────────────────────
echo "[5/5] Updating homebrew-tap..."
if [ -d "$TAP_DIR/.git" ]; then
  git -C "$TAP_DIR" pull --quiet
else
  rm -rf "$TAP_DIR"
  git clone --quiet https://github.com/Sean10000/homebrew-tap.git "$TAP_DIR"
fi

cat > "$CASK_FILE" <<CASK
cask "launchmanager" do
  version "$VERSION"
  sha256 "$SHA256"

  url "https://github.com/Sean10000/LaunchManager/releases/download/v\#{version}/LaunchManager.dmg"
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

git -C "$TAP_DIR" add Casks/launchmanager.rb
git -C "$TAP_DIR" commit -m "chore: bump LaunchManager to $TAG"
git -C "$TAP_DIR" push
echo "  ✓ Homebrew tap updated"

# ── Done ──────────────────────────────────────────────────
echo ""
echo "🎉 LaunchManager $TAG released!"
echo "   GitHub : https://github.com/Sean10000/LaunchManager/releases/tag/$TAG"
echo "   Install : brew tap Sean10000/tap && brew install --cask launchmanager"
