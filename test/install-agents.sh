#!/usr/bin/env bash
# Isolated contract test for scripts/install-agents.sh.
set -euo pipefail

REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="$REPOSITORY_ROOT/scripts/install-agents.sh"
TEMP_ROOT=$(mktemp -d /private/tmp/skills-sdlc-install-agents.XXXXXX)
trap 'rm -rf "$TEMP_ROOT"' EXIT

fail() {
  echo "install-agents test: $*" >&2
  exit 1
}

assert_file_content() {
  [ "$(<"$1")" = "$2" ] || fail "unexpected content in $1"
}

assert_link_to() {
  [ "$1" -ef "$2" ] || fail "expected $1 to link to $2"
}

assert_absent() {
  [ ! -e "$1" ] && [ ! -L "$1" ] || fail "expected $1 to be absent"
}

assert_output() {
  rg -Fq -- "$2" "$1" || fail "expected output to contain: $2"
}

assert_failure() {
  if "$@" >"$TEMP_ROOT/output" 2>&1; then
    fail "expected command to fail: $*"
  fi
}

HOME="$TEMP_ROOT/home"
CLAUDE_SOURCE="$TEMP_ROOT/claude source"
CODEX_SOURCE="$TEMP_ROOT/codex source"
PI_SOURCE="$TEMP_ROOT/pi source"
CLAUDE_INSTALL="$HOME/.claude/agents"
CODEX_INSTALL="$HOME/.codex/agents"
mkdir -p "$HOME" "$CLAUDE_SOURCE/nested" "$CODEX_SOURCE/nested" "$PI_SOURCE/nested"
printf 'claude one\n' >"$CLAUDE_SOURCE/one.md"
printf 'claude two\n' >"$CLAUDE_SOURCE/two.md"
printf 'ignored\n' >"$CLAUDE_SOURCE/wrong.toml"
printf 'nested\n' >"$CLAUDE_SOURCE/nested/hidden.md"
printf 'codex one\n' >"$CODEX_SOURCE/one.toml"
printf 'codex two\n' >"$CODEX_SOURCE/two.toml"
printf 'ignored\n' >"$CODEX_SOURCE/wrong.md"
printf 'nested\n' >"$CODEX_SOURCE/nested/hidden.toml"
printf 'pi one\n' >"$PI_SOURCE/one.md"
printf 'pi two\n' >"$PI_SOURCE/two.toml"
printf 'ignored\n' >"$PI_SOURCE/wrong.txt"
printf 'nested\n' >"$PI_SOURCE/nested/hidden.md"

"$INSTALLER" --help >"$TEMP_ROOT/help"
for option in --dry-run --force --claude-source-dir --codex-source-dir --pi-source-dir \
  --claude-install-dir --codex-install-dir --pi-install-dir -h --help; do
  assert_output "$TEMP_ROOT/help" "$option"
done
assert_absent "$CLAUDE_INSTALL"
assert_absent "$CODEX_INSTALL"

HOME="$HOME" "$INSTALLER" \
  --claude-source-dir "$CLAUDE_SOURCE" --codex-source-dir "$CODEX_SOURCE" \
  --claude-install-dir "$CLAUDE_INSTALL" --codex-install-dir "$CODEX_INSTALL"
assert_link_to "$CLAUDE_INSTALL/one.md" "$CLAUDE_SOURCE/one.md"
assert_link_to "$CLAUDE_INSTALL/two.md" "$CLAUDE_SOURCE/two.md"
assert_link_to "$CODEX_INSTALL/one.toml" "$CODEX_SOURCE/one.toml"
assert_link_to "$CODEX_INSTALL/two.toml" "$CODEX_SOURCE/two.toml"
assert_absent "$CLAUDE_INSTALL/wrong.toml"
assert_absent "$CLAUDE_INSTALL/hidden.md"
assert_absent "$CODEX_INSTALL/wrong.md"
assert_absent "$CODEX_INSTALL/hidden.toml"

