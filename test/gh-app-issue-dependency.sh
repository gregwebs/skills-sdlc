#!/usr/bin/env bash
# Functional test for the non-native operation scripts
# gh-app-issue-dependency.sh and gh-app-issue-sub-issue.sh. gh is a PATH stub
# answering `gh api` from fixtures; a seeded token cache stands in for the mint.
set -euo pipefail

REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPENDENCY="$REPOSITORY_ROOT/skills/github-app/scripts/gh-app-issue-dependency.sh"
SUB_ISSUE="$REPOSITORY_ROOT/skills/github-app/scripts/gh-app-issue-sub-issue.sh"

fail() {
  echo "gh-app-issue-dependency test: $*" >&2
  exit 1
}

if [ -d /private/tmp ]; then
  TEMP_ROOT=/private/tmp
else
  TEMP_ROOT=/tmp
fi
WORK=$(mktemp -d "$TEMP_ROOT/skills-sdlc-gh-app-dependency.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/bin"
cat >"$WORK/bin/gh" <<'EOF'
#!/usr/bin/env bash
# Test double for gh: records each call's arguments (one per line, then an end
# marker) and its GH_TOKEN, and answers `gh api` from fixture JSON, applying
# --jq with jq as gh would.
printf '%s\n' "$@" '--end--' >>"$GH_LOG"
printf '%s\n' "${GH_TOKEN:-}" >>"$GH_TOKEN_LOG"
[ "${1:-}" = api ] || exit 0
shift
method=GET endpoint="" filter=.
while [ $# -gt 0 ]; do
  case "$1" in
    -X) method="$2"; shift 2 ;;
    -F) shift 2 ;;
    --jq) filter="$2"; shift 2 ;;
    *) endpoint="$1"; shift ;;
  esac
done
if [ "$endpoint" = "${GH_FAIL_ENDPOINT:-}" ]; then
  echo 'gh: Not Found (HTTP 404)' >&2
  exit 1
fi
case "$method $endpoint" in
  "GET "*/dependencies/blocked_by) fixture=blocked_by.json ;;
  "GET "*/dependencies/blocking) fixture=blocking.json ;;
  "GET "*) fixture=issue.json ;;
  *) fixture=mutation.json ;;
esac
jq -r "$filter" "$GH_FIXTURES/$fixture"
EOF
chmod +x "$WORK/bin/gh"

FIXTURES="$WORK/fixtures"
mkdir -p "$FIXTURES"
printf '%s' '{"id":9040,"number":40}' >"$FIXTURES/issue.json"
printf '%s' '[{"number":40},{"number":41}]' >"$FIXTURES/blocked_by.json"
printf '%s' '[{"number":50}]' >"$FIXTURES/blocking.json"
printf '%s' '{"html_url":"https://github.com/example/repo/issues/40"}' >"$FIXTURES/mutation.json"

# Seed a fresh token cache so no mint (and no private key) is needed.
mkdir -p "$WORK/secrets" "$WORK/cache/gh-app"
printf '123' >"$WORK/secrets/installation-id"
printf '%s\tdep-token\n' "$(($(date +%s) + 3600))" >"$WORK/cache/gh-app/token.123"

export PATH="$WORK/bin:$PATH" GH_FIXTURES="$FIXTURES"
export HOME="$WORK/home" XDG_CACHE_HOME="$WORK/cache" GITHUB_APP_SECRETS_DIR="$WORK/secrets"
export GH_LOG="$WORK/gh.log" GH_TOKEN_LOG="$WORK/gh-token.log" GH_FAIL_ENDPOINT=""
unset GH_TOKEN GITHUB_TOKEN
ISSUES='repos/{owner}/{repo}/issues'
NUMBERS='map("#\(.number)") | if length > 0 then join(", ") else "none" end'

run() {
  : >"$GH_LOG"
  : >"$GH_TOKEN_LOG"
  last_status=0
  (cd "$WORK" && "$@") >"$WORK/out" 2>"$WORK/err" || last_status=$?
}

expect_status() {
  [ "$last_status" = "$1" ] || fail "expected exit $1, got $last_status: $(cat "$WORK/err")"
}

# Pass each recorded call's arguments as separate words, calls separated by
# --end--, so a merged argument cannot pass.
expect_calls() {
  local expected
  expected=$(printf '%s\n' "$@" '--end--')
  [ "$(cat "$GH_LOG")" = "$expected" ] \
    || fail "unexpected gh calls:"$'\n'"$(cat "$GH_LOG")"$'\n'"expected:"$'\n'"$expected"
  if grep -vqx dep-token "$GH_TOKEN_LOG"; then
    fail "gh ran without the App token"
  fi
}

