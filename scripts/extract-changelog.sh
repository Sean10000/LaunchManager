#!/bin/bash
# Extract a version section from CHANGELOG.md for GitHub release notes.
# Usage: ./scripts/extract-changelog.sh 1.6.2
set -euo pipefail

VERSION="${1:?Usage: extract-changelog.sh X.Y.Z}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHANGELOG="$SCRIPT_DIR/../CHANGELOG.md"

{
  echo "## LaunchManager v$VERSION"
  echo ""
  awk -v ver="$VERSION" '
    BEGIN { found=0 }
    /^## \[/ {
      if (found) exit
      if ($0 ~ "^## \\[" ver "\\]") { found=1; next }
    }
    found && /^## \[/ { exit }
    found { print }
  ' "$CHANGELOG"
} | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' 
