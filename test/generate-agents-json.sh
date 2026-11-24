#!/usr/bin/env bash
# Contract test for scripts/generate-agents-json.sh: checked-in JSON matches
# the CUE source, drift is reported, and schema violations fail.
#
# Skipped when cue is unavailable; CI installs it so drift is covered there.
set -euo pipefail

REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GENERATOR="$REPOSITORY_ROOT/scripts/generate-agents-json.sh"
TEMP_ROOT=$(mktemp -d /private/tmp/skills-sdlc-generate-agents.XXXXXX)
trap 'rm -rf "$TEMP_ROOT"' EXIT

fail() {
  echo "generate-agents-json test: $*" >&2
  exit 1
}

assert_output() {
  rg -Fq -- "$2" "$1" || fail "expected output to contain: $2"
}

assert_failure() {
  if "$@" >"$TEMP_ROOT/output" 2>&1; then
    fail "expected command to fail: $*"
  fi
}

CUE_BIN="${CUE:-cue}"
if ! command -v "$CUE_BIN" >/dev/null 2>&1; then
  echo "generate-agents-json test: skipped (cue not installed)"
  exit 0
fi
export CUE="$CUE_BIN"

# The repository's checked-in JSON is current.
"$GENERATOR" --check >"$TEMP_ROOT/check-output" 2>&1 ||
  fail 'checked-in agent JSON is stale; run ./scripts/generate-agents-json.sh'
assert_output "$TEMP_ROOT/check-output" 'agent JSON is current'

# A hand edit to the JSON is reported as drift, not silently overwritten.
DRIFT_DIR="$TEMP_ROOT/drift agents"
mkdir -p "$DRIFT_DIR"
cp "$REPOSITORY_ROOT"/agents/*.cue "$DRIFT_DIR/"
cp "$REPOSITORY_ROOT"/agents/*.json "$DRIFT_DIR/"
printf 'edited\n' >>"$DRIFT_DIR/planner.json"
assert_failure "$GENERATOR" --check --agent-dir "$DRIFT_DIR"
assert_output "$TEMP_ROOT/output" 'stale:'
HOME="$TEMP_ROOT/home" "$GENERATOR" --agent-dir "$DRIFT_DIR" >/dev/null 2>&1
"$GENERATOR" --check --agent-dir "$DRIFT_DIR" >"$TEMP_ROOT/repaired-output" 2>&1 ||
  fail 'regenerating did not repair drift'

# A CUE change is rendered into the JSON.
printf 'package agents\n\nplanner: #Agent & {name: "planner", description: "Changed description."}\n' \
  >"$DRIFT_DIR/planner.cue"
"$GENERATOR" --agent-dir "$DRIFT_DIR" >/dev/null 2>&1
jq -e '.description == "Changed description."' "$DRIFT_DIR/planner.json" >/dev/null ||
  fail 'regenerated JSON did not pick up the CUE change'

# The schema rejects fields and tool names the platforms do not have.
BAD_FIELD_DIR="$TEMP_ROOT/bad field agents"
mkdir -p "$BAD_FIELD_DIR"
cp "$REPOSITORY_ROOT"/agents/schema.cue "$BAD_FIELD_DIR/"
printf 'package agents\n\nbroken: #Agent & {name: "broken", description: "d", codex: {temperature: 1}}\n' \
  >"$BAD_FIELD_DIR/broken.cue"
assert_failure "$GENERATOR" --agent-dir "$BAD_FIELD_DIR"
assert_output "$TEMP_ROOT/output" 'cue export failed for:'
jq -e '.codex.temperature' "$BAD_FIELD_DIR/broken.json" >/dev/null 2>&1 &&
  fail 'invalid agent produced JSON'

BAD_TOOL_DIR="$TEMP_ROOT/bad tool agents"
mkdir -p "$BAD_TOOL_DIR"
cp "$REPOSITORY_ROOT"/agents/schema.cue "$BAD_TOOL_DIR/"
printf 'package agents\n\nbroken: #Agent & {name: "broken", description: "d", antigravity: {tools: ["view_files"]}}\n' \
  >"$BAD_TOOL_DIR/broken.cue"
assert_failure "$GENERATOR" --agent-dir "$BAD_TOOL_DIR"
assert_output "$TEMP_ROOT/output" 'cue export failed for:'

# Antigravity accepts a tier alias or a concrete model id; a malformed model
# string is rejected.
MODEL_DIR="$TEMP_ROOT/model agents"
mkdir -p "$MODEL_DIR"
cp "$REPOSITORY_ROOT"/agents/schema.cue "$MODEL_DIR/"
printf 'package agents\n\npinned: #Agent & {name: "pinned", description: "d", antigravity: {model: "gemini-4-neon-high"}}\n' \
  >"$MODEL_DIR/pinned.cue"
"$GENERATOR" --agent-dir "$MODEL_DIR" >/dev/null 2>&1 ||
  fail 'concrete Antigravity model id was rejected'
jq -e '.antigravity.model == "gemini-4-neon-high"' "$MODEL_DIR/pinned.json" >/dev/null ||
  fail 'model id did not reach the JSON'

BAD_MODEL_DIR="$TEMP_ROOT/bad model agents"
mkdir -p "$BAD_MODEL_DIR"
cp "$REPOSITORY_ROOT"/agents/schema.cue "$BAD_MODEL_DIR/"
printf 'package agents\n\npinned: #Agent & {name: "pinned", description: "d", antigravity: {model: "gemini 4 neon"}}\n' \
  >"$BAD_MODEL_DIR/pinned.cue"
assert_failure "$GENERATOR" --agent-dir "$BAD_MODEL_DIR"
assert_output "$TEMP_ROOT/output" 'cue export failed for:'

# Usage errors.
"$GENERATOR" --help >"$TEMP_ROOT/help"
for option in --check --agent-dir -h --help; do
  assert_output "$TEMP_ROOT/help" "$option"
done
assert_failure "$GENERATOR" --unknown
assert_output "$TEMP_ROOT/output" 'generate-agents-json: unknown option: --unknown'
assert_failure "$GENERATOR" --agent-dir
assert_output "$TEMP_ROOT/output" 'generate-agents-json: --agent-dir requires a directory'
assert_failure "$GENERATOR" --agent-dir "$TEMP_ROOT/absent"
assert_output "$TEMP_ROOT/output" 'agent directory does not exist'
assert_failure env CUE="$TEMP_ROOT/absent cue" "$GENERATOR"
assert_output "$TEMP_ROOT/output" 'cue not found'

echo 'generate-agents-json contract test passed'
