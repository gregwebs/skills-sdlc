#!/usr/bin/env bash
# Functional test for skills/github-actions-ci/scripts/check-ci-runs.sh.
# Stubs the GitHub API with fixtures so no network access is required, and
# covers the "no GitHub Actions checks apply to this commit" classification:
# it must resolve to success (exit 0), never hang under --wait, and never be
# confused with a still-pending run.
set -euo pipefail

REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECKER="$REPOSITORY_ROOT/skills/github-actions-ci/scripts/check-ci-runs.sh"

fail() {
  echo "check-ci-runs test: $*" >&2
  exit 1
}

if [ -d /private/tmp ]; then
  TEMP_ROOT=/private/tmp
else
  TEMP_ROOT=/tmp
fi
WORK=$(mktemp -d "$TEMP_ROOT/skills-sdlc-check-ci.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

REPO_DIR="$WORK/repo"
mkdir -p "$REPO_DIR"
git -C "$REPO_DIR" init -q
git -C "$REPO_DIR" config user.email test@example.com
git -C "$REPO_DIR" config user.name test
git -C "$REPO_DIR" commit -q --allow-empty -m init
git -C "$REPO_DIR" remote add origin https://github.com/example/repo.git

FIXTURES="$WORK/fixtures"
mkdir -p "$FIXTURES"

write_fixture() {
  printf '%s' "$2" >"$FIXTURES/$1"
}

write_fixture check_runs_success.json \
  '{"check_runs":[
     {"name":"build","app":{"slug":"github-actions"},"status":"completed","conclusion":"success","html_url":"https://x/1","started_at":"2024-01-01T00:00:00Z"},
     {"name":"test","app":{"slug":"github-actions"},"status":"completed","conclusion":"success","html_url":"https://x/2","started_at":"2024-01-01T00:00:00Z"}
   ]}'
write_fixture check_runs_one_failed.json \
  '{"check_runs":[
     {"name":"build","app":{"slug":"github-actions"},"status":"completed","conclusion":"success","html_url":"https://x/1","started_at":"2024-01-01T00:00:00Z"},
     {"name":"test","app":{"slug":"github-actions"},"status":"completed","conclusion":"failure","html_url":"https://x/2","started_at":"2024-01-01T00:00:00Z"}
   ]}'
write_fixture check_runs_pending.json \
  '{"check_runs":[
     {"name":"build","app":{"slug":"github-actions"},"status":"in_progress","conclusion":null,"html_url":"https://x/1","started_at":"2024-01-01T00:00:00Z"}
   ]}'
write_fixture check_runs_job_missing.json \
  '{"check_runs":[
     {"name":"build","app":{"slug":"github-actions"},"status":"completed","conclusion":"success","html_url":"https://x/1","started_at":"2024-01-01T00:00:00Z"}
   ]}'
write_fixture check_runs_empty.json '{"check_runs":[]}'
write_fixture check_runs_other_apps.json \
  '{"check_runs":[
     {"name":"ci/circleci","app":{"slug":"circleci"},"status":"completed","conclusion":"success","html_url":"https://x/1","started_at":"2024-01-01T00:00:00Z"}
   ]}'
write_fixture check_runs_success_with_skip.json \
  '{"check_runs":[
     {"name":"build","app":{"slug":"github-actions"},"status":"completed","conclusion":"success","html_url":"https://x/1","started_at":"2024-01-01T00:00:00Z"},
     {"name":"gem","app":{"slug":"github-actions"},"status":"completed","conclusion":"skipped","html_url":"https://x/2","started_at":"2024-01-01T00:00:00Z"}
   ]}'
write_fixture check_runs_skip_pending.json \
  '{"check_runs":[
     {"name":"gem","app":{"slug":"github-actions"},"status":"completed","conclusion":"skipped","html_url":"https://x/1","started_at":"2024-01-01T00:00:00Z"},
     {"name":"test","app":{"slug":"github-actions"},"status":"in_progress","conclusion":null,"html_url":"https://x/2","started_at":"2024-01-01T00:00:00Z"}
   ]}'
