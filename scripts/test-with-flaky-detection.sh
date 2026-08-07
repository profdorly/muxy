#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT"

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

FIRST_XML="$WORK_DIR/first.xml"
RETRY_XML="$WORK_DIR/retry.xml"

extract_failures() {
  python3 - "$1" <<'PY'
import re
import sys
import xml.etree.ElementTree as ET

tree = ET.parse(sys.argv[1])
failed = []
for testcase in tree.iter("testcase"):
    if testcase.find("failure") is None and testcase.find("error") is None:
        continue
    suite = testcase.get("classname", "").split(".")[-1]
    name = re.sub(r"\(\)$", "", testcase.get("name", ""))
    if suite and name:
        failed.append("{}/{}".format(suite, name))
print("\n".join(sorted(set(failed))))
PY
}

summarize_retry() {
  python3 - "$FIRST_XML" "$RETRY_XML" <<'PY'
import re
import sys
import xml.etree.ElementTree as ET

def outcomes(path):
    tree = ET.parse(path)
    result = {}
    for testcase in tree.iter("testcase"):
        suite = testcase.get("classname", "").split(".")[-1]
        name = re.sub(r"\(\)$", "", testcase.get("name", ""))
        key = "{}/{}".format(suite, name)
        if testcase.find("failure") is not None or testcase.find("error") is not None:
            result[key] = "failed"
        else:
            result.setdefault(key, "passed")
    return result

first = outcomes(sys.argv[1])
retry = outcomes(sys.argv[2])

flaky = sorted(key for key, status in first.items() if status == "failed" and retry.get(key) == "passed")
still_failing = sorted(key for key, status in first.items() if status == "failed" and retry.get(key) != "passed")

if flaky:
    print("FLAKY")
    for key in flaky:
        print(key)
if still_failing:
    print("FAILING")
    for key in still_failing:
        print(key)
PY
}

echo "Running full test suite"
scripts/run-tests-isolated.sh swift test --xunit-output "$FIRST_XML" --quiet
FIRST_STATUS=$?

if [ "$FIRST_STATUS" -eq 0 ]; then
  echo "All tests passed on the first run"
  exit 0
fi

FAILED_TESTS=$(extract_failures "$FIRST_XML")
if [ -z "$FAILED_TESTS" ]; then
  echo "Tests failed but no individual failures could be parsed from $FIRST_XML"
  exit "$FIRST_STATUS"
fi

COUNT=$(printf '%s\n' "$FAILED_TESTS" | wc -l | tr -d ' ')
echo "Re-running $COUNT failed test(s) to check for flakiness"
FILTER=$(printf '%s\n' "$FAILED_TESTS" | paste -sd '|' -)

scripts/run-tests-isolated.sh swift test --xunit-output "$RETRY_XML" --quiet --filter "$FILTER"
RETRY_STATUS=$?

REPORT=$(summarize_retry)
FLAKY=$(printf '%s\n' "$REPORT" | awk '/^FLAKY$/{flag=1;next}/^FAILING$/{flag=0}flag')
STILL_FAILING=$(printf '%s\n' "$REPORT" | awk '/^FAILING$/{flag=1;next}/^FLAKY$/{flag=0}flag')

if [ -n "$FLAKY" ]; then
  echo ""
  echo "Flaky tests detected (failed first, passed on retry):"
  printf '%s\n' "$FLAKY" | sed 's/^/  - /'
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
      echo "## Flaky tests detected"
      echo ""
      printf '%s\n' "$FLAKY" | sed 's/^/- [ ] `/;s/$/`/'
      echo ""
      echo "These tests failed on the first run and passed on retry. Please stabilize or quarantine them."
    } >> "$GITHUB_STEP_SUMMARY"
  fi
fi

if [ "$RETRY_STATUS" -ne 0 ] || [ -n "$STILL_FAILING" ]; then
  echo ""
  echo "Tests still failing after retry:"
  printf '%s\n' "$STILL_FAILING" | sed 's/^/  - /'
  exit 1
fi

exit 0
