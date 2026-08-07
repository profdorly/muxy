#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "Muxy is a macOS 14+ SwiftUI app: full builds and 'swift run Muxy' require macOS with Xcode."
echo "This container provides the Swift toolchain plus repo tooling for:"
echo "  - editing and reviewing code"
echo "  - documentation checks:        scripts/check-agents-md.sh"
echo "  - unused dependency checks:    scripts/check-unused-deps.sh"
echo "  - duplicate code checks:       scripts/check-duplicates.sh"

if ! command -v python3 &>/dev/null; then
  apt-get update -qq && apt-get install -y -qq python3
fi

if command -v swiftformat &>/dev/null; then
  echo "swiftformat available"
else
  echo "NOTE: swiftformat/swiftlint are macOS-only tools; run scripts/checks.sh on a Mac."
fi
