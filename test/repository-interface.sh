#!/usr/bin/env bash
# Contract test for the repository's stable command-line interface.
set -euo pipefail

REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GITHUB_APP_SCRIPTS="$REPOSITORY_ROOT/skills/github-app/scripts"
GITHUB_WRAPPER="$GITHUB_APP_SCRIPTS/gh-app.sh"
GITHUB_DEPENDENCY="$GITHUB_APP_SCRIPTS/gh-app-issue-dependency.sh"
GITHUB_SUB_ISSUE="$GITHUB_APP_SCRIPTS/gh-app-issue-sub-issue.sh"
CI_CHECKER="$REPOSITORY_ROOT/./skills/github-actions-ci/scripts/check-ci-runs.sh"
INLINE_CHECKER="$REPOSITORY_ROOT/scripts/check-skill-inlines.sh"

fail() {
  echo "test-repository-interface: $*" >&2
  exit 1
}

assert_json() {
  local query="$1" expected="$2"
  local actual
  actual=$(jq -r "$query" "$REPOSITORY_ROOT/.claude/settings.local.json")
  [ "$actual" = "$expected" ] || fail "expected $query to be $expected, got $actual"
}

assert_executable() {
  [ -x "$1" ] || fail "expected executable command: $1"
}

assert_readable() {
  [ -r "$1" ] || fail "expected readable dependency: $1"
}

assert_absent() {
  [ ! -e "$1" ] || fail "expected absent path: $1"
}

assert_tracked() {
  git -C "$REPOSITORY_ROOT" ls-files --error-unmatch -- "$1" >/dev/null \
    || fail "expected tracked path: $1"
}

assert_contains() {
  local path="$1" text="$2"
  rg -Fq -- "$text" "$REPOSITORY_ROOT/$path" \
    || fail "expected $path to contain: $text"
}

assert_help() {
  local help_output
  if ! help_output=$(cd "$TEMP_ROOT" && "$@" --help 2>&1); then
    fail "expected --help to succeed: $*"
  fi
  case "$help_output" in
    *"/skills/"*)
      fail "help exposed an implementation path: $help_output"
      ;;
  esac
}

assert_checker_result() {
  local expected="$1" fixture="$2"
  local output
  if output=$(HOME="${INLINE_FIXTURE_HOME:-$HOME}" "$INLINE_CHECKER" "$fixture" 2>&1); then
    [ "$expected" = pass ] || fail "expected checker failure for $fixture"
  else
    [ "$expected" = fail ] || fail "checker failed for $fixture: $output"
  fi
}

write_fixture() {
  local path="$1" contents="$2"
  printf '%s' "$contents" >"$path"
}

sha256_file() {
  local output
  output=$(openssl dgst -sha256 "$1") || fail "failed to hash fixture: $1"
  printf '%s\n' "${output##* }"
}

write_inline_skill() {
  local path="$1"
  local source="$2"
  local digest="$3"
  local metadata_before="$4"
  local metadata_after="$5"
  local local_body="$6"

  write_fixture "$path" "---
metadata:
${metadata_before}  inlined-from:
    - source: $source
      source-scope: \"## Process\"
      source-scope-sha256: \"$digest\"
      components:
        - source-section: \"### Source\"
          local-section: \"### Local\"
${metadata_after}---
${local_body}"
}