expect_no_calls() {
  [ ! -s "$GH_LOG" ] || fail "gh ran: $(cat "$GH_LOG")"
}

expect_usage_error() {
  run "$@"
  expect_status 2
  expect_no_calls
  grep -q '^usage:' "$WORK/err" || fail "usage error lacked usage: $*"
}

# add: the blocker's id goes in the payload; the blocked issue is in the path.
run "$DEPENDENCY" add --blocked 42 --blocker 40
expect_status 0
expect_calls \
  api "$ISSUES/40" --jq .id --end-- \
  api -X POST "$ISSUES/42/dependencies/blocked_by" -F issue_id=9040 --jq .html_url
[ "$(cat "$WORK/out")" = https://github.com/example/repo/issues/40 ] || fail "add did not print the URL"

run "$DEPENDENCY" add --blocker 40 --blocked 42 --repo example/other
expect_status 0
expect_calls \
  api repos/example/other/issues/40 --jq .id --end-- \
  api -X POST repos/example/other/issues/42/dependencies/blocked_by -F issue_id=9040 --jq .html_url

run "$DEPENDENCY" remove --blocked 42 --blocker 40
expect_status 0
expect_calls \
  api "$ISSUES/40" --jq .id --end-- \
  api -X DELETE "$ISSUES/42/dependencies/blocked_by/9040" --jq .html_url

run "$DEPENDENCY" list --issue 42
expect_status 0
expect_calls \
  api "$ISSUES/42/dependencies/blocked_by" --jq "$NUMBERS" --end-- \
  api "$ISSUES/42/dependencies/blocking" --jq "$NUMBERS"
[ "$(cat "$WORK/out")" = $'blocked by: #40, #41\nblocking: #50' ] || fail "unexpected list output: $(cat "$WORK/out")"
printf '%s' '[]' >"$FIXTURES/blocking.json"
run "$DEPENDENCY" list --issue 42
[ "$(cat "$WORK/out")" = $'blocked by: #40, #41\nblocking: none' ] || fail "unexpected empty list output: $(cat "$WORK/out")"
printf '%s' '[{"number":50}]' >"$FIXTURES/blocking.json"

# Id resolution failure is fatal: no mutation is attempted.
for verb in add remove; do
  GH_FAIL_ENDPOINT="$ISSUES/40" run "$DEPENDENCY" "$verb" --blocked 42 --blocker 40
  [ "$last_status" != 0 ] || fail "$verb succeeded without a blocker id"
  expect_calls api "$ISSUES/40" --jq .id
done
printf '%s' '{"id":null}' >"$FIXTURES/issue.json"
run "$DEPENDENCY" add --blocked 42 --blocker 40
[ "$last_status" != 0 ] || fail "add succeeded with a null blocker id"
expect_calls api "$ISSUES/40" --jq .id
grep -Fq 'could not resolve database id for issue 40' "$WORK/err" || fail "null id lacked diagnostic"
printf '%s' '{"id":9040,"number":40}' >"$FIXTURES/issue.json"

# A failing list is fatal, not an empty answer: neither direction may be
# swallowed.
GH_FAIL_ENDPOINT="$ISSUES/42/dependencies/blocked_by" run "$DEPENDENCY" list --issue 42
[ "$last_status" != 0 ] || fail "list succeeded after a failing blocked_by call: $(cat "$WORK/out")"
GH_FAIL_ENDPOINT="$ISSUES/42/dependencies/blocking" run "$DEPENDENCY" list --issue 42
[ "$last_status" != 0 ] || fail "list succeeded after a failing blocking call: $(cat "$WORK/out")"

# A failed mint never reaches gh, which would otherwise act as the user's login.
XDG_CACHE_HOME="$WORK/no-cache" GITHUB_APP_SECRETS_DIR="$WORK/absent" \
  run "$DEPENDENCY" list --issue 42
[ "$last_status" != 0 ] || fail "dependency succeeded without a token"
expect_no_calls
XDG_CACHE_HOME="$WORK/no-cache" GITHUB_APP_SECRETS_DIR="$WORK/absent" \
  run "$SUB_ISSUE" add --parent 10 --child 40
[ "$last_status" != 0 ] || fail "sub-issue succeeded without a token"
expect_no_calls

# A failing mutation propagates gh's failure.
GH_FAIL_ENDPOINT="$ISSUES/42/dependencies/blocked_by" run "$DEPENDENCY" add --blocked 42 --blocker 40
[ "$last_status" != 0 ] || fail "failed mutation exited 0"

# Invalid input never reaches gh.
expect_usage_error "$DEPENDENCY" add --blocked 42 --blocker 42
grep -Fq 'cannot block itself' "$WORK/err" || fail "self-reference lacked diagnostic"
expect_usage_error "$DEPENDENCY" remove --blocked 42 --blocker 42
expect_usage_error "$DEPENDENCY" add --blocked 42
expect_usage_error "$DEPENDENCY" add --blocked 4x --blocker 40
expect_usage_error "$DEPENDENCY" add --blocked 42 --blocker 40 --issue 42
# 0 and a leading zero are not issue numbers: they are typos that would resolve
# to a different issue, or none at all, if they were passed through.
for number in 0 042; do
  expect_usage_error "$DEPENDENCY" add --blocked "$number" --blocker 40
  expect_usage_error "$DEPENDENCY" add --blocked 42 --blocker "$number"
  expect_usage_error "$DEPENDENCY" list --issue "$number"
  expect_usage_error "$SUB_ISSUE" add --parent "$number" --child 40
  expect_usage_error "$SUB_ISSUE" add --parent 10 --child "$number"
done
expect_usage_error "$DEPENDENCY" add --blocked 42 --blocker
expect_usage_error "$DEPENDENCY" add --blocked 42 --blocker 40 --repo 'a/b/c'
# `.` and `..` are rejected in either component, not just in the whole slug.
for slug in '../..' '../x' './x' 'a/..' 'x/..' 'x/.'; do
  expect_usage_error "$DEPENDENCY" add --blocked 42 --blocker 40 --repo "$slug"
done
expect_usage_error "$DEPENDENCY" list
expect_usage_error "$DEPENDENCY" list --issue 42 --blocked 41
expect_usage_error "$DEPENDENCY" link --blocked 42 --blocker 40
expect_usage_error "$DEPENDENCY"

# --help needs no credentials.
GITHUB_APP_SECRETS_DIR="$WORK/absent" run "$DEPENDENCY" --help
expect_status 0
expect_no_calls
grep -q '^usage: gh-app-issue-dependency.sh add' "$WORK/out" || fail "--help lacked usage"

# Sub-issues: the child's id goes in the payload; the parent is in the path.
run "$SUB_ISSUE" add --parent 10 --child 40
expect_status 0
expect_calls \
  api "$ISSUES/40" --jq .id --end-- \
  api -X POST "$ISSUES/10/sub_issues" -F sub_issue_id=9040 --jq .html_url
[ "$(cat "$WORK/out")" = https://github.com/example/repo/issues/40 ] || fail "sub-issue add did not print the URL"

run "$SUB_ISSUE" add --parent 10 --child 40 --repo example/other
expect_status 0
expect_calls \
  api repos/example/other/issues/40 --jq .id --end-- \
  api -X POST repos/example/other/issues/10/sub_issues -F sub_issue_id=9040 --jq .html_url

GH_FAIL_ENDPOINT="$ISSUES/40" run "$SUB_ISSUE" add --parent 10 --child 40
[ "$last_status" != 0 ] || fail "sub-issue add succeeded without a child id"
expect_calls api "$ISSUES/40" --jq .id

printf '%s' '{"id":null}' >"$FIXTURES/issue.json"
run "$SUB_ISSUE" add --parent 10 --child 40
[ "$last_status" != 0 ] || fail "sub-issue add succeeded with a null child id"
expect_calls api "$ISSUES/40" --jq .id
grep -Fq 'could not resolve database id for issue 40' "$WORK/err" || fail "null id lacked diagnostic"
printf '%s' '{"id":9040,"number":40}' >"$FIXTURES/issue.json"

expect_usage_error "$SUB_ISSUE" add --parent 10 --child 10
expect_usage_error "$SUB_ISSUE" add --parent 10
expect_usage_error "$SUB_ISSUE" add --parent 10 --child 40 --repo 'a/b/c'
for slug in '../..' '../x' './x' 'a/..' 'x/..' 'x/.'; do
  expect_usage_error "$SUB_ISSUE" add --parent 10 --child 40 --repo "$slug"
done
expect_usage_error "$SUB_ISSUE" remove --parent 10 --child 40
GITHUB_APP_SECRETS_DIR="$WORK/absent" run "$SUB_ISSUE" --help
expect_status 0
expect_no_calls

echo 'gh-app-issue-dependency test passed'
