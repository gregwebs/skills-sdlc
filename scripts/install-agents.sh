#!/usr/bin/env bash
# Install this repository's agent definitions for the platforms you choose.
#
# Each agent is one directory entry in agents/: <name>.cue (source),
# <name>.json (generated, see scripts/generate-agents-json.sh) and <name>.md
# (system prompt). This script renders the JSON and body through a per-platform
# template and copies the result into that platform's agent directory.
set -euo pipefail

REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENT_DIR="$REPOSITORY_ROOT/agents"
RENDER_DIR="$REPOSITORY_ROOT/scripts/render"
CLAUDE_INSTALL_DIR="${HOME}/.claude/agents"
CODEX_INSTALL_DIR="${HOME}/.codex/agents"
ANTIGRAVITY_INSTALL_DIR="${HOME}/.gemini/config/agents"
PLATFORMS="claude codex antigravity"
FORCE=false
DRY_RUN=false
declare -a selected=()

usage() {
  cat <<'EOF'
Usage: ./scripts/install-agents.sh [options]

Render each agents/<name>.json and agents/<name>.md into the requested
platforms:

  claude       ~/.claude/agents/<name>.md
  codex        ~/.codex/agents/<name>.toml
  antigravity  ~/.gemini/config/agents/<name>.md

Without --platform, every platform whose configuration directory exists is
installed; that detection uses ~/.claude, ~/.codex, and ~/.gemini regardless of
the install-dir overrides.

Options:
  --platform NAME           Install for claude, codex, or antigravity.
                            Repeatable and comma separated; "all" selects every
                            platform.
  --agent-dir DIR           Read agent definitions from DIR instead of agents/.
  --claude-install-dir DIR  Override ~/.claude/agents/.
  --codex-install-dir DIR   Override ~/.codex/agents/.
  --antigravity-install-dir DIR
                            Override ~/.gemini/config/agents/.
  --dry-run                 Print planned filesystem operations without changing anything.
  --force                   Back up differing destination files, then install.
  -h, --help                Print this help text.
EOF
}

die() {
  echo "install-agents: $*" >&2
  exit 1
}

run() {
  if "$DRY_RUN"; then
    printf '+ '
    printf '%q ' "$@"
    printf '\n'
  else
    "$@"
  fi
}

platform_install_dir() {
  case "$1" in
    claude) printf '%s\n' "$CLAUDE_INSTALL_DIR" ;;
    codex) printf '%s\n' "$CODEX_INSTALL_DIR" ;;
    antigravity) printf '%s\n' "$ANTIGRAVITY_INSTALL_DIR" ;;
  esac
}

platform_config_dir() {
  case "$1" in
    claude) printf '%s\n' "${HOME}/.claude" ;;
    codex) printf '%s\n' "${HOME}/.codex" ;;
    antigravity) printf '%s\n' "${HOME}/.gemini" ;;
  esac
}

platform_suffix() {
  case "$1" in
    codex) printf '%s\n' toml ;;
    *) printf '%s\n' md ;;
  esac
}

platform_template() {
  case "$1" in
    claude) printf '%s\n' "$RENDER_DIR/claude.md.jq" ;;
    codex) printf '%s\n' "$RENDER_DIR/codex.toml.jq" ;;
    antigravity) printf '%s\n' "$RENDER_DIR/antigravity.md.jq" ;;
  esac
}

select_platform() {
  local platform="$1" existing
  case " $PLATFORMS " in
    *" $platform "*) ;;
    *) die "unknown platform: $platform (choose from: $PLATFORMS)" ;;
  esac
  for existing in ${selected[@]+"${selected[@]}"}; do
    [ "$existing" = "$platform" ] && return
  done
  selected+=("$platform")
}

select_platforms() {
  local item platform
  local -a items=()
  IFS=',' read -r -a items <<<"$1"
  for item in ${items[@]+"${items[@]}"}; do
    case "$item" in
      '') continue ;;
      all)
        for platform in $PLATFORMS; do
          select_platform "$platform"
        done
        ;;
      *) select_platform "$item" ;;
    esac
  done
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --platform)
      [ "$#" -ge 2 ] || die '--platform requires a platform name'
      select_platforms "$2"
      shift
      ;;
    --agent-dir)
      [ "$#" -ge 2 ] || die '--agent-dir requires a directory'
      AGENT_DIR="$2"
      shift
      ;;
    --claude-install-dir)
      [ "$#" -ge 2 ] || die '--claude-install-dir requires a directory'
      CLAUDE_INSTALL_DIR="$2"
      shift
      ;;
    --codex-install-dir)
      [ "$#" -ge 2 ] || die '--codex-install-dir requires a directory'
      CODEX_INSTALL_DIR="$2"
      shift
      ;;
    --antigravity-install-dir)
      [ "$#" -ge 2 ] || die '--antigravity-install-dir requires a directory'
      ANTIGRAVITY_INSTALL_DIR="$2"
      shift
      ;;
    --dry-run) DRY_RUN=true ;;
    --force) FORCE=true ;;
    -h|--help)
      usage
      exit 0
      ;;
    *) die "unknown option: $1" ;;
  esac
  shift
