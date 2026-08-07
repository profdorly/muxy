#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT"

if ! command -v npx &>/dev/null; then
  echo "npx not found. Install Node.js to run the duplication check."
  exit 1
fi

npx --yes jscpd@4.0.5 --config .jscpd.json .