write_fixture check_runs_fail_with_skip.json \
  '{"check_runs":[
     {"name":"gem","app":{"slug":"github-actions"},"status":"completed","conclusion":"skipped","html_url":"https://x/1","started_at":"2024-01-01T00:00:00Z"},
     {"name":"test","app":{"slug":"github-actions"},"status":"completed","conclusion":"failure","html_url":"https://x/2","started_at":"2024-01-01T00:00:00Z"}
   ]}'
write_fixture check_runs_success_with_neutral.json \
  '{"check_runs":[
     {"name":"build","app":{"slug":"github-actions"},"status":"completed","conclusion":"success","html_url":"https://x/1","started_at":"2024-01-01T00:00:00Z"},
     {"name":"lint","app":{"slug":"github-actions"},"status":"completed","conclusion":"neutral","html_url":"https://x/2","started_at":"2024-01-01T00:00:00Z"}
   ]}'
write_fixture actions_runs_zero.json '{"total_count":0}'
write_fixture actions_runs_nonzero.json '{"total_count":1}'
write_fixture workflows_zero_active.json '{"workflows":[]}'
write_fixture workflows_one_active.json '{"workflows":[{"state":"active"}]}'

STUB_CURL="$WORK/stub-curl.sh"
cat >"$STUB_CURL" <<'EOF'
#!/usr/bin/env bash
# Test double for curl: routes by URL (the last argument) to a fixture file
# named by an env var, mimicking `curl -f`'s empty-output/non-zero-exit on
# HTTP error when the fixture is the sentinel "FAIL".
url="${*: -1}"
case "$url" in
  *check-runs*) fixture="$STUB_CHECK_RUNS_FIXTURE" ;;
  *actions/runs*) fixture="$STUB_ACTIONS_RUNS_FIXTURE" ;;
  *actions/workflows*) fixture="$STUB_WORKFLOWS_FIXTURE" ;;
  *)
    echo "stub-curl: unexpected URL: $url" >&2
    exit 1
    ;;
esac
[ -n "$fixture" ] || { echo "stub-curl: no fixture configured for $url" >&2; exit 1; }
if [ "$fixture" = FAIL ]; then
  exit 22
fi
cat "$fixture"
EOF
chmod +x "$STUB_CURL"

OUT="$WORK/out"
ERR="$WORK/err"

run_case() {
  # run_case CHECK_RUNS_FIXTURE ACTIONS_RUNS_FIXTURE WORKFLOWS_FIXTURE GRACE -- ARGS...
  local check_runs="$1" actions_runs="$2" workflows="$3" grace="$4"
  shift 4
  [ "$1" = -- ] || fail "run_case: expected -- separator"
  shift
  set +e
  (
    cd "$REPO_DIR" &&
      CHECK_CI_CURL="$STUB_CURL" \
      STUB_CHECK_RUNS_FIXTURE="${check_runs:+$FIXTURES/$check_runs}" \
      STUB_ACTIONS_RUNS_FIXTURE="${actions_runs:+$FIXTURES/$actions_runs}" \
      STUB_WORKFLOWS_FIXTURE="${workflows:+$FIXTURES/$workflows}" \
      GITHUB_APP_SECRETS_DIR="$WORK/no-app-secrets" \
      CHECK_INTERVAL_SECONDS=0 \
      CI_ABSENT_GRACE_SECONDS="$grace" \
      timeout 10 "$CHECKER" "$@"
  ) >"$OUT" 2>"$ERR"
  last_status=$?
  set -e
}

assert_status() {
  [ "$last_status" = "$1" ] || fail "expected exit $1, got $last_status (stdout: $(cat "$OUT"), stderr: $(cat "$ERR"))"
}

assert_stdout_contains() {
  rg -Fq -- "$1" "$OUT" || fail "expected stdout to contain: $1 (got: $(cat "$OUT"))"
}

