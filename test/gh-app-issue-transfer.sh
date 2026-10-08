#!/usr/bin/env bash
# Exercise the public dispatcher with fixture HTTP/token boundaries; no network.
set -euo pipefail

REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK=$(mktemp -d /private/tmp/skills-sdlc-issue-transfer.XXXXXX)
trap 'rm -rf "$WORK"' EXIT

fail() {
  echo "issue-transfer test: $*" >&2
  exit 1
}

# Keep the real dispatcher, library and command together, replacing only auth/HTTP.
mkdir -p "$WORK/repo/scripts" "$WORK/repo/skills/github-app/scripts" "$WORK/repo/.agents"
cp "$REPOSITORY_ROOT/scripts/gh-app.sh" "$WORK/repo/scripts/"
for script in gh-app.sh gh-app-issue-transfer.sh lib.sh; do
  cp "$REPOSITORY_ROOT/skills/github-app/scripts/$script" "$WORK/repo/skills/github-app/scripts/"
done
ln -s ../skills "$WORK/repo/.agents/skills"
git -C "$WORK/repo" init -q
git -C "$WORK/repo" remote add origin https://github.com/example/source.git
cat >"$WORK/repo/skills/github-app/scripts/gh-app-token.sh" <<'EOF'
gh_app_token() {
  printf 'token\n' >>"$AUTH_LOG"
  [ "$TOKEN_STATUS" = 0 ] || return "$TOKEN_STATUS"
  printf 'fixture-token'
}
gh_app_curl() {
  local method="" url="" payload=""
  while [ $# -gt 0 ]; do
    case "$1" in
      -X) method="$2"; shift 2 ;;
      -d) payload="$2"; shift 2 ;;
      -H|-w) shift 2 ;;
      https://*) url="$1"; shift ;;
      *) shift ;;
    esac
  done
  printf '%s %s\n' "$method" "$url" >>"$HTTP_LOG"
  case "$method $url" in
    'GET https://api.github.com/repos/example/source/issues/11')
      cat "$ISSUE_FIXTURE"; printf '\n%s' "$ISSUE_STATUS"
      if [ "$ISSUE_TRANSPORT_STATUS" != 0 ]; then
        echo 'fixture source transport failure' >&2
        return "$ISSUE_TRANSPORT_STATUS"
      fi ;;
    'GET https://api.github.com/repos/example/target'|'GET https://api.github.com/repos/other/target')
      cat "$REPO_FIXTURE"; printf '\n%s' "$REPO_STATUS"
      if [ "$REPO_TRANSPORT_STATUS" != 0 ]; then
        echo 'fixture destination transport failure' >&2
        return "$REPO_TRANSPORT_STATUS"
      fi ;;
    'POST https://api.github.com/graphql')
      printf '%s' "$payload" >"$PAYLOAD_FILE"
      [ "$TRANSPORT_STATUS" = 0 ] || return "$TRANSPORT_STATUS"
      cat "$GRAPHQL_FIXTURE"; printf '\n%s' "$GRAPHQL_STATUS" ;;
    *) echo "unexpected request: $method $url" >&2; return 91 ;;
  esac
}
EOF
export AUTH_LOG="$WORK/auth" HTTP_LOG="$WORK/http" PAYLOAD_FILE="$WORK/payload"
export ISSUE_FIXTURE="$WORK/issue.json" REPO_FIXTURE="$WORK/repo.json" GRAPHQL_FIXTURE="$WORK/graphql.json"
export TOKEN_STATUS=0 TRANSPORT_STATUS=0 ISSUE_STATUS=200 REPO_STATUS=200 GRAPHQL_STATUS=200
export ISSUE_TRANSPORT_STATUS=0 REPO_TRANSPORT_STATUS=0

