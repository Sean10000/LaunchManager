#!/bin/bash
# Build a universal Release DMG locally (no publish).
# Output: build/LaunchManager.dmg
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ARCHIVE_PATH="$PROJECT_DIR/build/LaunchManager.xcarchive"
DMG_PATH="$PROJECT_DIR/build/LaunchManager.dmg"

mkdir -p "$PROJECT_DIR/build"
rm -rf "$ARCHIVE_PATH" "$DMG_PATH"

echo "▶ Building LaunchManager (universal Release)..."
cd "$PROJECT_DIR"
xcodebuild archive \
  -project LaunchManager.xcodeproj \
  -scheme LaunchManager \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  AD_HOC_CODE_SIGNING_ALLOWED=YES \
  DEVELOPMENT_TEAM="" \
  2>&1 | grep -E "error:|ARCHIVE|BUILD SUCCEEDED|BUILD FAILED" || true

if [ ! -d "$ARCHIVE_PATH" ]; then
  echo "✗ Archive failed"
  exit 1
fi

echo "▶ Packaging DMG..."
APP_PATH=$(find "$ARCHIVE_PATH" -name "LaunchManager.app" -maxdepth 5 | head -1)
"$SCRIPT_DIR/package-dmg.sh" "$APP_PATH" "$DMG_PATH"

SHA256=$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')
echo ""
echo "✓ DMG: $DMG_PATH ($(du -sh "$DMG_PATH" | cut -f1))"
echo "  SHA256: $SHA256"
