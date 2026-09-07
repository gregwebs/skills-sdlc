#!/usr/bin/env bash
set -u
set -o pipefail

CHECK_FAILED=0
CHECK_COUNTER=0
CHECK_REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -d /private/tmp ]; then
  CHECK_TEMP_PARENT=/private/tmp
else
  CHECK_TEMP_PARENT=/tmp
fi
CHECK_TEMP_ROOT=$(mktemp -d "$CHECK_TEMP_PARENT/check-skill-inlines.XXXXXX") || exit 1

# Invoked indirectly by the EXIT trap below.
# shellcheck disable=SC2329
cleanup() {
  if [ -n "${CHECK_TEMP_ROOT:-}" ] && [ -d "$CHECK_TEMP_ROOT" ]; then
    rm -rf "$CHECK_TEMP_ROOT"
  fi
}
trap cleanup EXIT

usage() {
  cat <<'EOF'
Usage: ./scripts/check-skill-inlines.sh [SKILL.md ...]
Check local skill provenance. Review upstream changes before refreshing a digest.
EOF
}

fail_check() {
  local skill="$1"
  local message="$2"
  printf '%s: %s\n' "$skill" "$message" >&2
  printf '  Review upstream changes before refreshing the digest.\n' >&2
  CHECK_FAILED=1
}

