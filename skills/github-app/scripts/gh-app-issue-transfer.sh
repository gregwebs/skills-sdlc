#!/usr/bin/env bash
# Transfer an issue, authenticated as a GitHub App installation.
# Requires a GitHub App set up per the Setup reference in the /github-app skill.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

usage() {
  echo "usage: $0 --issue NUMBER --to-repo OWNER/REPO [--repo OWNER/REPO]"
}

fail() {
  echo "issue-transfer: $*" >&2
  exit 1
}

repo="" destination="" issue=""
while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --repo|--to-repo|--issue)
      [ $# -ge 2 ] && [ -n "$2" ] && [[ "$2" != --* ]] \
        || fail "missing value for $1"
      case "$1" in
        --repo) repo="$2" ;;
        --to-repo) destination="$2" ;;
        --issue) issue="$2" ;;
      esac
      shift 2
      ;;
    *) fail "unknown argument: $1" ;;
  esac
done

[[ "$issue" =~ ^[1-9][0-9]*$ ]] || fail "--issue must be a positive integer"
[ -n "$destination" ] || fail "--to-repo required"
[ -n "$repo" ] || repo=$(gh_app_default_repo) || fail "--repo required (not in a github.com git repo)"
repo_pattern='^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9_.-]+$'
for name in "$repo" "$destination"; do
  [[ "$name" =~ $repo_pattern ]] && [ "${name#*/}" != . ] && [ "${name#*/}" != .. ] \
    || fail "invalid OWNER/REPO: $name"
done
source_lower=$(printf '%s' "$repo" | tr '[:upper:]' '[:lower:]')
target_lower=$(printf '%s' "$destination" | tr '[:upper:]' '[:lower:]')
[ "$source_lower" != "$target_lower" ] || fail "source and destination repositories must differ"

source_json=$(gh_app_api_get "repos/${repo}/issues/${issue}")
issue_id=$(printf '%s' "$source_json" | jq -ers '
  if length == 1 and (.[0] | type == "object") then .[0] else error("invalid issue response") end
  | if has("pull_request") then error("cannot transfer a pull request") else . end
  | .node_id | select(type == "string" and length > 0)') \
  || fail "invalid source issue response (pull requests cannot be transferred)"

destination_json=$(gh_app_api_get "repos/${destination}")
repository_id=$(printf '%s' "$destination_json" | jq -ers --arg owner "${source_lower%%/*}" --arg target "$target_lower" '
  if length == 1 and (.[0] | type == "object") then .[0] else error("invalid repository response") end
  | select((.full_name | ascii_downcase) == $target)
  | select(.has_issues == true)
  | select((.owner.login | ascii_downcase) == $owner)
  | .node_id | select(type == "string" and length > 0)') \
  || fail "destination must match the requested repo, have issues enabled, a node_id, and the same owner as the source"
canonical_destination=$(printf '%s' "$destination_json" | jq -r '.full_name')
# Also check the requested owner: a redirected REST lookup must not bypass the restriction.
[ "${source_lower%%/*}" = "${target_lower%%/*}" ] || fail "repositories must have the same owner"

query='mutation($issueId: ID!, $repositoryId: ID!) { transferIssue(input: {issueId: $issueId, repositoryId: $repositoryId}) { issue { id number url repository { nameWithOwner } } } }'
variables=$(jq -n --arg issueId "$issue_id" --arg repositoryId "$repository_id" \
  '{issueId: $issueId, repositoryId: $repositoryId}')
response=$(gh_app_api_graphql "$query" "$variables") || {
  status=$?
  echo "issue-transfer: mutation failed; outcome may be unknown. Reconcile the issue location read-only before retrying." >&2
  exit "$status"
}
url=$(printf '%s' "$response" | jq -er --arg destination "$canonical_destination" '
  ($destination | ascii_downcase) as $repo
  | .data.transferIssue.issue
  | select(.id | type == "string" and length > 0)
  | select((.repository.nameWithOwner | ascii_downcase) == $repo)
  | select(.number | type == "number" and . > 0 and floor == .)
  | select((.url | type) == "string")
  | select((.url | ascii_downcase) == ("https://github.com/" + $repo + "/issues/" + (.number | tostring)))
  | .url') \
  || fail "invalid transfer response; outcome may be unknown. Reconcile the issue location read-only before retrying."
printf '%s\n' "$url"
