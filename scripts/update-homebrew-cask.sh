#!/usr/bin/env bash
# CI only, after publish-release.sh: points the Homebrew cask at the release just published by
# rewriting its version and sha256 (from dist/release.json) and pushing to the tap repository.
#
#   HOMEBREW_TAP_KEY=<private deploy key with write access> scripts/update-homebrew-cask.sh
#
# The tap and cask are set by HOMEBREW_TAP (default kimjisub/homebrew-tap) and HOMEBREW_CASK
# (default: the app name in lower case). See docs/release.md.
set -euo pipefail

cd "$(cd "$(dirname "$0")/.." && pwd)"
source scripts/identity.sh

TAP="${HOMEBREW_TAP:-kimjisub/homebrew-tap}"
CASK="${HOMEBREW_CASK:-$(echo "$APP_NAME" | tr '[:upper:]' '[:lower:]')}"
: "${HOMEBREW_TAP_KEY:?HOMEBREW_TAP_KEY is not set}"

read -r VERSION SHA256 < <(python3 -c 'import json; r = json.load(open("dist/release.json")); print(r["version"], r["sha256"])')

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
printf '%s\n' "$HOMEBREW_TAP_KEY" > "$WORK/key"
chmod 600 "$WORK/key"
export GIT_SSH_COMMAND="ssh -i $WORK/key -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"

git clone --quiet --depth 1 "git@github.com:$TAP.git" "$WORK/tap"
FILE="$WORK/tap/Casks/$CASK.rb"
[[ -f "$FILE" ]] || { echo "no cask at Casks/$CASK.rb in $TAP" >&2; exit 1; }

sed -i '' -E \
  -e "s/^  version \"[^\"]*\"/  version \"$VERSION\"/" \
  -e "s/^  sha256 \"[^\"]*\"/  sha256 \"$SHA256\"/" \
  "$FILE"

cd "$WORK/tap"
if git diff --quiet; then
  echo "cask $CASK already at $VERSION"
  exit 0
fi
git -c user.name="github-actions[bot]" -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
  commit --quiet -am "$CASK $VERSION"
git push --quiet origin HEAD
echo "cask $CASK -> $VERSION in $TAP"
