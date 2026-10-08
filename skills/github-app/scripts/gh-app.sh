#!/usr/bin/env bash
# Stable dispatcher for GitHub App-authenticated repository operations.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROGRAM_NAME="${GH_APP_PROGRAM_NAME:-$0}"

usage() {
  cat <<EOF
usage: $PROGRAM_NAME COMMAND [ARGS...]

commands:
  push            Push the current branch
  pr-create       Create a pull request
  pr-update       Update a pull request
  issue-get       Read an issue
  issue-create    Create an issue
  issue-transfer  Transfer an issue to another repository
  issue-update    Update an issue
  issue-assign    Assign users to an issue
  issue-comment   Comment on an issue or pull request
  issue-sub-add   Link a child issue to a parent
  issue-block-add     Record that one issue is blocked by another
  issue-block-remove  Remove a blocked-by dependency between two issues
  issue-block-list    List an issue's blocked-by / blocking dependencies
  actions-run-view       Read workflow-run metadata
  actions-job-log        Download a job log
  actions-rerun-failed   Rerun failed jobs in a workflow run
  actions-cancel         Cancel a workflow run
  actions-force-cancel   Force cancel a workflow run

Run "$PROGRAM_NAME COMMAND --help" for command-specific arguments.
EOF
}

command_name="${1:-}"
case "$command_name" in
  --help|-h|"") usage; exit 0 ;;
  push|pr-create|pr-update|issue-get|issue-transfer|issue-create|issue-update|issue-assign|issue-comment|issue-sub-add|issue-block-add|issue-block-remove|issue-block-list|actions-run-view|actions-job-log|actions-rerun-failed|actions-cancel|actions-force-cancel) ;;
  *) echo "unknown command: $command_name" >&2; usage >&2; exit 1 ;;
esac
shift

exec "$SCRIPT_DIR/gh-app-${command_name}.sh" "$@"
