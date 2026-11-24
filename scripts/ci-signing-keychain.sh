#!/usr/bin/env bash
# CI only: builds a throwaway keychain holding the Developer ID certificate, for scripts/release.sh.
# The runner is discarded after the job, so nothing here outlives it.
#
#   scripts/ci-signing-keychain.sh <keychain path>
#
# Reads DEVELOPER_ID_P12_BASE64, DEVELOPER_ID_P12_PASSWORD and TOOLSMITH_SIGNING_KEYCHAIN_PASSWORD.
set -euo pipefail

KEYCHAIN="${1:?keychain path}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

security create-keychain -p "$TOOLSMITH_SIGNING_KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 3600 "$KEYCHAIN"
security unlock-keychain -p "$TOOLSMITH_SIGNING_KEYCHAIN_PASSWORD" "$KEYCHAIN"

printf '%s' "$DEVELOPER_ID_P12_BASE64" | base64 -d > "$WORK/developer-id.p12"
security import "$WORK/developer-id.p12" -k "$KEYCHAIN" -f pkcs12 -P "$DEVELOPER_ID_P12_PASSWORD" -T /usr/bin/codesign
# The .p12 holds only the leaf certificate. Without Apple's intermediate the identity is not valid.
curl -fsS -o "$WORK/DeveloperIDG2CA.cer" https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer
# Runner images already carry it in the system keychain; then the import reports it exists, which is fine.
security import "$WORK/DeveloperIDG2CA.cer" -k "$KEYCHAIN" 2>/dev/null || echo "Developer ID G2 intermediate already present"
# Lets codesign use the key without a dialog nobody can answer.
security set-key-partition-list -S apple-tool:,apple: -s -k "$TOOLSMITH_SIGNING_KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
# codesign builds the certificate chain from the search list.
security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')
