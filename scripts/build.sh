#!/usr/bin/env bash
# Builds build/Release/<app name>.app from project.yml.
#
#   scripts/build.sh [--test] [--release]
#
# Without --release this is the Dev configuration: Release plus the development aids (TOOLSMITH_DEV:
# command-line flags, the stand-in fan helper), signed with the local development identity.
# --release builds what the team gets (the Release configuration, unsigned here; scripts/release.sh
# signs it). TOOLSMITH_BUILD_NUMBER overrides CURRENT_PROJECT_VERSION (CI passes its run number).
set -euo pipefail

TEST=0
RELEASE=0
for arg in "$@"; do
  case "$arg" in
    --test) TEST=1 ;;
    --release) RELEASE=1 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source scripts/identity.sh

# Naming the destination keeps xcodebuild from warning about (and guessing between) arm64 and x86_64.
DEST="platform=macOS,arch=$(uname -m)"
CONFIG=$([[ $RELEASE == 1 ]] && echo Release || echo Dev)
PRODUCT="build/DerivedData/Build/Products/$CONFIG/$APP_NAME.app"
BUILD_SETTINGS=()
[[ -n "${TOOLSMITH_BUILD_NUMBER:-}" ]] && BUILD_SETTINGS+=("CURRENT_PROJECT_VERSION=$TOOLSMITH_BUILD_NUMBER")
[[ -n "${TOOLSMITH_VERSION:-}" ]] && BUILD_SETTINGS+=("MARKETING_VERSION=$TOOLSMITH_VERSION")

echo "==> design lint"
scripts/lint-design.sh

echo "==> app ($CONFIG)"
xcodegen generate --quiet
xcodebuild -project Toolsmith.xcodeproj -scheme Toolsmith -configuration "$CONFIG" \
  -derivedDataPath build/DerivedData -destination "$DEST" -quiet build ${BUILD_SETTINGS[@]+"${BUILD_SETTINGS[@]}"}
rm -rf "build/Release"
mkdir -p build/Release
cp -R "$PRODUCT" build/Release/
APP="$APP_PATH"

if [[ $RELEASE == 1 ]]; then
  # The development aids must never reach the team. Their command-line flags are a sure sign.
  if strings "$APP/Contents/MacOS/$APP_NAME" | grep -q -- "--print-system-sample"; then
    echo "release build contains development code (TOOLSMITH_DEV); refusing" >&2
    exit 1
  fi
  echo "signed: ad-hoc (release build; scripts/release.sh signs it)"
else
  # Sign with the developer's local identity when there is one. An ad-hoc signature changes with
  # every build, and macOS ties the Accessibility and Screen Recording grants to the signature:
  # the switches stay on in System Settings but the new build no longer has the permission.
  # Create the identity once: a self-signed code-signing certificate named "<app name> Dev" in the
  # login keychain (see CLAUDE.md). Without it the app stays ad-hoc signed.
  SIGN_IDENTITY="${TOOLSMITH_DEV_SIGN_IDENTITY:-$APP_NAME Dev}"
  if security find-identity -p codesigning 2>/dev/null | grep -q "\"$SIGN_IDENTITY\""; then
    codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$APP/Contents/Frameworks/ToolsmithKit.framework" 2>/dev/null
    codesign --force --sign "$SIGN_IDENTITY" --timestamp=none --identifier "$APP_BUNDLE_ID.helper" "$APP/Contents/MacOS/ToolsmithHelper" 2>/dev/null
    codesign --force --sign "$SIGN_IDENTITY" --timestamp=none --entitlements App/Main/Toolsmith.entitlements "$APP" 2>/dev/null
    echo "signed: $SIGN_IDENTITY"
  else
    echo "signed: ad-hoc (no \"$SIGN_IDENTITY\" identity; permissions will need re-granting after each build)"
  fi
fi

# Leave exactly one copy of the app on disk. macOS finds apps by bundle ID, so a second copy in
# the build folder can be the one it launches.
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister
"$LSREGISTER" -u "$ROOT/$PRODUCT" >/dev/null 2>&1 || true
rm -rf "$PRODUCT"
"$LSREGISTER" -f "$ROOT/$APP" >/dev/null 2>&1 || true

if [[ $TEST == 1 ]]; then
  echo "==> tests"
  # Tests get their own derived data: sharing one build database with the app build above fails
  # now and then with "accessing build database … disk I/O error".
  xcodebuild -project Toolsmith.xcodeproj -scheme ToolsmithKitTests -configuration Debug \
    -derivedDataPath build/DerivedDataTests -destination "$DEST" -quiet test
fi

echo "built: $APP"