run_inline_fixtures() {
  local fixture_root source skill digest
  fixture_root=$(mktemp -d "$TEMP_ROOT/skills-sdlc-inline.XXXXXX")
  trap 'rm -rf "$fixture_root"' EXIT
  source="$fixture_root/upstream.md"
  skill="$fixture_root/SKILL.md"

  write_fixture "$source" $'## Process\n\n### Source\ntext\n'
  digest=$(sha256_file "$source")
  write_inline_skill "$skill" "$source" "$digest" '' '' $'### Local\ntext\n'
  assert_checker_result pass "$skill"

  write_inline_skill "$skill" './upstream.md' "$digest" '' '' $'### Local\ntext\n'
  assert_checker_result pass "$skill"
  mkdir -p "$fixture_root/nested"
  write_fixture "$fixture_root/nested/upstream.md" $'## Process\n\n### Source\ntext\n'
  write_inline_skill "$fixture_root/nested/SKILL.md" '../upstream.md' "$digest" '' '' $'### Local\ntext\n'
  assert_checker_result pass "$fixture_root/nested/SKILL.md"
  write_inline_skill "$skill" "$source" "$digest" '' '' $'### Local\ntext\n'

  write_inline_skill "$skill" "$source" "$digest" \
    $'  short-description: fixture\n' '' $'### Local\ntext\n'
  assert_checker_result pass "$skill"
  write_inline_skill "$skill" "$source" "$digest" \
    '' $'  local-note: fixture\n' $'### Local\ntext\n'
  assert_checker_result pass "$skill"

  write_fixture "$source" $'## Process\n### Source\ntext\n## Outside\ntext\n'
  write_fixture "$skill" "$(sed 's/source-section: "### Source"/source-section: "## Outside"/' "$skill")"
  assert_checker_result fail "$skill"
  write_fixture "$source" $'## Process\n\n### Source\ntext\n'
  digest=$(sha256_file "$source")
  write_inline_skill "$skill" "$source" "$digest" '' '' $'### Local\ntext\n'

  write_fixture "$skill" "$(sed "s|source: $source|source: $fixture_root/missing.md|" "$skill")"
  assert_checker_result fail "$skill"
  write_fixture "$skill" "$(sed "s|source: $fixture_root/missing.md|source: relative/SKILL.md|" "$skill")"
  assert_checker_result fail "$skill"
  write_fixture "$skill" "$(sed 's|source: relative/SKILL.md|source: ~/upstream.md|' "$skill")"
  INLINE_FIXTURE_HOME="$fixture_root"
  assert_checker_result pass "$skill"
  unset INLINE_FIXTURE_HOME
  write_fixture "$skill" "$(sed "s|source: ~/upstream.md|source: $source|" "$skill")"

  write_fixture "$source" $'## Other\ntext\n'
  assert_checker_result fail "$skill"
  write_fixture "$source" $'## Process\na\n## Process\nb\n'
  assert_checker_result fail "$skill"
  write_fixture "$source" $'## Process\n### Other\ntext\n'
  assert_checker_result fail "$skill"
  write_fixture "$source" $'## Process\n### Source\na\n### Source\nb\n'
  assert_checker_result fail "$skill"
  write_fixture "$source" $'## Process\n### Source\ntext\n'
  digest=$(sha256_file "$source")
  write_fixture "$skill" "$(sed -e "s/[0-9a-f]\{64\}/$digest/" -e 's/local-section: "### Local"/local-section: "### Missing"/' "$skill")"
  assert_checker_result fail "$skill"
  write_inline_skill "$skill" "$source" "$digest" '' '' \
    $'### Local\ntext\n### Local\ntext\n'
  assert_checker_result fail "$skill"
  write_inline_skill "$skill" "$source" 'not-a-digest' '' '' \
    $'### Local\ntext\n'
  assert_checker_result fail "$skill"
  write_inline_skill "$skill" "$source" \
    '0000000000000000000000000000000000000000000000000000000000000000' \
    '' '' $'### Local\ntext\n'
  assert_checker_result fail "$skill"

  write_fixture "$source" $'## Process\n```markdown\n### Ignored\n```\n### Source\ntext\n'
  digest=$(sha256_file "$source")
  write_inline_skill "$skill" "$source" "$digest" '' '' $'### Local\ntext\n'
  assert_checker_result pass "$skill"

  write_fixture "$source" $'## Process\r\n### Source\r\ntext\r\n'
  digest=$(sha256_file "$source")
  write_fixture "$skill" "$(sed "s/[0-9a-f]\{64\}/$digest/" "$skill")"
  assert_checker_result pass "$skill"
  write_fixture "$source" $'## Process\r\n### Source\r\ntext'
  assert_checker_result fail "$skill"
  write_fixture "$source" $'## Process\n### Source\ntext\n### Inserted\nnew\n'
  assert_checker_result fail "$skill"
  write_fixture "$skill" "---
metadata:
  inlined-from:
    - source: $source
      source-scope: \"## Process\"
      source-scope-sha256: \"$digest\"
---
### Local
text
"
  assert_checker_result fail "$skill"
  trap - EXIT
  rm -rf "$fixture_root"
}

