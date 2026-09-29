#!/usr/bin/env bash
# ShellCheck all tracked shell scripts. Discovers them by shebang (so extensionless
# hooks like .githooks/pre-commit are covered, not just *.sh) and skips symlinks
# (scripts/download.sh -> ../scraper/download.sh) to avoid checking the same file twice.
#
# Called by both CI (.github/workflows/ci.yml) and `just shellcheck`.
set -euo pipefail
cd "$(dirname "$0")/.."

mapfile -t files < <(git ls-files | while read -r f; do
  [ -f "$f" ] && [ ! -L "$f" ] \
    && head -1 "$f" | grep -qE '^#!.*(bash|/sh| sh)' && printf '%s\n' "$f"
done)
shellcheck --severity=warning "${files[@]}"
