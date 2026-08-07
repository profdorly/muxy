#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT"

python3 <<'PY'
import re
import sys
from pathlib import Path

failures = []

agents = Path("AGENTS.md")
if not agents.exists():
    failures.append("AGENTS.md is missing")
    content = ""
else:
    content = agents.read_text()
    if len(content) < 100:
        failures.append("AGENTS.md is too short to be useful (<100 chars)")

docs = {
    "AGENTS.md": content,
    "README.md": Path("README.md").read_text() if Path("README.md").exists() else "",
    "CONTRIBUTING.md": Path("CONTRIBUTING.md").read_text() if Path("CONTRIBUTING.md").exists() else "",
}

for name, text in docs.items():
    if not text:
        failures.append("{} is missing or empty".format(name))
        continue
    for referenced in sorted(set(re.findall(r"scripts/[A-Za-z0-9._-]+\.sh", text))):
        path = Path(referenced)
        if not path.exists():
            failures.append("{} references missing script '{}'".format(name, referenced))
        elif not path.stat().st_mode & 0o111:
            failures.append("{} references non-executable script '{}'".format(name, referenced))

combined = "\n".join(docs.values())

if "swiftformat" in combined and not Path(".swiftformat").exists():
    failures.append("docs mention swiftformat but .swiftformat config is missing")
if "swiftlint" in combined and not Path(".swiftlint.yml").exists():
    failures.append("docs mention swiftlint but .swiftlint.yml config is missing")
if "swift build" in combined and not Path("Package.swift").exists():
    failures.append("docs mention swift build but Package.swift is missing")

tool_versions = Path(".tool-versions")
if tool_versions.exists():
    for tool in ("swiftformat", "swiftlint"):
        if tool in combined and tool not in tool_versions.read_text():
            failures.append("docs require {} but it is not pinned in .tool-versions".format(tool))

if failures:
    print("AGENTS.md validation failed:")
    for failure in failures:
        print("  - {}".format(failure))
    sys.exit(1)

checked = sum(1 for text in docs.values() for _ in re.findall(r"scripts/[A-Za-z0-9._-]+\.sh", text))
print("AGENTS.md validation passed ({} script references verified across {} docs)".format(checked, len(docs)))
PY
