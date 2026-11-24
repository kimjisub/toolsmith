# Sourced by the other scripts: the app's identity as project.yml sets it (its only home).
#   APP_NAME, APP_BUNDLE_ID, APP_TEAM_ID, APP_UPDATE_REPOSITORY, APP_PATH (the built app)
_identity_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_identity() {
  sed -n "s/^ *$1: *\"\{0,1\}\([^\"]*\)\"\{0,1\} *\$/\1/p" "$_identity_root/project.yml" | head -1
}
APP_NAME="$(_identity APP_NAME)"
APP_BUNDLE_ID="$(_identity APP_BUNDLE_ID)"
APP_TEAM_ID="$(_identity APP_TEAM_ID)"
APP_UPDATE_REPOSITORY="$(_identity APP_UPDATE_REPOSITORY)"
APP_PATH="build/Release/$APP_NAME.app"
[[ -n "$APP_NAME" && -n "$APP_BUNDLE_ID" ]] || { echo "project.yml has no APP_NAME or APP_BUNDLE_ID" >&2; exit 1; }
