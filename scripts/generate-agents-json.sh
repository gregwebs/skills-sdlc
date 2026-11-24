#!/usr/bin/env bash
# Regenerate agents/<name>.json from agents/<name>.cue.
#
# The JSON is checked in so installing agents never needs cue, and so an agent
# can be edited in its JSON instead of its CUE. --check reports drift instead of
# writing, for tests and CI.
set -euo pipefail

REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENT_DIR="$REPOSITORY_ROOT/agents"
CUE_BIN="${CUE:-cue}"
CHECK=false

usage() {
  cat <<'EOF'
Usage: ./scripts/generate-agents-json.sh [options]

Write agents/<name>.json from agents/<name>.cue for every agent.

Options:
  --check          Report stale JSON and exit non-zero instead of writing.
  --agent-dir DIR  Read and write agent definitions in DIR instead of agents/.
  -h, --help       Print this help text.
EOF
}

die() {
  echo "generate-agents-json: $*" >&2
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --check) CHECK=true ;;
    --agent-dir)
      [ "$#" -ge 2 ] || die '--agent-dir requires a directory'
      AGENT_DIR="$2"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *) die "unknown option: $1" ;;
  esac
  shift
done

[ -d "$AGENT_DIR" ] || die "agent directory does not exist: $AGENT_DIR"
AGENT_DIR="$(cd "$AGENT_DIR" && pwd -P)"
[ -f "$AGENT_DIR/schema.cue" ] || die "missing schema: $AGENT_DIR/schema.cue"

command -v "$CUE_BIN" >/dev/null 2>&1 || die "cue not found (set CUE or install cue: https://cuelang.org)"

stale=0
shopt -s nullglob
cue_files=("$AGENT_DIR"/*.cue)
shopt -u nullglob
[ "${#cue_files[@]}" -gt 0 ] || die "no .cue agent files found in: $AGENT_DIR"

for cue_file in "${cue_files[@]}"; do
  name="$(basename "$cue_file" .cue)"
  [ "$name" = schema ] && continue
  rendered="$("$CUE_BIN" export "$AGENT_DIR/schema.cue" "$cue_file" -e "$name" --out json)" ||
    die "cue export failed for: $cue_file"
  json_file="$AGENT_DIR/$name.json"
  rendered+=$'\n'
  if "$CHECK"; then
    if [ ! -f "$json_file" ] || ! cmp -s <(printf '%s' "$rendered") "$json_file"; then
      echo "stale: $json_file (run ./scripts/generate-agents-json.sh)" >&2
      stale=1
    fi
  else
    printf '%s' "$rendered" >"$json_file"
    echo "wrote $json_file" >&2
  fi
done

[ "$stale" -eq 0 ] || exit 1
if "$CHECK"; then
  echo "agent JSON is current" >&2
fi