done

command -v jq >/dev/null 2>&1 || die 'jq not found; install jq to render agents'
[ -d "$AGENT_DIR" ] || die "agent directory does not exist: $AGENT_DIR"
AGENT_DIR="$(cd "$AGENT_DIR" && pwd -P)"

shopt -s nullglob
agent_json_files=("$AGENT_DIR"/*.json)
shopt -u nullglob
[ "${#agent_json_files[@]}" -gt 0 ] || die "no agent definitions found in: $AGENT_DIR"

if [ "${#selected[@]}" -eq 0 ]; then
  for platform in $PLATFORMS; do
    if [ -d "$(platform_config_dir "$platform")" ]; then
      selected+=("$platform")
    fi
  done
  [ "${#selected[@]}" -gt 0 ] || die "no platform configuration directory found; pass --platform"
  for platform in $PLATFORMS; do
    if ! printf '%s\n' "${selected[@]}" | grep -qx "$platform"; then
      echo "Skipping $platform: $(platform_config_dir "$platform") does not exist" >&2
    fi
  done
fi

for platform in "${selected[@]}"; do
  template="$(platform_template "$platform")"
  [ -f "$template" ] || die "missing render template: $template"
done

declare -a agent_names=()
for json_file in "${agent_json_files[@]}"; do
  name="$(basename "$json_file" .json)"
  body_file="$AGENT_DIR/$name.md"
  [ -f "$body_file" ] || die "missing system prompt for $name: $body_file"
  declared_name="$(jq -r '.name // empty' "$json_file")" || die "unreadable JSON: $json_file"
  [ "$declared_name" = "$name" ] ||
    die "$json_file declares name \"$declared_name\"; it must match the file name"
  description="$(jq -r '.description // empty' "$json_file")"
  [ -n "$description" ] || die "$json_file has no description"
  agent_names+=("$name")
done

staging="$(mktemp -d "${TMPDIR:-/tmp}/install-agents.XXXXXX")"
trap 'rm -rf "$staging"' EXIT

render() {
  local platform="$1" name="$2" body_file="$AGENT_DIR/$2.md" rendered
  rendered="$staging/$platform.$name.$(platform_suffix "$platform")"
  jq -r --arg body "$(<"$body_file")" -f "$(platform_template "$platform")" \
    "$AGENT_DIR/$name.json" >"$rendered" ||
    die "failed to render $name for $platform"
  printf '%s\n' "$rendered"
}

# A destination is current when it holds exactly what the templates render now.
is_current() {
  [ -f "$1" ] && cmp -s "$2" "$1"
}

backup_path() {
  local target="$1" candidate suffix=1

  candidate="$target.backup.$(date +%Y%m%d%H%M%S)"
  while [ -e "$candidate" ] || [ -L "$candidate" ]; do
    candidate="$target.backup.$(date +%Y%m%d%H%M%S).$suffix"
    suffix=$((suffix + 1))
  done
  printf '%s\n' "$candidate"
}

declare -a plan_sources=()
declare -a plan_targets=()
for platform in "${selected[@]}"; do
  install_dir="$(platform_install_dir "$platform")"
  for name in "${agent_names[@]}"; do
    plan_sources+=("$(render "$platform" "$name")")
    plan_targets+=("$install_dir/$name.$(platform_suffix "$platform")")
  done
done

# Refuse before changing anything: a destination that differs is either a
# reinstall after a source change (--force backs it up) or a user edit.
for index in "${!plan_targets[@]}"; do
  target="${plan_targets[$index]}"
  source="${plan_sources[$index]}"
  if is_current "$target" "$source"; then
    continue
  fi
  if [ -e "$target" ] || [ -L "$target" ]; then
    "$FORCE" || die "refusing to replace differing agent file: $target (rerun with --force)"
  fi
done

declare -a installed_dirs=()
for platform in "${selected[@]}"; do
  install_dir="$(platform_install_dir "$platform")"
  run mkdir -p "$install_dir"
  installed_dirs+=("$install_dir")
done

written=0
for index in "${!plan_targets[@]}"; do
  target="${plan_targets[$index]}"
  source="${plan_sources[$index]}"
  if is_current "$target" "$source"; then
    continue
  fi
  if [ -e "$target" ] || [ -L "$target" ]; then
    backup="$(backup_path "$target")"
    run mv "$target" "$backup"
    echo "Backed up $target to $backup" >&2
  fi
  run cp "$source" "$target"
  written=$((written + 1))
done

destinations="${installed_dirs[0]}"
for dir in ${installed_dirs[@]+"${installed_dirs[@]:1}"}; do
  destinations+=" and $dir"
done
if "$DRY_RUN"; then
  echo "Dry run complete for $destinations"
elif [ "$written" -eq 0 ]; then
  echo "Agent definitions for ${selected[*]} are current in $destinations"
else
  echo "Installed ${written} agent files for ${selected[*]} in $destinations"
fi