reset_fixtures() {
  printf '%s' '{"node_id":"ISSUE_source"}' >"$ISSUE_FIXTURE"
  printf '%s' '{"node_id":"REPO_target","full_name":"Example/Target","has_issues":true,"owner":{"login":"Example"}}' >"$REPO_FIXTURE"
  # Transfer may change node identity; a different returned ID must succeed.
  printf '%s' '{"data":{"transferIssue":{"issue":{"id":"ISSUE_target","number":23,"url":"https://github.com/Example/Target/issues/23","repository":{"nameWithOwner":"Example/Target"}}}}}' >"$GRAPHQL_FIXTURE"
  TOKEN_STATUS=0 TRANSPORT_STATUS=0 ISSUE_STATUS=200 REPO_STATUS=200 GRAPHQL_STATUS=200
  ISSUE_TRANSPORT_STATUS=0 REPO_TRANSPORT_STATUS=0
}

run_case() {
  local expected="$1" requests="$2"
  shift 2
  : >"$AUTH_LOG"
  : >"$HTTP_LOG"
  : >"$PAYLOAD_FILE"
  last_status=0
  (cd "$WORK/repo" && ./scripts/gh-app.sh issue-transfer "$@") >"$WORK/out" 2>"$WORK/err" || last_status=$?
  [ "$last_status" = "$expected" ] || fail "expected exit $expected, got $last_status: $(cat "$WORK/err")"
  [ "$(wc -l <"$HTTP_LOG" | tr -d ' ')" = "$requests" ] || fail "unexpected requests: $(cat "$HTTP_LOG")"
  if [ "$expected" != 0 ]; then
    [ ! -s "$WORK/out" ] || fail "failure printed a success URL: $(cat "$WORK/out")"
    if [ "$requests" = 3 ]; then
      grep -Fq 'outcome may be unknown' "$WORK/err" || fail "mutation failure lacked uncertainty warning"
      grep -Fq 'read-only before retrying' "$WORK/err" || fail "mutation failure lacked reconciliation guidance"
    fi
    [ -s "$WORK/err" ] || [ "$expected" = 7 ] || [ "$expected" = 8 ] || fail "failure lacked diagnostic"
  fi
  if grep -Fq 'fixture-token' "$WORK/out" "$WORK/err"; then
    fail "token leaked to command output"
  fi
  if [ "$requests" = 0 ] && [ "$TOKEN_STATUS" = 0 ]; then
    [ ! -s "$AUTH_LOG" ] || fail "validation attempted authentication"
  fi
}

transfer() {
  run_case "$1" "$2" --issue 11 --to-repo example/target --repo example/source
}