if [ -d /private/tmp ]; then
  TEMP_ROOT=/private/tmp
else
  TEMP_ROOT=/tmp
fi

run_inline_fixtures

assert_json '.model' 'opusplan'
assert_json '.permissions.defaultMode' 'plan'

assert_executable "$GITHUB_WRAPPER"
assert_executable "$GITHUB_DEPENDENCY"
assert_executable "$GITHUB_SUB_ISSUE"
assert_executable "$CI_CHECKER"
assert_absent "$REPOSITORY_ROOT/scripts/check-ci-runs.sh"
assert_absent "$REPOSITORY_ROOT/scripts/gh-app.sh"
assert_readable "$GITHUB_APP_SCRIPTS/gh-app-token.sh"
# The four scripts above are the whole GitHub App surface; the REST client is gone.
github_app_scripts=$(ls "$GITHUB_APP_SCRIPTS" | LC_ALL=C sort)
expected_github_app_scripts=$(printf '%s\n' gh-app.sh gh-app-token.sh \
  gh-app-issue-dependency.sh gh-app-issue-sub-issue.sh | LC_ALL=C sort)
[ "$github_app_scripts" = "$expected_github_app_scripts" ] \
  || fail "unexpected GitHub App scripts: $github_app_scripts"

for tracked_path in \
  ./skills/implementation-plan/SKILL.md \
  ./skills/implement/SKILL.md ; do
  assert_tracked "$tracked_path"
done

assert_contains ./skills/implement/SKILL.md 'Use the /orchestration skill to manage subagents.'
assert_contains ./skills/implement/SKILL.md 'task-brief.md'
assert_contains ./skills/implement/SKILL.md 'implementation-plan.md'
assert_contains ./skills/implement/SKILL.md 'implementation-result.md'
# This assertion intentionally searches for the literal skill-directory expression.
# shellcheck disable=SC2016
assert_contains ./skills/github-actions-ci/SKILL.md \
  'allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/check-ci-runs.sh *)'
# This assertion intentionally searches for the literal command substitution.
# shellcheck disable=SC2016
assert_contains ./skills/github-actions-ci/scripts/check-ci-runs.sh \
  'REPO_ROOT="$(git rev-parse --show-toplevel)"'
if rg -q 'Pass the .* output \*\*verbatim\*\*' \
  "$REPOSITORY_ROOT/./skills/implement/SKILL.md"; then
  fail 'implement workflow passes planner output inline instead of by artifact'
fi
if rg -q '\bmain\b' "$REPOSITORY_ROOT/./skills/pull-request/SKILL.md"; then
  fail 'pull-request instructions assume main instead of the discovered default branch'
fi
if rg -q 'docs/change/' "$REPOSITORY_ROOT/./skills/github-app"; then
  fail 'GitHub App instructions reference absent change history files'
fi
if rg -q '\./skills/|docs/change/' "$REPOSITORY_ROOT/skills/github-app/scripts"; then
  fail 'GitHub App bundled scripts contain a repository-local documentation reference'
fi
for script in \
  gh-app.sh \
  gh-app-issue-dependency.sh \
  gh-app-issue-sub-issue.sh; do
  assert_contains "./skills/github-app/scripts/$script" \
    'Requires a GitHub App set up per the Setup reference in the /github-app skill'
done

