#!/bin/bash
# Bump version, finalize CHANGELOG, commit, tag, and push to trigger CI release.
#
# Usage:
#   ./scripts/release.sh patch              # 1.6.2 → 1.6.3
#   ./scripts/release.sh minor              # 1.6.2 → 1.7.0
#   ./scripts/release.sh major              # 1.6.2 → 2.0.0
#   ./scripts/release.sh 1.7.0              # explicit version
#   ./scripts/release.sh patch --dry-run    # preview only, no git changes
#
# Prerequisites:
#   - Update CHANGELOG.md [Unreleased] section before running
#   - GitHub Actions builds DMG + updates Homebrew tap on tag push
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION_FILE="$PROJECT_DIR/Version.xcconfig"
CHANGELOG="$PROJECT_DIR/CHANGELOG.md"

BUMP=""
DRY_RUN=false

usage() {
  echo "Usage: ./scripts/release.sh <patch|minor|major|X.Y.Z> [--dry-run]"
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    patch|minor|major)
      BUMP="$1"
      ;;
    --dry-run)
      DRY_RUN=true
      ;;
    -h|--help)
      usage
      ;;
    *)
      if [ -z "$BUMP" ] && [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        BUMP="$1"
      else
        echo "Unknown argument: $1"
        usage
      fi
      ;;
  esac
  shift
done

[ -n "$BUMP" ] || usage

read_version() {
  grep '^MARKETING_VERSION' "$VERSION_FILE" | sed 's/.*= *//'
}

read_build() {
  grep '^CURRENT_PROJECT_VERSION' "$VERSION_FILE" | sed 's/.*= *//'
}

current_version=$(read_version)
IFS='.' read -r MAJOR MINOR PATCH <<< "$current_version"

case "$BUMP" in
  patch)
    PATCH=$((PATCH + 1))
    NEW_VERSION="$MAJOR.$MINOR.$PATCH"
    ;;
  minor)
    MINOR=$((MINOR + 1))
    PATCH=0
    NEW_VERSION="$MAJOR.$MINOR.$PATCH"
    ;;
  major)
    MAJOR=$((MAJOR + 1))
    MINOR=0
    PATCH=0
    NEW_VERSION="$MAJOR.$MINOR.$PATCH"
    ;;
  *)
    NEW_VERSION="$BUMP"
    ;;
esac

NEW_BUILD=$(( $(read_build) + 1 ))
TAG="v$NEW_VERSION"
TODAY=$(date +%Y-%m-%d)

echo "▶ Release $TAG (build $NEW_BUILD)"
echo "  Current: v$current_version (build $(read_build))"
echo ""

# ── Validate CHANGELOG [Unreleased] has content ─────────────
unreleased_has_content() {
  awk '
    /^## \[Unreleased\]/ { in_unreleased=1; next }
    in_unreleased && /^## \[/ { exit }
    in_unreleased && /^### / { found=1; exit }
    in_unreleased && /^- / { found=1; exit }
    END { exit !found }
  ' "$CHANGELOG"
}

if ! unreleased_has_content; then
  echo "✗ CHANGELOG.md [Unreleased] is empty."
  echo "  Add bullets under ## [Unreleased] before releasing."
  exit 1
fi

cd "$PROJECT_DIR"
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "✗ Working tree has uncommitted changes. Commit or stash first."
  exit 1
fi

if [ "$DRY_RUN" = true ]; then
  echo "[dry-run] Would release $TAG (build $NEW_BUILD)"
  echo "[dry-run] Would finalize CHANGELOG and push tag to trigger CI"
  exit 0
fi

# ── Bump Version.xcconfig ───────────────────────────────────
sed -i '' "s/^MARKETING_VERSION = .*/MARKETING_VERSION = $NEW_VERSION/" "$VERSION_FILE"
sed -i '' "s/^CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = $NEW_BUILD/" "$VERSION_FILE"
echo "✓ Version.xcconfig → $NEW_VERSION ($NEW_BUILD)"

# ── Finalize CHANGELOG ──────────────────────────────────────
# Replace [Unreleased] header with dated version section; insert fresh [Unreleased].
TMP_CHANGELOG=$(mktemp)
awk -v ver="$NEW_VERSION" -v date="$TODAY" '
  /^## \[Unreleased\]/ {
    print "## [Unreleased]"
    print ""
    print "<!-- Add changes here as you develop. Run ./scripts/release.sh patch to publish. -->"
    print ""
    print "## [" ver "] - " date
    in_unreleased=1
    next
  }
  in_unreleased && /^## \[/ { in_unreleased=0 }
  in_unreleased && /^<!--/ { next }
  !in_unreleased { print }
  in_unreleased { print }
' "$CHANGELOG" > "$TMP_CHANGELOG"
mv "$TMP_CHANGELOG" "$CHANGELOG"
echo "✓ CHANGELOG.md finalized for $TAG"

# ── Git commit + tag + push ─────────────────────────────────
git add "$VERSION_FILE" "$CHANGELOG"
git commit -m "chore(release): $TAG"
git tag "$TAG"
echo "✓ Committed and tagged $TAG"

echo "▶ Pushing to origin (triggers GitHub Actions release)..."
git push origin HEAD
git push origin "$TAG"

echo ""
echo "🎉 $TAG pushed — CI will build DMG and update Homebrew tap."
echo "   Actions: https://github.com/Sean10000/LaunchManager/actions"
echo "   Release: https://github.com/Sean10000/LaunchManager/releases/tag/$TAG"