trim_yaml_value() {
  local value="$1"
  local length

  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  length=${#value}
  if [ "$length" -ge 2 ]; then
    if { [ "${value:0:1}" = '"' ] && [ "${value:length-1:1}" = '"' ]; } ||
      { [ "${value:0:1}" = "'" ] && [ "${value:length-1:1}" = "'" ]; }; then
      value="${value:1:length-2}"
    fi
  fi
  TRIMMED_YAML_VALUE="$value"
}

reject_tabbed_value() {
  local skill="$1"
  local value="$2"
  if [[ "$value" == *$'\t'* ]]; then
    fail_check "$skill" 'tabs are unsupported in inlined-from values'
    return 1
  fi
  return 0
}

parse_inline_metadata() {
  local skill="$1"
  local output="$2"
  local raw_line line value
  local in_metadata=0
  local inline_declared=0
  local parsing_inline=0
  local saw_group=0
  local group_active=0
  local saw_scope=0
  local saw_digest=0
  local saw_components=0
  local component_open=0
  local frontmatter_closed=0
  local pending_source_section=''

  : >"$output"
  exec 3<"$skill" || {
    fail_check "$skill" 'cannot read local skill'
    return 1
  }

  if ! IFS= read -r raw_line <&3; then
    exec 3<&-
    return 0
  fi
  line="${raw_line%$'\r'}"
  if [ "$line" != '---' ]; then
    exec 3<&-
    return 0
  fi

  while IFS= read -r raw_line <&3 || [ -n "$raw_line" ]; do
    line="${raw_line%$'\r'}"

    if [ "$line" = '---' ]; then
      frontmatter_closed=1
      break
    fi

    if [[ "$line" =~ ^[^[:space:]] ]]; then
      if [ "$line" = 'metadata:' ]; then
        if [ "$in_metadata" -eq 1 ]; then
          fail_check "$skill" 'duplicate metadata declaration'
          exec 3<&-
          return 1
        fi
        in_metadata=1
        parsing_inline=0
      else
        in_metadata=0
        parsing_inline=0
      fi
      continue
    fi

    if [ "$in_metadata" -ne 1 ]; then
      continue
    fi

    if [ "$line" = '  inlined-from:' ]; then
      if [ "$inline_declared" -eq 1 ]; then
        fail_check "$skill" 'duplicate inlined-from declaration'
        exec 3<&-
        return 1
      fi
      inline_declared=1
      parsing_inline=1
      continue
    fi
    if [[ "$line" == '  inlined-from:'* ]]; then
      fail_check "$skill" "unsupported inlined-from YAML shape: $line"
      exec 3<&-
      return 1
    fi

    if [ "$parsing_inline" -ne 1 ]; then
      continue
    fi

    if [[ "$line" == '    - source:'* ]]; then
      if [ "$component_open" -eq 1 ]; then
        fail_check "$skill" 'component requires local-section'
        exec 3<&-
        return 1
      fi
      value="${line#    - source:}"
      trim_yaml_value "$value"
      value="$TRIMMED_YAML_VALUE"
      if [ -z "$value" ] || ! reject_tabbed_value "$skill" "$value"; then
        [ -n "$value" ] || fail_check "$skill" 'source cannot be empty'
        exec 3<&-
        return 1
      fi
      printf 'G\t%s\n' "$value" >>"$output"
      saw_group=1
      group_active=1
      saw_scope=0
      saw_digest=0
      saw_components=0
      component_open=0
      continue
    fi

    if [[ "$line" == '      source-scope:'* ]]; then
      if [ "$group_active" -ne 1 ]; then
        fail_check "$skill" 'source-scope before source'
        exec 3<&-
        return 1
      fi
      if [ "$saw_scope" -eq 1 ] || [ "$saw_components" -eq 1 ]; then
        fail_check "$skill" 'duplicate or misplaced source-scope'
        exec 3<&-
        return 1
      fi
      value="${line#      source-scope:}"
      trim_yaml_value "$value"
      value="$TRIMMED_YAML_VALUE"
      if ! reject_tabbed_value "$skill" "$value"; then
        exec 3<&-
        return 1
      fi
      printf 'S\t%s\n' "$value" >>"$output"
      saw_scope=1
      continue
    fi

    if [[ "$line" == '      source-scope-sha256:'* ]]; then
      if [ "$group_active" -ne 1 ]; then
        fail_check "$skill" 'source-scope-sha256 before source'
        exec 3<&-
        return 1
      fi
      if [ "$saw_digest" -eq 1 ] || [ "$saw_components" -eq 1 ]; then
        fail_check "$skill" 'duplicate or misplaced source-scope-sha256'
        exec 3<&-
        return 1
      fi
      value="${line#      source-scope-sha256:}"
      trim_yaml_value "$value"
      value="$TRIMMED_YAML_VALUE"
      if ! reject_tabbed_value "$skill" "$value"; then
        exec 3<&-
        return 1
      fi
      printf 'H\t%s\n' "$value" >>"$output"
      saw_digest=1
      continue
    fi

    if [ "$line" = '      components:' ]; then
      if [ "$group_active" -ne 1 ]; then
        fail_check "$skill" 'components before source'
        exec 3<&-
        return 1
      fi
      if [ "$saw_components" -eq 1 ]; then
        fail_check "$skill" 'duplicate components inventory'
        exec 3<&-
        return 1
      fi
      printf 'B\n' >>"$output"
      saw_components=1
      continue
    fi

    if [[ "$line" == '        - source-section:'* ]]; then
      if [ "$group_active" -ne 1 ] || [ "$saw_components" -ne 1 ]; then
        fail_check "$skill" 'component before components inventory'
        exec 3<&-
        return 1
      fi
      if [ "$component_open" -eq 1 ]; then
        fail_check "$skill" 'component requires local-section'
        exec 3<&-
        return 1
      fi
      value="${line#        - source-section:}"
      trim_yaml_value "$value"
      value="$TRIMMED_YAML_VALUE"
      if [ -z "$value" ] || ! reject_tabbed_value "$skill" "$value"; then
        [ -n "$value" ] || fail_check "$skill" 'source-section cannot be empty'
        exec 3<&-
        return 1
      fi
      pending_source_section="$value"
      component_open=1
      continue
    fi

    if [[ "$line" == '          local-section:'* ]]; then
      if [ "$component_open" -ne 1 ]; then
        fail_check "$skill" 'local-section without source-section'
        exec 3<&-
        return 1
      fi
      value="${line#          local-section:}"
      trim_yaml_value "$value"
      value="$TRIMMED_YAML_VALUE"
      if [ -z "$value" ] || ! reject_tabbed_value "$skill" "$value"; then
        [ -n "$value" ] || fail_check "$skill" 'local-section cannot be empty'
        exec 3<&-
        return 1
      fi
      printf 'C\t%s\t%s\n' "$pending_source_section" "$value" >>"$output"
      component_open=0
      continue
    fi

    if [ -z "$line" ]; then
      continue
    fi

    if [[ "$line" =~ ^[[:space:]]{2}[^[:space:]] ]]; then
      if [ "$component_open" -eq 1 ]; then
        fail_check "$skill" 'component requires local-section'
        exec 3<&-
        return 1
      fi
      parsing_inline=0
      continue
    fi

    fail_check "$skill" "unsupported inlined-from YAML shape: $line"
    exec 3<&-
    return 1
  done
  exec 3<&-

  if [ "$inline_declared" -eq 1 ] && [ "$frontmatter_closed" -ne 1 ]; then
    fail_check "$skill" 'unterminated frontmatter'
    return 1
  fi
  if [ "$component_open" -eq 1 ]; then
    fail_check "$skill" 'component requires local-section'
    return 1
  fi
  if [ "$inline_declared" -eq 1 ] && [ "$saw_group" -ne 1 ]; then
    fail_check "$skill" 'empty inlined-from declaration'
    return 1
  fi
  return 0
}

scan_headings() {
  local path="$1"
  local output="$2"

  LC_ALL=C awk '
    BEGIN {
      offset = 0
      first = 1
      frontmatter = 0
      fence = ""
    }
    {
      raw = $0
      line = $0
      sub(/\r$/, "", line)

      if (first) {
        first = 0
        if (line == "---") {
          frontmatter = 1
          offset += length(raw) + 1
          next
        }
      }
      if (frontmatter) {
        if (line == "---") {
          frontmatter = 0
        }
        offset += length(raw) + 1
        next
      }

      indent = 0
      while (indent < 4 && substr(line, indent + 1, 1) == " ") {
        indent++
      }
      rest = substr(line, indent + 1)
      marker = substr(rest, 1, 1)
      triple = marker marker marker
      if (indent <= 3 && (marker == "`" || marker == "~") &&
          substr(rest, 1, 3) == triple) {
        run = 0
        while (substr(rest, run + 1, 1) == marker) {
          run++
        }
        tail = substr(rest, run + 1)
        if (fence == "") {
          fence = marker
        } else if (fence == marker && tail ~ /^[ \t]*$/) {
          fence = ""
        }
        offset += length(raw) + 1
        next
      }

      if (fence == "") {
        level = 0
        while (level < 7 && substr(line, level + 1, 1) == "#") {
          level++
        }
        if (level >= 1 && level <= 6) {
          heading = substr(line, level + 1)
          if (heading ~ /^[ \t]+/) {
            sub(/^[ \t]+/, "", heading)
            sub(/[ \t]+$/, "", heading)
            hashes = substr(line, 1, level)
            print offset "\t" level "\t" hashes " " heading
          }
        }
      }
      offset += length(raw) + 1
    }
  ' "$path" >"$output"
}

unique_heading() {
  local headings_file="$1"
  local target="$2"
  local result status

  result=$(awk -F '\t' -v target="$target" '
    {
      text = $3
      for (i = 4; i <= NF; i++) {
        text = text FS $i
      }
      if (text == target) {
        count++
        found_offset = $1
        found_level = $2
      }
    }
    END {
      if (count == 1) {
        print found_offset "\t" found_level
        exit 0
      }
      if (count == 0) {
        exit 3
      }
      exit 4
    }
  ' "$headings_file")
  status=$?

  case "$status" in
    0)
      HEADING_OFFSET="${result%%$'\t'*}"
      HEADING_LEVEL="${result#*$'\t'}"
      HEADING_ERROR=''
      return 0
      ;;
    3)
      HEADING_ERROR='missing'
      return 1
      ;;
    *)
      HEADING_ERROR='duplicate'
      return 1
      ;;
  esac
}

