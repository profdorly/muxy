#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT"

python3 <<'PY'
import re
import sys
from pathlib import Path

root = Path(".")
manifest = (root / "Package.swift").read_text()

packages = re.findall(r'\.package\(url:\s*"[^"]*/([^"/]+?)(?:\.git)?",', manifest)
products = re.findall(r'\.product\(name:\s*"([^"]+)"\s*,\s*package:\s*"([^"]+)"', manifest)

source_dirs = [
    "Muxy",
    "MuxyServer",
    "MuxyShared",
    "MuxySession",
    "MuxyHookKit",
    "MuxyExtensionHost",
    "MuxySessionProtocol",
    "MuxyHookBridge",
    "Tests",
]

imports = set()
import_pattern = re.compile(r"^\s*(?:@testable\s+)?import\s+([A-Za-z_][A-Za-z0-9_]*)", re.MULTILINE)
for directory in source_dirs:
    for swift_file in root.glob("{}/**/*.swift".format(directory)):
        imports.update(import_pattern.findall(swift_file.read_text()))

failures = []
for package in packages:
    package_products = [name for name, pkg in products if pkg.lower() == package.lower()]
    if not package_products:
        failures.append("package '{}' is declared but no product references it".format(package))
        continue
    used = [name for name in package_products if name in imports]
    if not used:
        failures.append("package '{}' products {} are never imported".format(package, package_products))

for name, pkg in products:
    if name not in imports:
        failures.append("product '{}' (package '{}') is declared but never imported".format(name, pkg))

if failures:
    print("Unused Swift package dependencies detected:")
    for failure in failures:
        print("  - {}".format(failure))
    print("")
    print("Remove the unused dependency from Package.swift or import the module where it is needed.")
    sys.exit(1)

print("All {} package dependencies are imported ({} products checked)".format(len(packages), len(products)))
PY
