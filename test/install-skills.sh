#!/usr/bin/env bash
# Isolated contract test for scripts/install-skills.sh.
set -euo pipefail

REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="$REPOSITORY_ROOT/scripts/install-skills.sh"
TEMP_ROOT=$(mktemp -d /private/tmp/skills-sdlc-install-skills.XXXXXX)
trap 'rm -rf "$TEMP_ROOT"' EXIT

fail() {
  echo "test-install-skills: $*" >&2
  exit 1
}

write_skill() {
  local path="$1" name="$2"
  mkdir -p "$path"
  printf '%s\n' '---' "name: $name" '---' >"$path/SKILL.md"
}

expect_failure() {
  local output="$1"
  shift
  if "$@" >"$output" 2>&1; then
    fail "expected command to fail: $*"
  fi
}

HOME="$TEMP_ROOT/home"
LOCAL="$TEMP_ROOT/local"
SCAN="$TEMP_ROOT/scan"
UPSTREAM="$SCAN/vendor-source/skills"
INSTALL="$HOME/.agent/skills"
mkdir -p "$HOME/.claude" "$SCAN"
ln -s "$LOCAL" "$HOME/.claude/skills"
write_skill "$LOCAL/custom" custom
write_skill "$UPSTREAM/engineering/tdd" tdd
printf '%s\n' 'Use /custom and /tdd. /plan is built in.' >"$SCAN/README.md"

HOME="$HOME" "$INSTALLER" --local-skills-dir "$LOCAL" --upstream-skills-dir "$UPSTREAM" --install-dir "$INSTALL" --scan-dir "$SCAN"
[ "$INSTALL/custom" -ef "$LOCAL/custom" ] || fail 'local skill did not link'
[ "$INSTALL/tdd" -ef "$UPSTREAM/engineering/tdd" ] || fail 'categorized upstream skill did not link'
[ ! -e "$INSTALL/plan" ] || fail 'built-in command was installed'
[ ! -e "$INSTALL/skills" ] && [ ! -L "$INSTALL/skills" ] || fail 'nested skills link created'
[ "$HOME/.claude/skills" -ef "$LOCAL" ] || fail 'destination-root symlink changed'
[ "$HOME/.claude/skills/tdd" -ef "$UPSTREAM/engineering/tdd" ] || fail 'Claude upstream link missing'

# The injected source is beneath SCAN, but its own references are not consumer dependencies.
printf '%s\n' 'Use /code-review.' >"$UPSTREAM/README.md"
HOME="$HOME" "$INSTALLER" --local-skills-dir "$LOCAL" --upstream-skills-dir "$UPSTREAM" --install-dir "$INSTALL" --scan-dir "$SCAN"
[ ! -e "$INSTALL/code-review" ] || fail 'vendored reference was scanned'

# The test seam also accepts the historical flat source layout.
rm -rf "$LOCAL/tdd" "$UPSTREAM/engineering/tdd"
write_skill "$UPSTREAM/tdd" tdd
FLAT_INSTALL="$TEMP_ROOT/flat-home/.agent/skills"
HOME="$TEMP_ROOT/flat-home" "$INSTALLER" --local-skills-dir "$LOCAL" --upstream-skills-dir "$UPSTREAM" --install-dir "$FLAT_INSTALL" --scan-dir "$SCAN"
[ "$FLAT_INSTALL/tdd" -ef "$UPSTREAM/tdd" ] || fail 'flat override did not resolve'

write_skill "$UPSTREAM/engineering/tdd" tdd
DUPLICATE_INSTALL="$TEMP_ROOT/duplicate-home/.agent/skills"
expect_failure "$TEMP_ROOT/duplicate.out" env HOME="$TEMP_ROOT/duplicate-home" "$INSTALLER" --local-skills-dir "$LOCAL" --upstream-skills-dir "$UPSTREAM" --install-dir "$DUPLICATE_INSTALL" --scan-dir "$SCAN"
rg -Fq 'Ambiguous Matt Pocock skills: tdd' "$TEMP_ROOT/duplicate.out" || fail 'ambiguous dependency not reported'
[ ! -e "$DUPLICATE_INSTALL" ] || fail 'ambiguous dependency mutated destination'
rm -rf "$UPSTREAM/engineering/tdd"