before=$(readlink "$CLAUDE_INSTALL/one.md")
HOME="$HOME" "$INSTALLER" \
  --claude-source-dir "$CLAUDE_SOURCE" --codex-source-dir "$CODEX_SOURCE" \
  --claude-install-dir "$CLAUDE_INSTALL" --codex-install-dir "$CODEX_INSTALL"
[ "$(readlink "$CLAUDE_INSTALL/one.md")" = "$before" ] || fail 'idempotent link changed'
if compgen -G "$CLAUDE_INSTALL/one.md.backup.*" >/dev/null; then
  fail 'idempotent install created a backup'
fi

GATE_HOME="$TEMP_ROOT/gate home"
mkdir -p "$GATE_HOME"
HOME="$GATE_HOME" "$INSTALLER" \
  --claude-source-dir "$CLAUDE_SOURCE" --codex-source-dir "$CODEX_SOURCE" --pi-source-dir "$PI_SOURCE" \
  --claude-install-dir "$GATE_HOME/.claude/agents" --codex-install-dir "$GATE_HOME/.codex/agents" \
  >"$TEMP_ROOT/gate-off-output" 2>&1
assert_absent "$GATE_HOME/.pi"
assert_output "$TEMP_ROOT/gate-off-output" 'Skipping Pi agents'

mkdir -p "$GATE_HOME/.pi"
HOME="$GATE_HOME" "$INSTALLER" \
  --claude-source-dir "$CLAUDE_SOURCE" --codex-source-dir "$CODEX_SOURCE" --pi-source-dir "$PI_SOURCE" \
  --claude-install-dir "$GATE_HOME/.claude/agents" --codex-install-dir "$GATE_HOME/.codex/agents"
assert_link_to "$GATE_HOME/.pi/agent/agents/one.md" "$PI_SOURCE/one.md"
assert_link_to "$GATE_HOME/.pi/agent/agents/two.toml" "$PI_SOURCE/two.toml"
assert_absent "$GATE_HOME/.pi/agent/agents/wrong.txt"
assert_absent "$GATE_HOME/.pi/agent/agents/hidden.md"

OVERRIDE_HOME="$TEMP_ROOT/override home"
OVERRIDE_PI="$TEMP_ROOT/override pi"
mkdir -p "$OVERRIDE_HOME"
HOME="$OVERRIDE_HOME" "$INSTALLER" \
  --claude-source-dir "$CLAUDE_SOURCE" --codex-source-dir "$CODEX_SOURCE" --pi-source-dir "$PI_SOURCE" \
  --claude-install-dir "$OVERRIDE_HOME/.claude/agents" --codex-install-dir "$OVERRIDE_HOME/.codex/agents" \
  --pi-install-dir "$OVERRIDE_PI"
assert_absent "$OVERRIDE_HOME/.pi"
assert_link_to "$OVERRIDE_PI/one.md" "$PI_SOURCE/one.md"

SYMLINK_ROOT="$TEMP_ROOT/linked claude agents"
SYMLINK_TARGET="$TEMP_ROOT/linked target"
mkdir -p "$SYMLINK_TARGET"
ln -s "$SYMLINK_TARGET" "$SYMLINK_ROOT"
SYMLINK_CODEX="$TEMP_ROOT/linked codex agents"
HOME="$HOME" "$INSTALLER" \
  --claude-source-dir "$CLAUDE_SOURCE" --codex-source-dir "$CODEX_SOURCE" \
  --claude-install-dir "$SYMLINK_ROOT" --codex-install-dir "$SYMLINK_CODEX"
[ -L "$SYMLINK_ROOT" ] || fail 'destination root symlink was not preserved'
assert_link_to "$SYMLINK_ROOT/one.md" "$CLAUDE_SOURCE/one.md"
assert_link_to "$SYMLINK_CODEX/one.toml" "$CODEX_SOURCE/one.toml"

PREFLIGHT_CLAUDE="$TEMP_ROOT/preflight claude"
PREFLIGHT_CODEX="$TEMP_ROOT/preflight codex"
mkdir -p "$PREFLIGHT_CLAUDE"
printf 'keep me\n' >"$PREFLIGHT_CLAUDE/one.md"
assert_failure env HOME="$HOME" "$INSTALLER" \
  --claude-source-dir "$CLAUDE_SOURCE" --codex-source-dir "$CODEX_SOURCE" \
  --claude-install-dir "$PREFLIGHT_CLAUDE" --codex-install-dir "$PREFLIGHT_CODEX"
