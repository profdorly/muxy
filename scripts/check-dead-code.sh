#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BASELINE="$REPO_ROOT/.dead-code-baseline.json"

UPDATE=0
for arg in "$@"; do
  case "$arg" in
    --update-baseline) UPDATE=1 ;;
  esac
done

cd "$REPO_ROOT"

if ! command -v periphery &>/dev/null; then
  echo "periphery not found. Install with: brew install periphery"
  exit 1
fi

REPORT=$(mktemp)
trap 'rm -f "$REPORT"' EXIT

periphery scan --quiet > "$REPORT" || true

BASELINE_PATH="$BASELINE" UPDATE_BASELINE="$UPDATE" REPORT_PATH="$REPORT" python3 <<'PY'
import json
import os
import re
import sys

baseline_path = os.environ["BASELINE_PATH"]
report_path = os.environ["REPORT_PATH"]
update = os.environ["UPDATE_BASELINE"] == "1"

pattern = re.compile(r"^(?P<file>.*?):(?P<line>\d+):(?P<col>\d+): warning: (?P<message>.*)$")

current = {}
rows = []
with open(report_path) as handle:
    for raw in handle:
        match = pattern.match(raw.strip())
        if not match:
            continue
        relative = os.path.relpath(match.group("file"), os.getcwd())
        kind = match.group("message").split(" ")[0]
        key = "{}|{}".format(relative, kind)
        current[key] = current.get(key, 0) + 1
        rows.append((relative, match.group("line"), match.group("message")))

if update:
    with open(baseline_path, "w") as handle:
        json.dump(dict(sorted(current.items())), handle, indent=2)
        handle.write("\n")
    print("Baseline updated with {} warning(s) across {} bucket(s)".format(sum(current.values()), len(current)))
    sys.exit(0)

if not os.path.exists(baseline_path):
    print("Baseline not found at {}".format(baseline_path))
    print("Run: scripts/check-dead-code.sh --update-baseline")
    sys.exit(1)

with open(baseline_path) as handle:
    baseline = json.load(handle)

regressions = []
improvements = 0
for key, count in sorted(current.items()):
    allowed = baseline.get(key, 0)
    if count > allowed:
        regressions.append((key, allowed, count))
    elif count < allowed:
        improvements += allowed - count
for key, allowed in sorted(baseline.items()):
    if key not in current:
        improvements += allowed

total = sum(current.values())
print("Dead code scan: {} warning(s)".format(total))
for relative, line, message in rows[:25]:
    print("  {}:{}: {}".format(relative, line, message))
if len(rows) > 25:
    print("  ... and {} more".format(len(rows) - 25))

if improvements:
    print("Dead code reduced by {} warning(s) since baseline; consider running scripts/check-dead-code.sh --update-baseline".format(improvements))

if regressions:
    print("")
    print("New dead code detected (baseline must not grow):")
    for key, allowed, count in regressions:
        print("  {}: {} -> {}".format(key, allowed, count))
    print("")
    print("Remove the new unused declarations, or clean up existing debt and regenerate the baseline.")
    sys.exit(1)

print("Dead code within baseline")
PY