# The repository owns the expected inventory; the generic checker validates
# declarations but cannot know whether a copied section was omitted.
assert_contains ./skills/breakdown/SKILL.md 'inlined-from:'
assert_contains ./skills/breakdown/SKILL.md '### 4. Quiz the user'
assert_contains ./skills/implementation-plan/SKILL.md 'inlined-from:'
assert_contains ./skills/implementation-plan/SKILL.md '### 2. Identify the spec source'
assert_contains .gitmodules 'path = vendor/mattpocock'
assert_contains .gitmodules 'url = https://github.com/mattpocock/skills.git'
gitlink_mode=$(git -C "$REPOSITORY_ROOT" ls-files --stage -- vendor/mattpocock | awk '{print $1}')
[ "$gitlink_mode" = 160000 ] || fail 'expected vendor/mattpocock to be a gitlink'
assert_readable "$REPOSITORY_ROOT/vendor/mattpocock/LICENSE"
for upstream_skill in \
  engineering/code-review \
  engineering/codebase-design \
  engineering/diagnosing-bugs \
  engineering/grill-with-docs \
  engineering/improve-codebase-architecture \
  engineering/tdd \
  engineering/to-spec \
  engineering/to-tickets \
  productivity/handoff; do
  assert_readable "$REPOSITORY_ROOT/vendor/mattpocock/skills/$upstream_skill/SKILL.md"
done
assert_contains ./skills/breakdown/SKILL.md '../../vendor/mattpocock/'
assert_contains ./skills/implementation-plan/SKILL.md '../../vendor/mattpocock/'
if rg -Fq '.agent/skills' "$REPOSITORY_ROOT/skills/breakdown/SKILL.md" "$REPOSITORY_ROOT/skills/implementation-plan/SKILL.md"; then
  fail 'inline provenance relies on home-directory skills'
fi
for skill in implement github-tickets pull-request github-app github-actions-ci; do
  if rg -q 'inlined-from:' "$REPOSITORY_ROOT/./skills/$skill/SKILL.md"; then
    fail "unexpected inline provenance inventory for $skill"
  fi
done

"$INLINE_CHECKER"

assert_help "$CI_CHECKER"
assert_help "$GITHUB_DEPENDENCY"
assert_help "$GITHUB_SUB_ISSUE"

unknown_output=$(mktemp "$TEMP_ROOT/skills-sdlc-interface.XXXXXX")
trap 'rm -f "$unknown_output"' EXIT
for command in "$GITHUB_DEPENDENCY" "$GITHUB_SUB_ISSUE"; do
  if (cd "$TEMP_ROOT" && "$command" unknown-command >"$unknown_output" 2>&1); then
    fail "unknown command succeeded: $command"
  fi
  rg -q '^usage:' "$unknown_output" || fail "unknown command did not print usage: $command"
  if rg -q '/skills/' "$unknown_output"; then
    fail "unknown command exposed an implementation path: $command"
  fi
done

if rg -n -F './scripts/gh-app.sh' \
  "$REPOSITORY_ROOT/skills" "$REPOSITORY_ROOT/README.md" "$REPOSITORY_ROOT/CONTRIBUTING.md"; then
  fail 'documentation references the removed ./scripts/gh-app.sh entry point'
fi
# Skills name GitHub App scripts only as the three public entry points. Sibling
# skills reach them through ../github-app, which resolves in both the repository
# and installed skill layouts.
script_reference='[^[:space:]`("]*gh-app[a-z-]*\.sh'
# shellcheck disable=SC2016
own_entry_point='^\$\{CLAUDE_SKILL_DIR\}(/\.\./github-app)?/scripts/gh-app(-issue-dependency|-issue-sub-issue)?\.sh$'
# shellcheck disable=SC2016
sibling_entry_point='^\$\{CLAUDE_SKILL_DIR\}/\.\./github-app/scripts/gh-app(-issue-dependency|-issue-sub-issue)?\.sh$'
if rg -o --no-filename --no-line-number "$script_reference" \
  "$REPOSITORY_ROOT/skills/github-app/SKILL.md" | rg -v "$own_entry_point"; then
  fail 'the github-app skill bypasses its public entry points'
fi
if rg -o --no-filename --no-line-number "$script_reference" \
  "$REPOSITORY_ROOT/./skills" --glob 'SKILL.md' --glob '!**/github-app/SKILL.md' \
  | rg -v "$sibling_entry_point"; then
  fail 'sibling skills bypass the github-app entry points'
fi
if rg -n '\./scripts/check-ci-runs\.sh' \
  "$REPOSITORY_ROOT/./skills" \
  --glob 'SKILL.md'; then
  fail 'workflow skills expect a repository-local CI checker'
fi

echo 'repository interface contract passed'
