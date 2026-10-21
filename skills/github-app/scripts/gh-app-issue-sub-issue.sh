#!/usr/bin/env bash
# Link an existing issue as a sub-issue of a parent as the GitHub App
# installation. gh has no command for this endpoint, and it takes the child's
# database id rather than its number, so this resolves the id first.
#
# Requires a GitHub App set up per the Setup reference in the /github-app skill.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/gh-app-token.sh"

usage() {
  echo "usage: gh-app-issue-sub-issue.sh add --parent NUMBER --child NUMBER [--repo OWNER/REPO]"
}

usage_error() {
  echo "gh-app-issue-sub-issue.sh: $*" >&2
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

case "${1:-}" in
  --help|-h) usage; exit 0 ;;
  add) shift ;;
  *) usage_error "expected add" ;;
esac

repo="" parent="" child=""
while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --repo) repo="${2:-}"; shift 2 || usage_error "--repo requires a value" ;;
    --parent) parent="${2:-}"; shift 2 || usage_error "--parent requires a value" ;;
    --child) child="${2:-}"; shift 2 || usage_error "--child requires a value" ;;
    *) usage_error "unknown argument: $1" ;;
  esac
done

if [ -n "$repo" ] && ! is_repo_slug "$repo"; then
  usage_error "--repo must be OWNER/REPO"
fi
is_issue_number "$parent" || usage_error "--parent must be an issue number"
is_issue_number "$child" || usage_error "--child must be an issue number"
[ "$parent" != "$child" ] || usage_error "an issue cannot be its own sub-issue"

GH_TOKEN=$(gh_app_token) || exit 1
export GH_TOKEN

# Without --repo, gh fills {owner}/{repo} with the repository it resolves
# itself, which need not be the remote `git push` uses (see the /github-app
# skill on multiple remotes).
[ -n "$repo" ] || repo='{owner}/{repo}'
issues="repos/${repo}/issues"

child_id=$(gh api "${issues}/${child}" --jq .id)
if ! [[ "$child_id" =~ ^[0-9]+$ ]]; then
  echo "gh-app-issue-sub-issue.sh: could not resolve database id for issue ${child}" >&2
  exit 1
fi
gh api -X POST "${issues}/${parent}/sub_issues" -F sub_issue_id="$child_id" --jq .html_url
