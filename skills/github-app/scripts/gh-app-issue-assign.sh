#!/usr/bin/env bash
# Assign or unassign users on an issue, authenticated as a GitHub App
# installation. (GitHub treats PRs as issues for this endpoint, so the same
# script works for both.)
#
# Usage: gh-app-issue-assign.sh --issue NUMBER \
#          (--assignee USER)... | --clear-assignees
#
# Passing --assignee replaces the issue's full assignee set with the provided
# users. Passing --clear-assignees removes all assignees. The two forms are
# mutually exclusive.
#
# Requires a GitHub App set up per the Setup reference in the /github-app skill
# with installation granted Issues:write on the repo.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

usage() {
  echo "usage: $0 --issue NUMBER [--repo OWNER/REPO] (--assignee USER)... [--clear-assignees]"
}

repo="" issue="" clear_assignees=false assignees=()
while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --repo) repo="$2"; shift 2 ;;
    --issue) issue="$2"; shift 2 ;;
    --assignee) assignees+=("$2"); shift 2 ;;
    --clear-assignees) clear_assignees=true; shift ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done

[ -n "$repo" ] || repo=$(gh_app_default_repo) || { echo "--repo required (not in a github.com git repo)" >&2; exit 1; }
if [ -z "$issue" ]; then
  usage >&2
  exit 1
fi
if [ "$clear_assignees" = true ] && [ "${#assignees[@]}" -gt 0 ]; then
  echo "--clear-assignees cannot be combined with --assignee" >&2
  exit 1
fi
if [ "${#assignees[@]}" -eq 0 ] && [ "$clear_assignees" = false ]; then
  echo "at least one --assignee or --clear-assignees is required" >&2
  exit 1
fi

assignees_json=$(printf '%s\n' "${assignees[@]:-}" | jq -R . | jq -s 'map(select(length > 0))')
payload=$(jq -n --argjson assignees "$assignees_json" '{assignees: $assignees}')

gh_app_api_patch "repos/${repo}/issues/${issue}" "$payload"
