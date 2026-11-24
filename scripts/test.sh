#!/usr/bin/env bash
# Runs only the XCTest suite (Debug). scripts/build.sh --test is the full check.
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"
xcodegen generate --quiet
xcodebuild -project Toolsmith.xcodeproj -scheme ToolsmithKitTests -configuration Debug \
  -derivedDataPath build/DerivedDataTests -destination "platform=macOS,arch=$(uname -m)" -quiet test
