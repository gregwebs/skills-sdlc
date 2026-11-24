#!/usr/bin/env bash
# Isolated contract test for scripts/install-agents.sh: agent rendering per
# platform, platform selection, and filesystem behavior.
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
  [ -f "$1" ] || fail "expected file: $1"
  [ "$(<"$1")" = "$2" ] || fail "unexpected content in $1"
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

# --- fixtures -------------------------------------------------------------

AGENT_DIR="$TEMP_ROOT/agents"
mkdir -p "$AGENT_DIR"
printf 'ignored\n' >"$AGENT_DIR/notes.txt"
printf 'ignored\n' >"$AGENT_DIR/gamma.cue"

cat >"$AGENT_DIR/alpha.json" <<'EOF'
{
    "name": "alpha",
    "description": "Alpha agent: does alpha things.",
    "claude": {
        "model": "opus",
        "tools": ["Read", "Grep"],
        "fallbackModels": ["a-model", "b-model"]
    },
    "codex": {
        "model": "gpt-x",
        "model_reasoning_effort": "high"
    },
    "antigravity": {
        "model": "pro",
        "tools": ["view_file", "run_command"],
        "subagent": true,
        "mainAgent": false
    }
}
EOF
cat >"$AGENT_DIR/alpha.md" <<'EOF'
Alpha body line one.
Line two has a "quote" and C:\tmp.
EOF

# beta exercises a definition with no codex block at all.
cat >"$AGENT_DIR/beta.json" <<'EOF'
{
    "name": "beta",
    "description": "Beta agent.",
    "claude": {"model": "sonnet"}
}
EOF
printf 'Beta body.\n' >"$AGENT_DIR/beta.md"

EXPECTED_CLAUDE_ALPHA="---"$'\n'"name: alpha"$'\n'
EXPECTED_CLAUDE_ALPHA+='description: "Alpha agent: does alpha things."'$'\n'
EXPECTED_CLAUDE_ALPHA+='tools: Read, Grep'$'\n'
EXPECTED_CLAUDE_ALPHA+='model: "opus"'$'\n'
EXPECTED_CLAUDE_ALPHA+='fallbackModels: ["a-model", "b-model"]'$'\n'
EXPECTED_CLAUDE_ALPHA+="---"$'\n'$'\n'
EXPECTED_CLAUDE_ALPHA+='Alpha body line one.'$'\n'
EXPECTED_CLAUDE_ALPHA+='Line two has a "quote" and C:\tmp.'

EXPECTED_CODEX_ALPHA='name = "alpha"'$'\n'
EXPECTED_CODEX_ALPHA+='description = "Alpha agent: does alpha things."'$'\n'
EXPECTED_CODEX_ALPHA+='model = "gpt-x"'$'\n'
EXPECTED_CODEX_ALPHA+='model_reasoning_effort = "high"'$'\n'
EXPECTED_CODEX_ALPHA+='developer_instructions = """'$'\n'
EXPECTED_CODEX_ALPHA+='Alpha body line one.'$'\n'
EXPECTED_CODEX_ALPHA+='Line two has a \"quote\" and C:\\tmp.'$'\n'
EXPECTED_CODEX_ALPHA+='"""'

EXPECTED_CODEX_BETA='name = "beta"'$'\n'
EXPECTED_CODEX_BETA+='description = "Beta agent."'$'\n'
EXPECTED_CODEX_BETA+='developer_instructions = """'$'\n'
EXPECTED_CODEX_BETA+='Beta body.'$'\n'
EXPECTED_CODEX_BETA+='"""'

EXPECTED_ANTIGRAVITY_ALPHA="---"$'\n'"name: alpha"$'\n'
EXPECTED_ANTIGRAVITY_ALPHA+='description: "Alpha agent: does alpha things."'$'\n'
EXPECTED_ANTIGRAVITY_ALPHA+='subagent: true'$'\n'
EXPECTED_ANTIGRAVITY_ALPHA+='mainAgent: false'$'\n'
EXPECTED_ANTIGRAVITY_ALPHA+='model: "pro"'$'\n'
EXPECTED_ANTIGRAVITY_ALPHA+='tools:'$'\n'
EXPECTED_ANTIGRAVITY_ALPHA+='  - "view_file"'$'\n'
EXPECTED_ANTIGRAVITY_ALPHA+='  - "run_command"'$'\n'
EXPECTED_ANTIGRAVITY_ALPHA+="---"$'\n'$'\n'
EXPECTED_ANTIGRAVITY_ALPHA+='Alpha body line one.'$'\n'
EXPECTED_ANTIGRAVITY_ALPHA+='Line two has a "quote" and C:\tmp.'