scope_end_offset() {
  local headings_file="$1"
  local start="$2"
  local level="$3"
  local file_size="$4"
  local result

  result=$(awk -F '\t' -v start="$start" -v level="$level" '
    $1 > start && $2 <= level {
      print $1
      exit
    }
  ' "$headings_file")
  if [ -n "$result" ]; then
    SCOPE_END="$result"
  else
    SCOPE_END="$file_size"
  fi
}

sha256_range() {
  local path="$1"
  local start="$2"
  local length="$3"

  dd if="$path" bs=1 skip="$start" count="$length" 2>/dev/null |
    openssl dgst -sha256 |
    awk '{print $NF}'
}

check_group() {
  local skill_display="$1"
  local local_headings="$2"
  local group_source="$3"
  local group_scope="$4"
  local group_digest="$5"
  local components_seen="$6"
  local components_file="$7"
  local declaring_dir="$8"
  local component_count upstream_path source_headings source_size
  local scope_offset scope_level scope_end actual_digest
  local source_section local_section source_offset
  local complete=1

  if [ -z "$group_source" ]; then
    fail_check "$skill_display" 'missing source'
    complete=0
  fi
  if [ -z "$group_scope" ]; then
    fail_check "$skill_display" 'missing source-scope'
    complete=0
  fi
  if [ -z "$group_digest" ]; then
    fail_check "$skill_display" 'missing source-scope-sha256'
    complete=0
  fi
  if [ "$components_seen" -ne 1 ]; then
    fail_check "$skill_display" "missing components inventory for $group_source"
    complete=0
  fi

  component_count=$(wc -l <"$components_file")
  component_count="${component_count//[[:space:]]/}"
  if [ "${component_count:-0}" -eq 0 ]; then
    fail_check "$skill_display" "empty components inventory for $group_source"
    complete=0
  fi
  [ "$complete" -eq 1 ] || return

  if [[ ! "$group_digest" =~ ^[0-9a-f]{64}$ ]]; then
    fail_check "$skill_display" "malformed digest for $group_source $group_scope"
    return
  fi

  if [[ "$group_source" == /* ]]; then
    upstream_path="$group_source"
  elif [[ "$group_source" == \~/* ]]; then
    if [ -z "${HOME:-}" ]; then
      fail_check "$skill_display" "cannot expand source without HOME: $group_source"
      return
    fi
    upstream_path="${HOME%/}/${group_source:2}"
  elif [[ "$group_source" == ./* || "$group_source" == ../* ]]; then
    upstream_path="$declaring_dir/$group_source"
  else
    fail_check "$skill_display" "unsupported relative source path: $group_source"
    return
  fi

  if [ ! -r "$upstream_path" ]; then
    fail_check "$skill_display" "cannot read upstream source $group_source"
    return
  fi

  CHECK_COUNTER=$((CHECK_COUNTER + 1))
  source_headings="$CHECK_TEMP_ROOT/source-headings.$CHECK_COUNTER"
  if ! scan_headings "$upstream_path" "$source_headings"; then
    fail_check "$skill_display" "cannot scan upstream source $group_source"
    return
  fi

  if ! unique_heading "$source_headings" "$group_scope"; then
    fail_check "$skill_display" "$HEADING_ERROR upstream scope $group_scope in $group_source"
    return
  fi
  scope_offset="$HEADING_OFFSET"
  scope_level="$HEADING_LEVEL"
  source_size=$(wc -c <"$upstream_path")
  source_size="${source_size//[[:space:]]/}"
  scope_end_offset "$source_headings" "$scope_offset" "$scope_level" "$source_size"
  scope_end="$SCOPE_END"

  if ! actual_digest=$(sha256_range "$upstream_path" "$scope_offset" "$((scope_end - scope_offset))"); then
    fail_check "$skill_display" "cannot hash upstream scope $group_scope in $group_source"
    return
  fi
  if [ "$actual_digest" != "$group_digest" ]; then
    fail_check "$skill_display" "upstream scope digest drift at $group_source $group_scope"
  fi

  while IFS=$'\t' read -r source_section local_section; do
    if ! unique_heading "$source_headings" "$source_section"; then
      fail_check "$skill_display" "$HEADING_ERROR upstream component $source_section in $group_source; local $local_section"
    else
      source_offset="$HEADING_OFFSET"
      if [ "$source_offset" -lt "$scope_offset" ] || [ "$source_offset" -ge "$scope_end" ]; then
        fail_check "$skill_display" "upstream component $source_section falls outside scope $group_scope in $group_source; local $local_section"
      fi
    fi

    if ! unique_heading "$local_headings" "$local_section"; then
      fail_check "$skill_display" "$HEADING_ERROR local component $local_section for upstream $source_section"
    fi
  done <"$components_file"
}

process_skill() {
  local skill_path="$1"
  local skill_display="$2"
  local parsed_file local_headings components_file declaring_dir
  local operation first second
  local group_active=0
  local group_source=''
  local group_scope=''
  local group_digest=''
  local components_seen=0

  CHECK_COUNTER=$((CHECK_COUNTER + 1))
  parsed_file="$CHECK_TEMP_ROOT/parsed.$CHECK_COUNTER"
  local_headings="$CHECK_TEMP_ROOT/local-headings.$CHECK_COUNTER"
  components_file="$CHECK_TEMP_ROOT/components.$CHECK_COUNTER"
  : >"$components_file"

  if [ ! -r "$skill_path" ]; then
    fail_check "$skill_display" 'cannot read local skill'
    return
  fi
  declaring_dir="$(cd "$(dirname "$skill_path")" && pwd -P)"
  if ! parse_inline_metadata "$skill_path" "$parsed_file"; then
    return
  fi
  if [ ! -s "$parsed_file" ]; then
    return
  fi
  if ! scan_headings "$skill_path" "$local_headings"; then
    fail_check "$skill_display" 'cannot scan local skill'
    return
  fi

  while IFS=$'\t' read -r operation first second; do
    case "$operation" in
      G)
        if [ "$group_active" -eq 1 ]; then
          check_group "$skill_display" "$local_headings" \
            "$group_source" "$group_scope" "$group_digest" \
            "$components_seen" "$components_file" "$declaring_dir"
        fi
        group_active=1
        group_source="$first"
        group_scope=''
        group_digest=''
        components_seen=0
        : >"$components_file"
        ;;
      S)
        group_scope="$first"
        ;;
      H)
        group_digest="$first"
        ;;
      B)
        components_seen=1
        ;;
      C)
        printf '%s\t%s\n' "$first" "$second" >>"$components_file"
        ;;
    esac
  done <"$parsed_file"

  if [ "$group_active" -eq 1 ]; then
    check_group "$skill_display" "$local_headings" \
      "$group_source" "$group_scope" "$group_digest" \
      "$components_seen" "$components_file" "$declaring_dir"
  fi
}

if [ "$#" -gt 0 ] && [ "$1" = '--help' ]; then
  usage
  exit 0
fi

for dependency in awk dd git mktemp openssl wc; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    printf 'check-skill-inlines: required command not found: %s\n' "$dependency" >&2
    exit 1
  fi
done

skills_file="$CHECK_TEMP_ROOT/skills"
if [ "$#" -gt 0 ]; then
  printf '%s\n' "$@" >"$skills_file"
  while IFS= read -r skill_path; do
    process_skill "$skill_path" "$skill_path"
  done <"$skills_file"
else
  git -C "$CHECK_REPOSITORY_ROOT" ls-files '*SKILL.md' >"$skills_file"
  while IFS= read -r skill_path; do
    process_skill "$CHECK_REPOSITORY_ROOT/$skill_path" "$skill_path"
  done <"$skills_file"
fi

exit "$CHECK_FAILED"
