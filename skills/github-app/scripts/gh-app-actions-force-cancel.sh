#!/usr/bin/env bash
# Force cancel a GitHub Actions workflow run.
#
# Usage: ./scripts/gh-app.sh actions-force-cancel RUN_ID
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

usage() {
  echo "usage: $0 RUN_ID" >&2
}

if [ "$#" -eq 1 ] && { [ "$1" = "--help" ] || [ "$1" = "-h" ]; }; then
  usage
  exit 0
fi

if [ "$#" -ne 1 ] || ! [[ "$1" =~ ^[0-9]+$ ]]; then
  usage
  exit 2
fi

repo=$(gh_app_default_repo)
run_id="$1"
gh_app_api_post "repos/${repo}/actions/runs/${run_id}/force-cancel" '{}' >/dev/null
echo "Requested force-cancellation of workflow run ${run_id}." >&2