# An omitted default submodule is actionable and cannot create destinations.
CHECKOUT="$TEMP_ROOT/checkout"
mkdir -p "$CHECKOUT/scripts" "$CHECKOUT/.agents/skills/custom" "$CHECKOUT/scan"
cp "$INSTALLER" "$CHECKOUT/scripts/install-skills.sh"
printf '%s\n' '---' 'name: custom' '---' >"$CHECKOUT/.agents/skills/custom/SKILL.md"
printf '%s\n' 'Use /custom and /tdd.' >"$CHECKOUT/scan/README.md"
UNINITIALIZED_INSTALL="$TEMP_ROOT/uninitialized-home/.agent/skills"
expect_failure "$TEMP_ROOT/uninitialized.out" env HOME="$TEMP_ROOT/uninitialized-home" "$CHECKOUT/scripts/install-skills.sh" --install-dir "$UNINITIALIZED_INSTALL" --scan-dir "$CHECKOUT/scan"
rg -Fq 'git submodule update --init --recursive' "$TEMP_ROOT/uninitialized.out" || fail 'uninitialized source recovery missing'
[ ! -e "$UNINITIALIZED_INSTALL" ] || fail 'uninitialized source mutated destination'

INVALID_INSTALL="$TEMP_ROOT/invalid-home/.agent/skills"
expect_failure "$TEMP_ROOT/invalid.out" env HOME="$TEMP_ROOT/invalid-home" "$INSTALLER" --local-skills-dir "$LOCAL" --upstream-skills-dir "$TEMP_ROOT/no-upstream" --install-dir "$INVALID_INSTALL" --scan-dir "$SCAN"
rg -Fq 'upstream skill directory does not exist' "$TEMP_ROOT/invalid.out" || fail 'invalid override error missing'
[ ! -e "$INVALID_INSTALL" ] || fail 'invalid override mutated destination'

# All dependencies must resolve before either normal or forced conflict handling mutates a destination.
printf '%s\n' 'Use /code-review.' >"$SCAN/missing.md"
PRECHECK_INSTALL="$TEMP_ROOT/precheck-home/.agent/skills"
expect_failure "$TEMP_ROOT/precheck.out" env HOME="$TEMP_ROOT/precheck-home" "$INSTALLER" --local-skills-dir "$LOCAL" --upstream-skills-dir "$UPSTREAM" --install-dir "$PRECHECK_INSTALL" --scan-dir "$SCAN"
rg -Fq 'code-review' "$TEMP_ROOT/precheck.out" || fail 'missing dependency not reported'
[ ! -e "$PRECHECK_INSTALL" ] || fail 'missing dependency mutated destination'
mkdir -p "$PRECHECK_INSTALL"
printf conflict >"$PRECHECK_INSTALL/custom"
expect_failure "$TEMP_ROOT/precheck-force.out" env HOME="$TEMP_ROOT/precheck-home" "$INSTALLER" --force --local-skills-dir "$LOCAL" --upstream-skills-dir "$UPSTREAM" --install-dir "$PRECHECK_INSTALL" --scan-dir "$SCAN"
[ -f "$PRECHECK_INSTALL/custom" ] || fail 'force replaced conflict before preflight'
[ ! -e "$PRECHECK_INSTALL/tdd" ] || fail 'force linked before preflight'

HELP_OUTPUT=$("$INSTALLER" --help)
case "$HELP_OUTPUT" in
  *'npx skills'*|*'package-manager'*|*'install missing dependencies'*) fail 'help advertises runtime acquisition' ;;
esac

echo 'install-skills contract passed'
