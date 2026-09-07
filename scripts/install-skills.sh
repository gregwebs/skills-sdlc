#!/usr/bin/env bash
# Install this repository's skill overrides and their Matt Pocock dependencies
# into agent skill directories without copying their source files.
set -euo pipefail

REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_SKILLS_DIR="$REPOSITORY_ROOT/.agents/skills"
UPSTREAM_SKILLS_DIR="$REPOSITORY_ROOT/vendor/mattpocock/skills"
UPSTREAM_SKILLS_DIR_EXPLICIT=false
INSTALL_DIR="${HOME}/.agent/skills"
SCAN_DIR="$REPOSITORY_ROOT"
FORCE=false
DRY_RUN=false

usage() {
  cat <<'EOF'
Usage: ./scripts/install-skills.sh [options]

Symlink this repository's skill overrides and the referenced Matt Pocock skills
from its pinned submodule into ~/.agent/skills. If ~/.claude already exists,
install matching links into its ~/.claude/skills directory too.

Options:
  --force                       Back up and replace destination conflicts.
  --dry-run                     Print the actions without changing files.
  --local-skills-dir DIR        Override the repository skill source directory.
  --upstream-skills-dir DIR     Override the Matt Pocock skill source directory.
  --install-dir DIR             Override ~/.agent/skills (useful for testing).
  --scan-dir DIR                Override the documentation and skill scan root.
  -h, --help                    Show this help text.

The production upstream source is vendor/mattpocock/skills. Initialize it with:
  git submodule update --init --recursive
EOF
}

die() {
  echo "install-skills: $*" >&2
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

while [ "$#" -gt 0 ]; do
  case "$1" in
    --force) FORCE=true ;;
    --dry-run) DRY_RUN=true ;;
    --local-skills-dir)
      [ "$#" -ge 2 ] || die "--local-skills-dir requires a directory"
      LOCAL_SKILLS_DIR="$2"
      shift
      ;;
    --upstream-skills-dir)
      [ "$#" -ge 2 ] || die "--upstream-skills-dir requires a directory"
      UPSTREAM_SKILLS_DIR="$2"
      UPSTREAM_SKILLS_DIR_EXPLICIT=true
      shift
      ;;
    --install-dir)
      [ "$#" -ge 2 ] || die "--install-dir requires a directory"
      INSTALL_DIR="$2"
      shift
      ;;
    --scan-dir)
      [ "$#" -ge 2 ] || die "--scan-dir requires a directory"
      SCAN_DIR="$2"
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

[ -d "$LOCAL_SKILLS_DIR" ] || die "local skill directory does not exist: $LOCAL_SKILLS_DIR"
[ -d "$SCAN_DIR" ] || die "scan directory does not exist: $SCAN_DIR"
if [ ! -d "$UPSTREAM_SKILLS_DIR" ]; then
  if "$UPSTREAM_SKILLS_DIR_EXPLICIT"; then
    die "upstream skill directory does not exist: $UPSTREAM_SKILLS_DIR"
  fi
  die "Matt Pocock submodule is uninitialized: $REPOSITORY_ROOT/vendor/mattpocock (run: git submodule update --init --recursive)"
fi
LOCAL_SKILLS_DIR="$(cd "$LOCAL_SKILLS_DIR" && pwd -P)"
UPSTREAM_SKILLS_DIR="$(cd "$UPSTREAM_SKILLS_DIR" && pwd -P)"
SCAN_DIR="$(cd "$SCAN_DIR" && pwd -P)"

# This inventory lets the audit distinguish a slash-command reference from a
# filesystem path or a built-in command such as /plan. Keep it in sync with the
# upstream repository when its skill inventory changes.
MATTPOCOCK_SKILLS=(
  ask-matt code-review codebase-design diagnosing-bugs domain-modeling
  grilling grill-me grill-with-docs handoff implement improve-codebase-architecture
  prototype research resolving-merge-conflicts
  setup-matt-pocock-skills tdd teach to-spec to-tickets triage wayfinder
  writing-great-skills
)

is_mattpocock_skill() {
  local candidate="$1" skill
  for skill in "${MATTPOCOCK_SKILLS[@]}"; do
    [ "$skill" = "$candidate" ] && return 0
  done
  return 1
}