reset_fixtures
transfer 0 3
[ "$(cat "$WORK/out")" = https://github.com/Example/Target/issues/23 ] || fail "wrong success URL"
jq -e '.variables == {issueId:"ISSUE_source",repositoryId:"REPO_target"}
  and (.query | contains("transferIssue(input:"))
  and (.query | contains("repository { nameWithOwner }"))' "$PAYLOAD_FILE" >/dev/null || fail "wrong mutation payload"
# Default source from origin, without authentication or writes to a real repository.
run_case 0 3 --issue 11 --to-repo example/target

run_case 1 0
run_case 1 0 --issue 11
run_case 1 0 --issue 11 --to-repo
run_case 1 0 --issue 11 --to-repo example/target --repo
run_case 1 0 --issue --to-repo example/target
run_case 1 0 --issue 11 --to-repo ''
run_case 1 0 --unknown
for number in 0 -1 1.5 abc 01; do
  run_case 1 0 --issue "$number" --to-repo example/target
done
for name in example example/target/extra /target example/ 'example/t arget' example/. example/..; do
  run_case 1 0 --issue 11 --to-repo "$name"
  run_case 1 0 --issue 11 --to-repo example/target --repo "$name"
done
run_case 1 0 --issue 11 --to-repo EXAMPLE/SOURCE
# An invalid inferred remote cannot become an API path.
git -C "$WORK/repo" remote set-url origin https://not-github.invalid/example/source.git
run_case 1 0 --issue 11 --to-repo example/target
git -C "$WORK/repo" remote set-url origin https://github.com/example/source.git

printf '%s' '{"node_id":"PR_id","pull_request":{}}' >"$ISSUE_FIXTURE"
transfer 1 1
for body in '{}' '{"node_id":null}' '{"node_id":12}' '{"node_id":""}' 'not-json'; do
  printf '%s' "$body" >"$ISSUE_FIXTURE"
  transfer 1 1
done
reset_fixtures
printf '%s' '{"node_id":"REPO_target","full_name":"Example/Target","has_issues":true,"owner":{"login":"other"}}' >"$REPO_FIXTURE"
run_case 1 2 --issue 11 --to-repo other/target --repo example/source
# Even a redirect returning the source owner must not allow a different requested owner.
reset_fixtures
run_case 1 2 --issue 11 --to-repo other/target --repo example/source
for body in '{"node_id":"R","full_name":"example/wrong","has_issues":true,"owner":{"login":"example"}}' '{}' '{"node_id":"R","full_name":"example/target","has_issues":false,"owner":{"login":"example"}}' '{"node_id":null,"full_name":"example/target","has_issues":true,"owner":{"login":"example"}}' 'not-json'; do
  printf '%s' "$body" >"$REPO_FIXTURE"
  transfer 1 2
done
# Valid bodies must never override a failed preflight transport or authentication.
reset_fixtures
ISSUE_TRANSPORT_STATUS=18
transfer 18 1
reset_fixtures
REPO_TRANSPORT_STATUS=18
transfer 18 2
reset_fixtures
TOKEN_STATUS=8
transfer 8 0
for status in 404 302 000 invalid; do
  reset_fixtures
  ISSUE_STATUS="$status"
  transfer 1 1
  reset_fixtures
  REPO_STATUS="$status"
  transfer 1 2
done
reset_fixtures
REPO_STATUS=403
transfer 1 2
reset_fixtures
for status in 403 500 302; do
  GRAPHQL_STATUS="$status"
  transfer 1 3
done
reset_fixtures
printf '%s' '{"errors":[{"message":"Resource not accessible by integration"}]}' >"$GRAPHQL_FIXTURE"
transfer 1 3
# Partial data plus errors must fail too, even if the issue looks valid.
reset_fixtures
jq '. + {errors:[{message:"denied"}]}' "$GRAPHQL_FIXTURE" >"$WORK/partial"
cp "$WORK/partial" "$GRAPHQL_FIXTURE"
transfer 1 3
for body in 'not-json' '{}' 'null' '[]' '{} {}' '{"data":{"transferIssue":null}}' '{"data":{"transferIssue":{"issue":null}}}'; do
  printf '%s' "$body" >"$GRAPHQL_FIXTURE"
  transfer 1 3
done
for filter in '.id = ""' '.id = null' '.number = 0' '.number = 1.5' '.number = "23"' '.repository.nameWithOwner = "other/target"' '.url = ""' '.url = "https://github.com/example/source/issues/23"' '.url = "https://github.com/example/target/issues/24"'; do
  reset_fixtures
  jq ".data.transferIssue.issue |= ($filter)" "$GRAPHQL_FIXTURE" >"$WORK/invalid"
  cp "$WORK/invalid" "$GRAPHQL_FIXTURE"
  transfer 1 3
done
reset_fixtures
TRANSPORT_STATUS=7
transfer 7 3
# Token failure at the GraphQL boundary is covered without triggering REST auth failure.
# Test the reusable helper directly because each REST lookup also mints a token.
TOKEN_STATUS=8
helper_status=0
bash -c 'source "$1"; gh_app_api_graphql "query { viewer { login } }" "{}"' \
  _ "$WORK/repo/skills/github-app/scripts/lib.sh" >"$WORK/out" 2>"$WORK/err" || helper_status=$?
[ "$helper_status" = 8 ] && [ ! -s "$WORK/out" ] || fail "GraphQL token failure was not propagated"

echo 'issue-transfer test passed'
