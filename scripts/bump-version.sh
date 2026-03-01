#!/bin/bash
set -euo pipefail

# Usage: ./scripts/bump-version.sh <major|minor|patch>
# Bumps MARKETING_VERSION (semver) and CURRENT_PROJECT_VERSION (build number)
# in the Xcode project file. Outputs old/new values for CI to parse.

PBXPROJ="RemoteShutter.xcodeproj/project.pbxproj"
BUMP_TYPE="${1:?Usage: bump-version.sh <major|minor|patch>}"

if [[ ! -f "$PBXPROJ" ]]; then
    echo "Error: $PBXPROJ not found. Run from the repo root." >&2
    exit 1
fi

# Extract current version (first occurrence)
CURRENT_VERSION=$(grep -m1 'MARKETING_VERSION = ' "$PBXPROJ" | sed 's/.*= //;s/;.*//' | tr -d ' ')

# Normalize to semver (4.14 -> 4.14.0)
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"
PATCH="${PATCH:-0}"

case "$BUMP_TYPE" in
    major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
    minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
    patch) PATCH=$((PATCH + 1)) ;;
    *) echo "Error: Invalid bump type '$BUMP_TYPE'. Use major, minor, or patch." >&2; exit 1 ;;
esac

NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"

# Extract and increment build number
CURRENT_BUILD=$(grep -m1 'CURRENT_PROJECT_VERSION = ' "$PBXPROJ" | sed 's/.*= //;s/;.*//' | tr -d ' ')
NEW_BUILD=$((CURRENT_BUILD + 1))

# Replace all occurrences in pbxproj (Debug + Release configs)
sed -i '' "s/MARKETING_VERSION = ${CURRENT_VERSION}/MARKETING_VERSION = ${NEW_VERSION}/g" "$PBXPROJ"
sed -i '' "s/CURRENT_PROJECT_VERSION = ${CURRENT_BUILD}/CURRENT_PROJECT_VERSION = ${NEW_BUILD}/g" "$PBXPROJ"

echo "Version: ${CURRENT_VERSION} -> ${NEW_VERSION}"
echo "Build: ${CURRENT_BUILD} -> ${NEW_BUILD}"