assert_output "$TEMP_ROOT/output" 'install-agents: refusing to replace existing agent link'
assert_file_content "$PREFLIGHT_CLAUDE/one.md" 'keep me'
assert_absent "$PREFLIGHT_CODEX"

FORCE_CLAUDE="$TEMP_ROOT/force claude"
FORCE_CODEX="$TEMP_ROOT/force codex"
FORCE_PI="$TEMP_ROOT/force pi"
mkdir -p "$FORCE_CLAUDE" "$FORCE_CODEX" "$FORCE_PI"
printf 'first original\n' >"$FORCE_CLAUDE/one.md"
OTHER_TARGET="$TEMP_ROOT/other.toml"
printf 'other\n' >"$OTHER_TARGET"
ln -s "$OTHER_TARGET" "$FORCE_CODEX/one.toml"
printf 'pi first original\n' >"$FORCE_PI/one.md"
HOME="$HOME" "$INSTALLER" --force \
  --claude-source-dir "$CLAUDE_SOURCE" --codex-source-dir "$CODEX_SOURCE" --pi-source-dir "$PI_SOURCE" \
  --claude-install-dir "$FORCE_CLAUDE" --codex-install-dir "$FORCE_CODEX" --pi-install-dir "$FORCE_PI"
assert_link_to "$FORCE_CLAUDE/one.md" "$CLAUDE_SOURCE/one.md"
assert_link_to "$FORCE_CODEX/one.toml" "$CODEX_SOURCE/one.toml"
assert_link_to "$FORCE_PI/one.md" "$PI_SOURCE/one.md"
mapfile -t claude_backups < <(compgen -G "$FORCE_CLAUDE/one.md.backup.*")
mapfile -t codex_backups < <(compgen -G "$FORCE_CODEX/one.toml.backup.*")
mapfile -t pi_backups < <(compgen -G "$FORCE_PI/one.md.backup.*")
[ "${#claude_backups[@]}" -eq 1 ] || fail 'expected Claude backup'
[ "${#codex_backups[@]}" -eq 1 ] || fail 'expected Codex backup'
[ "${#pi_backups[@]}" -eq 1 ] || fail 'expected Pi backup'
assert_file_content "${claude_backups[0]}" 'first original'
assert_link_to "${codex_backups[0]}" "$OTHER_TARGET"
assert_file_content "${pi_backups[0]}" 'pi first original'
mv "$FORCE_CLAUDE/one.md" "$TEMP_ROOT/displaced correct Claude link"
printf 'second original\n' >"$FORCE_CLAUDE/one.md"
HOME="$HOME" "$INSTALLER" --force \
  --claude-source-dir "$CLAUDE_SOURCE" --codex-source-dir "$CODEX_SOURCE" --pi-source-dir "$PI_SOURCE" \
  --claude-install-dir "$FORCE_CLAUDE" --codex-install-dir "$FORCE_CODEX" --pi-install-dir "$FORCE_PI"
mapfile -t claude_backups < <(compgen -G "$FORCE_CLAUDE/one.md.backup.*")
mapfile -t pi_backups < <(compgen -G "$FORCE_PI/one.md.backup.*")
[ "${#claude_backups[@]}" -eq 2 ] || fail 'expected distinct Claude backups'
[ "${#pi_backups[@]}" -eq 1 ] || fail 'idempotent Pi install created a backup'
for backup in "${claude_backups[@]}"; do
  [ "$(<"$backup")" = 'first original' ] || [ "$(<"$backup")" = 'second original' ] || fail 'backup content was lost'
done

DRY_CLAUDE="$TEMP_ROOT/dry claude"
DRY_CODEX="$TEMP_ROOT/dry codex"
DRY_PI="$TEMP_ROOT/dry pi"
HOME="$HOME" "$INSTALLER" --dry-run \
  --claude-source-dir "$CLAUDE_SOURCE" --codex-source-dir "$CODEX_SOURCE" --pi-source-dir "$PI_SOURCE" \
  --claude-install-dir "$DRY_CLAUDE" --codex-install-dir "$DRY_CODEX" --pi-install-dir "$DRY_PI" \
  >"$TEMP_ROOT/dry-output"