# --- help -----------------------------------------------------------------

"$INSTALLER" --help >"$TEMP_ROOT/help"
for option in --platform --agent-dir --claude-install-dir --codex-install-dir \
  --antigravity-install-dir --dry-run --force -h --help; do
  assert_output "$TEMP_ROOT/help" "$option"
done
for platform in claude codex antigravity; do
  assert_output "$TEMP_ROOT/help" "$platform"
done

# --- rendering per platform ----------------------------------------------

HOME="$TEMP_ROOT/all home"
mkdir -p "$HOME"
HOME="$HOME" "$INSTALLER" --agent-dir "$AGENT_DIR" --platform all
assert_file_content "$HOME/.claude/agents/alpha.md" "$EXPECTED_CLAUDE_ALPHA"
assert_file_content "$HOME/.claude/agents/beta.md" $'---\nname: beta\ndescription: "Beta agent."\nmodel: "sonnet"\n---\n\nBeta body.'
assert_file_content "$HOME/.codex/agents/alpha.toml" "$EXPECTED_CODEX_ALPHA"
assert_file_content "$HOME/.codex/agents/beta.toml" "$EXPECTED_CODEX_BETA"
assert_file_content "$HOME/.gemini/config/agents/alpha.md" "$EXPECTED_ANTIGRAVITY_ALPHA"
assert_file_content "$HOME/.gemini/config/agents/beta.md" \
  $'---\nname: beta\ndescription: "Beta agent."\nsubagent: true\nmainAgent: false\n---\n\nBeta body.'
assert_absent "$HOME/.claude/agents/notes.txt"
assert_absent "$HOME/.claude/agents/gamma.cue"

# --- platform selection --------------------------------------------------

HOME="$TEMP_ROOT/select home"
mkdir -p "$HOME/.claude" "$HOME/.codex" "$HOME/.gemini"
HOME="$HOME" "$INSTALLER" --agent-dir "$AGENT_DIR" --platform claude,antigravity
assert_absent "$HOME/.codex/agents"
[ -f "$HOME/.claude/agents/alpha.md" ] || fail 'expected claude install'
[ -f "$HOME/.gemini/config/agents/alpha.md" ] || fail 'expected antigravity install'

HOME="$TEMP_ROOT/repeat home"
mkdir -p "$HOME"
HOME="$HOME" "$INSTALLER" --agent-dir "$AGENT_DIR" --platform codex --platform claude
[ -f "$HOME/.codex/agents/alpha.toml" ] || fail 'expected repeated --platform to accumulate'
[ -f "$HOME/.claude/agents/alpha.md" ] || fail 'expected repeated --platform to accumulate'
assert_absent "$HOME/.gemini"

# --- default detection ---------------------------------------------------

HOME="$TEMP_ROOT/detect home"
mkdir -p "$HOME/.codex"
HOME="$HOME" "$INSTALLER" --agent-dir "$AGENT_DIR" >"$TEMP_ROOT/detect-output" 2>&1
[ -f "$HOME/.codex/agents/alpha.toml" ] || fail 'expected codex to be detected'
assert_absent "$HOME/.claude"
assert_absent "$HOME/.gemini"
assert_output "$TEMP_ROOT/detect-output" 'Skipping claude'
assert_output "$TEMP_ROOT/detect-output" 'Skipping antigravity'

HOME="$TEMP_ROOT/nothing home"
mkdir -p "$HOME"
assert_failure env HOME="$HOME" "$INSTALLER" --agent-dir "$AGENT_DIR"
assert_output "$TEMP_ROOT/output" 'pass --platform'
assert_absent "$HOME/.claude"

# --- idempotence, user edits, --force ------------------------------------

HOME="$TEMP_ROOT/idem home"
mkdir -p "$HOME"
HOME="$HOME" "$INSTALLER" --agent-dir "$AGENT_DIR" --platform claude
HOME="$HOME" "$INSTALLER" --agent-dir "$AGENT_DIR" --platform claude
if compgen -G "$HOME/.claude/agents/alpha.md.backup.*" >/dev/null; then
  fail 'unchanged reinstall created a backup'
fi
assert_file_content "$HOME/.claude/agents/alpha.md" "$EXPECTED_CLAUDE_ALPHA"

