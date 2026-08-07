#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK_PATH="$REPO_ROOT/.git/hooks/pre-commit"

cat > "$HOOK_PATH" <<'HOOK'
#!/usr/bin/env bash
set -euo pipefail

swiftformat --lint .

if command -v swiftlint &>/dev/null; then
  swiftlint lint --strict --quiet
fi
HOOK

chmod +x "$HOOK_PATH"

printf "Pre-commit hook installed at .git/hooks/pre-commit\n"
