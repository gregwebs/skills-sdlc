#!/usr/bin/env bash
# Contract test for the repository's stable command-line interface.
set -euo pipefail

REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GITHUB_DISPATCHER="$REPOSITORY_ROOT/scripts/gh-app.sh"
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
    *"./skills/"*|*"gh-app-"*".sh"*)
      fail "help exposed an internal implementation path: $help_output"
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

assert_executable "$GITHUB_DISPATCHER"
assert_executable "$CI_CHECKER"
assert_absent "$REPOSITORY_ROOT/scripts/check-ci-runs.sh"
assert_readable "$REPOSITORY_ROOT/./skills/github-app/scripts/gh-app-token.sh"

for tracked_path in \
  ./skills/implementation-plan/SKILL.md \
  ./skills/implement/SKILL.md ; do
  assert_tracked "$tracked_path"
done

assert_contains .claude/agents/planner.md 'Read and follow the /implementation-plan skill.'
assert_contains .codex/agents/planner.toml 'Read and follow the /implementation-plan skill.'
assert_contains .claude/agents/implementer.md 'Read and follow the Phase 2 - Plan execution section of the /implement skill.'
assert_contains .codex/agents/implementer.toml 'Read and follow the Phase 2 - Plan execution section of the /implement skill.'
assert_contains ./skills/implement/SKILL.md 'fork_turns="none"'
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
for adapter in \
  .claude/agents/planner.md \
  .claude/agents/implementer.md \
  .codex/agents/planner.toml \
  .codex/agents/implementer.toml; do
  assert_contains "$adapter" 'delegated by /implement'
  if rg -q '\./skills/(implementation-plan|implement)/SKILL\.md' "$REPOSITORY_ROOT/$adapter"; then
    fail "adapter contains a repository-local skill path: $adapter"
  fi
done
if rg -q '\bmain\b' "$REPOSITORY_ROOT/./skills/pull-request/SKILL.md"; then
  fail 'pull-request instructions assume main instead of the discovered default branch'
fi
if rg -q 'docs/change/' "$REPOSITORY_ROOT/./skills/github-app"; then
  fail 'GitHub App instructions reference absent change history files'
fi
if rg -q '\./skills/|docs/change/' "$REPOSITORY_ROOT/.agents/skills/github-app/scripts"; then
  fail 'GitHub App bundled scripts contain a repository-local documentation reference'
fi
for script in \
  gh-app-issue-update.sh \
  gh-app-pr-update.sh \
  gh-app-issue-comment.sh \
  gh-app-issue-create.sh \
  gh-app-issue-get.sh \
  gh-app-issue-sub-add.sh \
  gh-app-issue-block-add.sh \
  gh-app-issue-block-remove.sh \
  gh-app-issue-block-list.sh \
  gh-app-pr-create.sh; do
  assert_contains "./skills/github-app/scripts/$script" \
    'Requires a GitHub App set up per the Setup reference in the /github-app skill'
done

# The repository owns the expected inventory; the generic checker validates
# declarations but cannot know whether a copied section was omitted.
assert_contains ./skills/breakdown/SKILL.md 'inlined-from:'
assert_contains ./skills/breakdown/SKILL.md '### 4. Quiz the user'
assert_contains ./skills/implementation-plan/SKILL.md 'inlined-from:'
assert_contains ./skills/implementation-plan/SKILL.md '### 2. Identify the spec source'
for skill in implement github-tickets pull-request github-app github-actions-ci; do
  if rg -q 'inlined-from:' "$REPOSITORY_ROOT/./skills/$skill/SKILL.md"; then
    fail "unexpected inline provenance inventory for $skill"
  fi
done

"$INLINE_CHECKER"

assert_help "$GITHUB_DISPATCHER"
assert_help "$CI_CHECKER"
for command_name in \
  push \
  pr-create \
  pr-update \
  issue-get \
  issue-create \
  issue-update \
  issue-comment \
  issue-sub-add \
  issue-block-add \
  issue-block-remove \
  issue-block-list \
  actions-run-view \
  actions-job-log \
  actions-rerun-failed; do
  assert_help "$GITHUB_DISPATCHER" "$command_name"
done

unknown_output=$(mktemp "$TEMP_ROOT/skills-sdlc-interface.XXXXXX")
trap 'rm -f "$unknown_output"' EXIT
if (cd "$TEMP_ROOT" && "$GITHUB_DISPATCHER" unknown-command >"$unknown_output" 2>&1); then
  fail 'unknown dispatcher command succeeded'
fi
rg -q '^usage:' "$unknown_output" || fail 'unknown dispatcher command did not print usage'
if rg -q '\./skills/|gh-app-[a-z-]+\.sh' "$unknown_output"; then
  fail 'unknown dispatcher command exposed an internal implementation path'
fi

if rg -n '\./scripts/github/|gh-app-[a-z-]+\.sh' \
  "$REPOSITORY_ROOT/./skills" \
  --glob 'SKILL.md'; then
  fail 'workflow skills bypass the public scripts interface'
fi
if rg -n '\./scripts/check-ci-runs\.sh' \
  "$REPOSITORY_ROOT/./skills" \
  --glob 'SKILL.md'; then
  fail 'workflow skills expect a repository-local CI checker'
fi

echo 'repository interface contract passed'
