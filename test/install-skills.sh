#!/usr/bin/env bash
# Isolated contract test for scripts/install-skills.sh.
set -euo pipefail

REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="$REPOSITORY_ROOT/scripts/install-skills.sh"
TEMP_ROOT=$(mktemp -d /private/tmp/claude-conf-install-skills.XXXXXX)
trap 'rm -rf "$TEMP_ROOT"' EXIT

HOME="$TEMP_ROOT/home"
LOCAL="$TEMP_ROOT/local"
UPSTREAM="$TEMP_ROOT/upstream"
SCAN="$TEMP_ROOT/scan"
INSTALL="$HOME/.agent/skills"
mkdir -p "$HOME/.claude" "$LOCAL/custom" "$UPSTREAM/tdd" "$SCAN"
ln -s "$LOCAL" "$HOME/.claude/skills"
printf '%s\\n' '---' 'name: custom' '---' >"$LOCAL/custom/SKILL.md"
printf '%s\\n' '---' 'name: tdd' '---' >"$UPSTREAM/tdd/SKILL.md"
printf '%s\\n' 'Use /custom and /tdd. /plan is built in.' >"$SCAN/README.md"

HOME="$HOME" "$INSTALLER" --local-skills-dir "$LOCAL" --upstream-skills-dir "$UPSTREAM" --install-dir "$INSTALL" --scan-dir "$SCAN"

[ "$INSTALL/custom" -ef "$LOCAL/custom" ]
[ "$INSTALL/tdd" -ef "$UPSTREAM/tdd" ]
[ ! -e "$INSTALL/skills" ] && [ ! -L "$INSTALL/skills" ]
[ "$HOME/.claude/skills" -ef "$LOCAL" ]
[ "$HOME/.claude/skills/tdd" -ef "$UPSTREAM/tdd" ]

printf '%s\\n' 'Use /code-review.' >"$SCAN/missing.md"
if HOME="$HOME" "$INSTALLER" --local-skills-dir "$LOCAL" --upstream-skills-dir "$UPSTREAM" --install-dir "$INSTALL" --scan-dir "$SCAN" >"$TEMP_ROOT/output" 2>&1; then
  echo 'expected missing dependency audit to fail without --force' >&2
  exit 1
fi
rg -Fq 'rerun with --force' "$TEMP_ROOT/output"