local_skills=()
shopt -s nullglob
for skill_file in "$LOCAL_SKILLS_DIR"/*/SKILL.md; do
  local_skills+=("$(basename "${skill_file%/SKILL.md}")")
done
shopt -u nullglob
[ "${#local_skills[@]}" -gt 0 ] || die "no SKILL.md files found in: $LOCAL_SKILLS_DIR"

is_local_skill() {
  local candidate="$1" skill
  for skill in "${local_skills[@]}"; do
    [ "$skill" = "$candidate" ] && return 0
  done
  return 1
}

mapfile -t referenced_commands < <(
  find "$SCAN_DIR" \
    -path '*/.git' -prune -o \
    -path "$REPOSITORY_ROOT/vendor/mattpocock" -prune -o \
    -path "$UPSTREAM_SKILLS_DIR" -prune -o \
    -type f \( -name '*.md' -o -name '*.yaml' -o -name '*.yml' \) -print0 |
    xargs -0 rg --no-filename --only-matching --pcre2 \
      '(?<![[:alnum:]_.:/~-])/([a-z][a-z0-9-]*)(?![a-z0-9-]|/)' 2>/dev/null |
    sed 's#^/##' | sort -u
)

dependencies=()
for command in "${referenced_commands[@]}"; do
  if is_mattpocock_skill "$command" && ! is_local_skill "$command"; then
    dependencies+=("$command")
  fi
done

resolve_mattpocock_skill_dir() {
  local name="$1"
  local -a matches=()
  local candidate

  if [ -f "$UPSTREAM_SKILLS_DIR/$name/SKILL.md" ]; then
    matches+=("$UPSTREAM_SKILLS_DIR/$name")
  fi
  shopt -s nullglob
  for candidate in "$UPSTREAM_SKILLS_DIR"/*/"$name"/SKILL.md; do
    matches+=("${candidate%/SKILL.md}")
  done
  shopt -u nullglob

  case "${#matches[@]}" in
    0) return 1 ;;
    1) printf '%s\n' "${matches[0]}" ;;
    *) return 2 ;;
  esac
}

dependency_sources=()
missing_dependencies=()
ambiguous_dependencies=()
for dependency in "${dependencies[@]}"; do
  if source=$(resolve_mattpocock_skill_dir "$dependency"); then
    dependency_sources+=("$source")
  else
    case "$?" in
      1) missing_dependencies+=("$dependency") ;;
      2) ambiguous_dependencies+=("$dependency") ;;
    esac
  fi
done

if [ "${#missing_dependencies[@]}" -gt 0 ]; then
  printf 'Missing Matt Pocock skills: %s\n' "${missing_dependencies[*]}" >&2
fi
if [ "${#ambiguous_dependencies[@]}" -gt 0 ]; then
  printf 'Ambiguous Matt Pocock skills: %s\n' "${ambiguous_dependencies[*]}" >&2
fi
if [ "${#missing_dependencies[@]}" -gt 0 ] || [ "${#ambiguous_dependencies[@]}" -gt 0 ]; then
  die 'all referenced Matt Pocock skills must resolve exactly once in the upstream source'
fi

absolute_dir() {
  (cd "$1" && pwd -P)
}

link_skill() {
  local destination="$1" source="$2" name target backup
  name="$(basename "$source")"
  target="$destination/$name"
  if [ -e "$target" ] || [ -L "$target" ]; then
    [ "$target" -ef "$source" ] && return
    if ! "$FORCE"; then
      die "refusing to replace existing skill link: $target $source (rerun with --force)"
    fi
    backup="$target.backup.$(date +%Y%m%d%H%M%S)"
    run mv "$target" "$backup"
    echo "Backed up $target to $backup" >&2
  fi
  run ln -s "$source" "$target"
}

link_all_skills() {
  local destination="$1" name source index
  run mkdir -p "$destination"
  for name in "${local_skills[@]}"; do
    source="$(absolute_dir "$LOCAL_SKILLS_DIR/$name")"
    link_skill "$destination" "$source"
  done
  for index in "${!dependencies[@]}"; do
    source="$(absolute_dir "${dependency_sources[$index]}")"
    link_skill "$destination" "$source"
  done
}

link_all_skills "$INSTALL_DIR"

CLAUDE_DIR="${HOME}/.claude"
CLAUDE_SKILLS_DIR="$CLAUDE_DIR/skills"
if [ -d "$CLAUDE_DIR" ]; then
  # Claude commonly points this directory at ~/.agents/skills while Codex uses
  # ~/.agent/skills. They need not resolve to the same directory: link the
  # required individual skills in either layout and preserve the user's root.
  link_all_skills "$CLAUDE_SKILLS_DIR"
fi

echo "Installed skill links in $INSTALL_DIR"
