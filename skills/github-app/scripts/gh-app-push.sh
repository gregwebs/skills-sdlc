#!/usr/bin/env bash
# Push the current branch to origin using the GitHub App credential helper.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  echo "usage: $0 [--force | --force-with-lease]"
  echo "Push the current non-main branch to origin with GitHub App authentication."
  echo "--force / -f         push with --force (overwrites remote history)"
  echo "--force-with-lease   push with --force-with-lease (refuses if the remote moved)"
}

force_flag=""
while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --force|-f) force_flag="--force"; shift ;;
    --force-with-lease) force_flag="--force-with-lease"; shift ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

REPO_ROOT="$(git rev-parse --show-toplevel)"
HELPER="$SCRIPT_DIR/credential-helper.sh"

branch="$(git -C "$REPO_ROOT" symbolic-ref --quiet --short HEAD)" || {
  echo "gh-app-push: HEAD is detached; check out a branch first" >&2
  exit 2
}

if [[ "$branch" == "main" ]]; then
  echo "gh-app-push: refusing to push main; check out a working branch first" >&2
  exit 2
fi

push_args=(--set-upstream)
if [ -n "$force_flag" ]; then
  push_args+=("$force_flag")
fi
push_args+=(origin "$branch")

GIT_CONFIG_GLOBAL=/dev/null \
GIT_CONFIG_NOSYSTEM=1 \
exec git \
  -C "$REPO_ROOT" \
  -c "credential.https://github.com.helper=$HELPER" \
  -c credential.https://github.com.username=x-access-token \
  push "${push_args[@]}"
