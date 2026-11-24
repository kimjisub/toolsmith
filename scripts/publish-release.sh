#!/usr/bin/env bash
# CI only: publishes the signed DMG in dist/ as a GitHub release of the given repository, with
# release.json beside it: what the app's update check reads (version, build, checksum).
#
#   GH_TOKEN=... scripts/publish-release.sh <owner/repo>
set -euo pipefail

REPO="${1:?owner/repo}"
cd "$(cd "$(dirname "$0")/.." && pwd)"
source scripts/identity.sh
APP="$APP_PATH"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
DMG="dist/${APP_NAME// /}-$VERSION.dmg"
[[ -f "$DMG" ]] || { echo "missing $DMG" >&2; exit 1; }
SHA256="$(shasum -a 256 "$DMG" | awk '{print $1}')"
SIZE="$(stat -f %z "$DMG")"
TAG="v$VERSION"

# What changed since the previous tag, one line per commit, as the release notes.
PREVIOUS="$(git describe --tags --abbrev=0 "$TAG^" 2>/dev/null || true)"
NOTES="$(git log --format='- %s' ${PREVIOUS:+"$PREVIOUS..$TAG"} | head -40)"

python3 - "$VERSION" "$BUILD" "$SHA256" "$SIZE" "$(basename "$DMG")" > dist/release.json <<'PY'
import json, sys
version, build, sha256, size, dmg = sys.argv[1:]
print(json.dumps({"version": version, "build": int(build), "sha256": sha256, "size": int(size), "dmg": dmg}, indent=2))
PY

# The tag already exists here; elsewhere the release creates it on that repository's default branch.
gh release create "$TAG" "$DMG" dist/release.json --repo "$REPO" --title "$APP_NAME $VERSION" --notes "${NOTES:-$APP_NAME $VERSION}"
echo "published $TAG to $REPO"
