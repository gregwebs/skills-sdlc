#!/usr/bin/env bash
# Add, remove or list issue dependencies (blocked by / blocking) as the GitHub
# App installation. gh has no command for these endpoints, and they take an
# issue's database id rather than its number, so this resolves the id first.
#
# Requires a GitHub App set up per the Setup reference in the /github-app skill.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/gh-app-token.sh"

usage() {
  cat <<'USAGE'
usage: gh-app-issue-dependency.sh add --blocked NUMBER --blocker NUMBER [--repo OWNER/REPO]
       gh-app-issue-dependency.sh remove --blocked NUMBER --blocker NUMBER [--repo OWNER/REPO]
       gh-app-issue-dependency.sh list --issue NUMBER [--repo OWNER/REPO]

--blocked 42 --blocker 40 records that issue 42 is blocked by issue 40.
USAGE
}

usage_error() {
  echo "gh-app-issue-dependency.sh: $*" >&2
  usage >&2
  exit 2
}

is_issue_number() {
  [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

# GitHub rejects `.` and `..` as path components; gh would send them unchanged.
is_repo_slug() {
  local owner="${1%%/*}" name="${1#*/}"
  [[ "$1" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] \
    && [ "$owner" != . ] && [ "$owner" != .. ] \
    && [ "$name" != . ] && [ "$name" != .. ]
}

verb="${1:-}"
case "$verb" in
  --help|-h) usage; exit 0 ;;
  add|remove|list) shift ;;
  *) usage_error "expected add, remove or list" ;;
esac

repo="" blocked="" blocker="" issue=""
while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --repo) repo="${2:-}"; shift 2 || usage_error "--repo requires a value" ;;
    --blocked) blocked="${2:-}"; shift 2 || usage_error "--blocked requires a value" ;;
    --blocker) blocker="${2:-}"; shift 2 || usage_error "--blocker requires a value" ;;
    --issue) issue="${2:-}"; shift 2 || usage_error "--issue requires a value" ;;
    *) usage_error "unknown argument: $1" ;;
  esac
done

if [ -n "$repo" ] && ! is_repo_slug "$repo"; then
  usage_error "--repo must be OWNER/REPO"
fi
case "$verb" in
  add|remove)
    [ -z "$issue" ] || usage_error "--issue is only for list"
    is_issue_number "$blocked" || usage_error "--blocked must be an issue number"
    is_issue_number "$blocker" || usage_error "--blocker must be an issue number"
    [ "$blocked" != "$blocker" ] || usage_error "an issue cannot block itself"
    ;;
  list)
    [ -z "$blocked$blocker" ] || usage_error "--blocked and --blocker are only for add and remove"
    is_issue_number "$issue" || usage_error "--issue must be an issue number"
    ;;
esac

GH_TOKEN=$(gh_app_token) || exit 1
export GH_TOKEN

# Without --repo, gh fills {owner}/{repo} with the repository it resolves
# itself, which need not be the remote `git push` uses (see the /github-app
# skill on multiple remotes).
[ -n "$repo" ] || repo='{owner}/{repo}'
issues="repos/${repo}/issues"

issue_database_id() {
  local number="$1" id
  id=$(gh api "${issues}/${number}" --jq .id) || return 1
  if ! [[ "$id" =~ ^[0-9]+$ ]]; then
    echo "gh-app-issue-dependency.sh: could not resolve database id for issue ${number}" >&2
    return 1
  fi
  printf '%s' "$id"
}

case "$verb" in
  add)
    blocker_id=$(issue_database_id "$blocker") || exit 1
    gh api -X POST "${issues}/${blocked}/dependencies/blocked_by" -F issue_id="$blocker_id" --jq .html_url
    ;;
  remove)
    blocker_id=$(issue_database_id "$blocker") || exit 1
    gh api -X DELETE "${issues}/${blocked}/dependencies/blocked_by/${blocker_id}" --jq .html_url
    ;;
  list)
    numbers='map("#\(.number)") | if length > 0 then join(", ") else "none" end'
    blocked_by=$(gh api "${issues}/${issue}/dependencies/blocked_by" --jq "$numbers")
    blocking=$(gh api "${issues}/${issue}/dependencies/blocking" --jq "$numbers")
    printf 'blocked by: %s\nblocking: %s\n' "$blocked_by" "$blocking"
    ;;
esac