assert_stderr_contains() {
  rg -Fq -- "$1" "$ERR" || fail "expected stderr to contain: $1 (got: $(cat "$ERR"))"
}

# All selected checks succeed.
run_case check_runs_success.json '' '' 120 --
assert_status 0
assert_stdout_contains 'build: completed (success)'
assert_stdout_contains 'test: completed (success)'

# One selected check fails.
run_case check_runs_one_failed.json '' '' 120 --
assert_status 1

# A check is still running (one-shot mode).
run_case check_runs_pending.json '' '' 120 --
assert_status 2

# (a) A run that succeeds with a legitimately skipped job resolves to success:
# "skipped" must not be treated as failure. Also guards the coupled success
# predicate (all-jobs-success would otherwise reject the skipped job).
run_case check_runs_success_with_skip.json '' '' 120 --
assert_status 0
assert_stdout_contains 'build: completed (success)'
assert_stdout_contains 'gem: completed (skipped)'

# (b) A skipped job while another job is still pending must NOT trigger a
# premature failure: one-shot mode stays "pending" (exit 2). This is the
# reported bug (formerly exited 1 immediately).
run_case check_runs_skip_pending.json '' '' 120 --
assert_status 2

# (c) A genuine failure alongside a skipped job still fails (failure wins).
run_case check_runs_fail_with_skip.json '' '' 120 --
assert_status 1

# (d) "neutral" is a non-failing terminal conclusion too, same as "skipped".
run_case check_runs_success_with_neutral.json '' '' 120 --
assert_status 0
assert_stdout_contains 'build: completed (success)'
assert_stdout_contains 'lint: completed (neutral)'

# --job names a job that hasn't reported, but other GitHub Actions checks
# exist for this commit, so CI does apply here: stays "pending", not "absent".
run_case check_runs_job_missing.json '' '' 120 -- --job deploy
assert_status 2
assert_stderr_contains 'deploy: not found among 1 GitHub Actions checks'

# No check runs at all, and the repo has zero active workflows: this is a
# clean, unambiguous conclusion, so it succeeds even without --wait.
run_case check_runs_empty.json actions_runs_zero.json workflows_zero_active.json 120 --
assert_status 0
assert_stderr_contains 'no GitHub Actions workflows configured'

# Same, but with --wait: must resolve immediately, not loop forever.
run_case check_runs_empty.json actions_runs_zero.json workflows_zero_active.json 120 -- --wait
assert_status 0
assert_stderr_contains 'no GitHub Actions workflows configured'

# Workflows exist but none ran for this SHA, and the grace period has
# already elapsed (0s): conclude "no CI applies" as success.
run_case check_runs_empty.json actions_runs_zero.json workflows_one_active.json 0 --
assert_status 0
assert_stderr_contains 'no GitHub Actions checks apply to'

# Same, but the grace period has not elapsed yet: still undetermined/pending.
run_case check_runs_empty.json actions_runs_zero.json workflows_one_active.json 100 --
assert_status 2
assert_stderr_contains 'waiting up to 100s'

# A workflow run exists for this SHA; its check runs just haven't registered
# yet. This is ordinary pending, regardless of grace.
run_case check_runs_empty.json actions_runs_nonzero.json workflows_one_active.json 0 --
assert_status 2
assert_stderr_contains 'a workflow run is in progress'

# The actions/runs probe itself fails (rate limit, 403, ...): never guess
# "no CI" from a broken probe.
run_case check_runs_empty.json FAIL '' 0 --
assert_status 2
assert_stderr_contains 'CI checks: not found for'

# Only non-Actions check runs exist (e.g. another CI provider): still
# resolves to "no GitHub Actions CI", but names the other apps so the
# commit isn't mistaken for unchecked.
run_case check_runs_other_apps.json actions_runs_zero.json workflows_zero_active.json 120 --
assert_status 0
assert_stderr_contains 'no GitHub Actions workflows configured'
assert_stderr_contains '1 check runs from other apps: circleci'

echo 'check-ci-runs test passed'