printf 'hand edited\n' >"$HOME/.claude/agents/alpha.md"
assert_failure env HOME="$HOME" "$INSTALLER" --agent-dir "$AGENT_DIR" --platform claude
assert_output "$TEMP_ROOT/output" 'refusing to replace differing agent file'
assert_file_content "$HOME/.claude/agents/alpha.md" 'hand edited'
[ -f "$HOME/.claude/agents/beta.md" ] || fail 'preflight failure left beta uninstalled'

HOME="$HOME" "$INSTALLER" --agent-dir "$AGENT_DIR" --platform claude --force
assert_file_content "$HOME/.claude/agents/alpha.md" "$EXPECTED_CLAUDE_ALPHA"
mapfile -t backups < <(compgen -G "$HOME/.claude/agents/alpha.md.backup.*")
[ "${#backups[@]}" -eq 1 ] || fail 'expected one backup of the edited file'
assert_file_content "${backups[0]}" 'hand edited'

# --- dry run -------------------------------------------------------------

DRY_HOME="$TEMP_ROOT/dry home"
mkdir -p "$DRY_HOME"
HOME="$DRY_HOME" "$INSTALLER" --agent-dir "$AGENT_DIR" --platform codex --dry-run \
  >"$TEMP_ROOT/dry-output"
assert_output "$TEMP_ROOT/dry-output" 'mkdir -p'
assert_output "$TEMP_ROOT/dry-output" 'cp '
assert_output "$TEMP_ROOT/dry-output" 'Dry run complete'
assert_absent "$DRY_HOME/.codex/agents"

# --- source validation ---------------------------------------------------

assert_failure "$INSTALLER" --platform emacs
assert_output "$TEMP_ROOT/output" 'unknown platform: emacs'

EMPTY_DIR="$TEMP_ROOT/empty agents"
mkdir -p "$EMPTY_DIR"
assert_failure env HOME="$TEMP_ROOT/all home" "$INSTALLER" --agent-dir "$EMPTY_DIR" --platform claude
assert_output "$TEMP_ROOT/output" 'no agent definitions found'

NO_BODY_DIR="$TEMP_ROOT/no body agents"
mkdir -p "$NO_BODY_DIR"
cp "$AGENT_DIR/alpha.json" "$NO_BODY_DIR/"
assert_failure env HOME="$TEMP_ROOT/all home" "$INSTALLER" --agent-dir "$NO_BODY_DIR" --platform claude
assert_output "$TEMP_ROOT/output" 'missing system prompt'

MISNAMED_DIR="$TEMP_ROOT/misnamed agents"
mkdir -p "$MISNAMED_DIR"
cp "$AGENT_DIR/alpha.md" "$MISNAMED_DIR/other.md"
cp "$AGENT_DIR/alpha.json" "$MISNAMED_DIR/other.json"
assert_failure env HOME="$TEMP_ROOT/all home" "$INSTALLER" --agent-dir "$MISNAMED_DIR" --platform claude
assert_output "$TEMP_ROOT/output" 'declares name "alpha"'

NO_DESCRIPTION_DIR="$TEMP_ROOT/no description agents"
mkdir -p "$NO_DESCRIPTION_DIR"
printf '{"name": "alpha"}\n' >"$NO_DESCRIPTION_DIR/alpha.json"
printf 'body\n' >"$NO_DESCRIPTION_DIR/alpha.md"
assert_failure env HOME="$TEMP_ROOT/all home" "$INSTALLER" --agent-dir "$NO_DESCRIPTION_DIR" --platform claude
assert_output "$TEMP_ROOT/output" 'has no description'

HOME="$TEMP_ROOT/all home" "$INSTALLER" --agent-dir "$AGENT_DIR" --platform claude \
  --claude-install-dir "$TEMP_ROOT/custom install" >/dev/null
[ -f "$TEMP_ROOT/custom install/alpha.md" ] || fail 'expected --claude-install-dir to be honored'

assert_failure "$INSTALLER" --unknown
assert_output "$TEMP_ROOT/output" 'install-agents: unknown option: --unknown'
assert_failure "$INSTALLER" --platform
assert_output "$TEMP_ROOT/output" 'install-agents: --platform requires a platform name'
for option in --agent-dir --claude-install-dir --codex-install-dir --antigravity-install-dir; do
  assert_failure "$INSTALLER" "$option"
  assert_output "$TEMP_ROOT/output" "install-agents: $option requires a directory"
done

echo 'install-agents contract test passed'
