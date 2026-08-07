#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG="$REPO_ROOT/.swiftlint-health.yml"
BASELINE="$REPO_ROOT/.code-health-baseline.json"

UPDATE=0
for arg in "$@"; do
  case "$arg" in
    --update-baseline) UPDATE=1 ;;
  esac
done

cd "$REPO_ROOT"

REPORT=$(mktemp)
trap 'rm -f "$REPORT"' EXIT

swiftlint lint --quiet --config "$CONFIG" --reporter json > "$REPORT" || true

BASELINE_PATH="$BASELINE" UPDATE_BASELINE="$UPDATE" REPORT_PATH="$REPORT" python3 <<'PY'
import json
import os
import sys

baseline_path = os.environ["BASELINE_PATH"]
report_path = os.environ["REPORT_PATH"]
update = os.environ["UPDATE_BASELINE"] == "1"

with open(report_path) as handle:
    violations = json.load(handle)

current = {}
for violation in violations:
    key = "{}|{}|{}".format(violation["rule_id"], violation["severity"], violation["file"])
    current[key] = current.get(key, 0) + 1

if update:
    with open(baseline_path, "w") as handle:
        json.dump(dict(sorted(current.items())), handle, indent=2)
        handle.write("\n")
    total = sum(current.values())
    print("Baseline updated with {} violation(s) across {} bucket(s)".format(total, len(current)))
    sys.exit(0)

if not os.path.exists(baseline_path):
    print("Baseline not found at {}".format(baseline_path))
    print("Run: scripts/check-code-health.sh --update-baseline")
    sys.exit(1)

with open(baseline_path) as handle:
    baseline = json.load(handle)

regressions = []
improvements = []
for key, count in sorted(current.items()):
    allowed = baseline.get(key, 0)
    if count > allowed:
        regressions.append((key, allowed, count))
    elif count < allowed:
        improvements.append((key, allowed, count))

for key, allowed in sorted(baseline.items()):
    if key not in current:
        improvements.append((key, allowed, 0))

totals = {}
for violation in violations:
    bucket = "{} ({})".format(violation["rule_id"], violation["severity"])
    totals[bucket] = totals.get(bucket, 0) + 1

print("Code health violations: " + (", ".join("{} {}".format(n, b) for b, n in sorted(totals.items())) if totals else "none"))

if improvements:
    reduced = sum(old - new for _, old, new in improvements)
    print("Debt reduced by {} violation(s) since baseline; consider running scripts/check-code-health.sh --update-baseline".format(reduced))

if regressions:
    print("")
    print("New complexity or file-size debt detected (baseline must not grow):")
    for key, allowed, count in regressions:
        rule, severity, path = key.split("|", 2)
        print("  {} [{}]: {} -> {} in {}".format(rule, severity, allowed, count, path))
    print("")
    print("Refactor the new violations away, or pay down existing debt and regenerate the baseline.")
    sys.exit(1)

print("Code health within baseline")
PY
