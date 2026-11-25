#!/usr/bin/env bash
# Builds the DMG the team installs: Developer ID signature, hardened runtime, Apple notarization.
#
#   scripts/release.sh [--adhoc] [--skip-build]
#
# --adhoc       ad-hoc signature, no notarization. Only for checking the pipeline on a Mac without the certificate.
# --skip-build  sign the existing build/Release app (it must come from `scripts/build.sh --release`).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source scripts/identity.sh

ADHOC=0
BUILD=1
for arg in "$@"; do
  case "$arg" in
    --adhoc) ADHOC=1 ;;
    --skip-build) BUILD=0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

IDENTITY="${TOOLSMITH_SIGN_IDENTITY:-Developer ID Application: jisub kim ($APP_TEAM_ID)}"
KEYCHAIN="${TOOLSMITH_SIGNING_KEYCHAIN:-$HOME/Library/Keychains/toolsmith-signing.keychain-db}"
# Optional 1Password references (op://vault/item/field) for the keychain password and the notary
# app password, used when the values are not in the environment. Maintainers keep theirs outside the repo.
KEYCHAIN_ITEM="${TOOLSMITH_SIGNING_KEYCHAIN_OP_REF:-}"
NOTARY_PROFILE="${TOOLSMITH_NOTARY_PROFILE:-toolsmith-notary}"
NOTARY_ITEM="${TOOLSMITH_NOTARY_OP_REF:-}"
ENTITLEMENTS="App/Main/Toolsmith.entitlements"

if [[ $ADHOC == 1 ]]; then
  IDENTITY="-"
  echo "==> ad-hoc: no Developer ID, no notarization. This DMG is for checking the pipeline only."
else
  [[ -f "$KEYCHAIN" ]] || { echo "signing keychain missing: $KEYCHAIN (see docs/release.md)" >&2; exit 1; }
  if [[ -z "${TOOLSMITH_SIGNING_KEYCHAIN_PASSWORD:-}" ]]; then
    [[ -n "$KEYCHAIN_ITEM" ]] || { echo "set TOOLSMITH_SIGNING_KEYCHAIN_PASSWORD or TOOLSMITH_SIGNING_KEYCHAIN_OP_REF (see docs/release.md)" >&2; exit 1; }
    TOOLSMITH_SIGNING_KEYCHAIN_PASSWORD="$(op read "$KEYCHAIN_ITEM")"
  fi
  security unlock-keychain -p "$TOOLSMITH_SIGNING_KEYCHAIN_PASSWORD" "$KEYCHAIN"
  trap 'security lock-keychain "$KEYCHAIN"' EXIT
  if ! security find-identity -v -p codesigning "$KEYCHAIN" | grep -qF "\"$IDENTITY\""; then
    echo "signing identity not in $KEYCHAIN: $IDENTITY (see docs/release.md, or use --adhoc)" >&2
    exit 1
  fi
fi

if [[ $BUILD == 1 ]]; then
  scripts/build.sh --release
fi
BUILT="build/Release/$APP_NAME.app"
[[ -d "$BUILT" ]] || { echo "missing $BUILT; run without --skip-build" >&2; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$BUILT/Contents/Info.plist")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$BUILT/Contents/Info.plist")"
STAGE="build/release-stage"
APP="$STAGE/$APP_NAME.app"
rm -rf "$STAGE"
mkdir -p "$STAGE" dist
ditto "$BUILT" "$APP"

sign() {
  local flags=(--force --sign "$IDENTITY")
  [[ $ADHOC == 1 ]] || flags+=(--options runtime --timestamp --keychain "$KEYCHAIN")
  codesign "${flags[@]}" "$@"
}
echo "==> sign ($IDENTITY)"
for framework in "$APP"/Contents/Frameworks/*.framework; do
  sign "$framework"
done
# The charge-control helper: its own identifier, hardened runtime (sign adds it), before the app.
if [[ -f "$APP/Contents/MacOS/ToolsmithHelper" ]]; then
  sign --identifier "$APP_BUNDLE_ID.helper" "$APP/Contents/MacOS/ToolsmithHelper"
fi
# The command line tool, likewise.
if [[ -f "$APP/Contents/Helpers/toolsmith" ]]; then
  sign --identifier "$APP_BUNDLE_ID.cli" "$APP/Contents/Helpers/toolsmith"
fi
sign --entitlements "$ENTITLEMENTS" "$APP"
codesign --verify --deep --strict "$APP"

DMG="dist/${APP_NAME// /}-$VERSION.dmg"
echo "==> dmg"
DMG_ROOT="$STAGE/dmg"
mkdir -p "$DMG_ROOT"
ditto "$APP" "$DMG_ROOT/$APP_NAME.app"
ln -s /Applications "$DMG_ROOT/Applications"
rm -f "$DMG"
hdiutil create -quiet -volname "$APP_NAME $VERSION" -srcfolder "$DMG_ROOT" -fs HFS+ -format UDZO "$DMG"
if [[ $ADHOC == 1 ]]; then
  codesign --force --sign - "$DMG"
else
  codesign --force --sign "$IDENTITY" --timestamp --keychain "$KEYCHAIN" "$DMG"
fi

if [[ $ADHOC == 0 ]]; then
  # Three places for the notarization credentials, first one found wins: the environment (CI),
  # the saved notarytool profile, 1Password. The profile lives in the login session's keychain,
  # which a background session (ssh, an agent) cannot always read.
  if [[ -n "${TOOLSMITH_NOTARY_APPLE_ID:-}" ]]; then
    echo "==> notarize (credentials from the environment)"
    NOTARY_AUTH=(--apple-id "$TOOLSMITH_NOTARY_APPLE_ID" --team-id "$TOOLSMITH_NOTARY_TEAM_ID"
      --password "$TOOLSMITH_NOTARY_PASSWORD")
  elif xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "==> notarize (profile $NOTARY_PROFILE)"
    NOTARY_AUTH=(--keychain-profile "$NOTARY_PROFILE")
  else
    [[ -n "$NOTARY_ITEM" ]] || { echo "no notarization credentials: set TOOLSMITH_NOTARY_APPLE_ID/TEAM_ID/PASSWORD, the $NOTARY_PROFILE profile, or TOOLSMITH_NOTARY_OP_REF" >&2; exit 1; }
    echo "==> notarize (app password from 1Password)"
    NOTARY_AUTH=(--apple-id "$(op read "$NOTARY_ITEM/username")" --team-id "$(op read "$NOTARY_ITEM/team id")"
      --password "$(op read "$NOTARY_ITEM/password")")
  fi
  xcrun notarytool submit "$DMG" "${NOTARY_AUTH[@]}" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  MOUNT="$(mktemp -d)"
  hdiutil attach -quiet -nobrowse -readonly -mountpoint "$MOUNT" "$DMG"
  spctl --assess --type execute --verbose "$MOUNT/$APP_NAME.app"
  hdiutil detach -quiet "$MOUNT"
fi

SHA256="$(shasum -a 256 "$DMG" | awk '{print $1}')"
echo "$SHA256  $(basename "$DMG")" > "$DMG.sha256"
echo "built: $DMG (version $VERSION build $BUILD_NUMBER, $(stat -f %z "$DMG") bytes, sha256 $SHA256)"