assert_output "$TEMP_ROOT/dry-output" 'mkdir -p'
assert_output "$TEMP_ROOT/dry-output" 'ln -s'
assert_absent "$DRY_CLAUDE"
assert_absent "$DRY_CODEX"
assert_absent "$DRY_PI"
mkdir -p "$DRY_CLAUDE" "$DRY_CODEX" "$DRY_PI"
printf 'dry conflict\n' >"$DRY_CLAUDE/one.md"
HOME="$HOME" "$INSTALLER" --dry-run --force \
  --claude-source-dir "$CLAUDE_SOURCE" --codex-source-dir "$CODEX_SOURCE" --pi-source-dir "$PI_SOURCE" \
  --claude-install-dir "$DRY_CLAUDE" --codex-install-dir "$DRY_CODEX" --pi-install-dir "$DRY_PI" \
  >"$TEMP_ROOT/dry-force-output"
assert_output "$TEMP_ROOT/dry-force-output" 'mv'
assert_output "$TEMP_ROOT/dry-force-output" 'ln -s'
assert_file_content "$DRY_CLAUDE/one.md" 'dry conflict'
if compgen -G "$DRY_CLAUDE/one.md.backup.*" >/dev/null; then
  fail 'dry-run force created a backup'
fi

MISSING="$TEMP_ROOT/missing"
assert_failure env HOME="$HOME" "$INSTALLER" --claude-source-dir "$MISSING" \
  --codex-source-dir "$CODEX_SOURCE" --claude-install-dir "$TEMP_ROOT/no mutation claude" \
  --codex-install-dir "$TEMP_ROOT/no mutation codex"
assert_output "$TEMP_ROOT/output" 'Claude source directory does not exist'
assert_absent "$TEMP_ROOT/no mutation claude"
assert_absent "$TEMP_ROOT/no mutation codex"
EMPTY_CLAUDE="$TEMP_ROOT/empty claude"
mkdir -p "$EMPTY_CLAUDE"
assert_failure env HOME="$HOME" "$INSTALLER" --claude-source-dir "$EMPTY_CLAUDE" \
  --codex-source-dir "$CODEX_SOURCE" --claude-install-dir "$TEMP_ROOT/empty result claude" \
  --codex-install-dir "$TEMP_ROOT/empty result codex"
assert_output "$TEMP_ROOT/output" 'no Claude .md agent files found'
assert_absent "$TEMP_ROOT/empty result claude"
assert_absent "$TEMP_ROOT/empty result codex"
EMPTY_PI="$TEMP_ROOT/empty pi"
mkdir -p "$EMPTY_PI"
assert_failure env HOME="$HOME" "$INSTALLER" --claude-source-dir "$CLAUDE_SOURCE" \
  --codex-source-dir "$CODEX_SOURCE" --pi-source-dir "$EMPTY_PI" \
  --claude-install-dir "$TEMP_ROOT/empty pi result claude" \
  --codex-install-dir "$TEMP_ROOT/empty pi result codex" \
  --pi-install-dir "$TEMP_ROOT/empty pi result pi"
assert_output "$TEMP_ROOT/output" 'no Pi .md, .toml agent files found'
assert_absent "$TEMP_ROOT/empty pi result claude"
assert_absent "$TEMP_ROOT/empty pi result codex"
assert_absent "$TEMP_ROOT/empty pi result pi"

assert_failure "$INSTALLER" --unknown
assert_output "$TEMP_ROOT/output" 'install-agents: unknown option: --unknown'
for option in --claude-source-dir --codex-source-dir --pi-source-dir \
  --claude-install-dir --codex-install-dir --pi-install-dir; do
  assert_failure "$INSTALLER" "$option"
  assert_output "$TEMP_ROOT/output" "install-agents: $option requires a directory"
done

echo 'install-agents contract test passed'
