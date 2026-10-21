#!/usr/bin/env bash
# Run gh as the GitHub App installation: export a minted installation token as
# GH_TOKEN and exec gh with the arguments unchanged. `git push` is the one
# wrapped non-gh command, so pushes authenticate as the App too.
#
# Requires a GitHub App set up per the Setup reference in the /github-app skill.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/gh-app-token.sh"

push_usage() {
  echo "usage: gh-app.sh git push [--force | -f | --force-with-lease]" >&2
}

# A failed mint must stop here: gh with an empty GH_TOKEN falls back to the
# user's own stored login.
export_app_token() {
  local token
  token=$(gh_app_token) || exit 1
  export GH_TOKEN="$token"
}

if [ "${1:-}" != git ]; then
  export_app_token
  exec gh "$@"
fi

if [ "${2:-}" != push ]; then
  echo "gh-app.sh: only 'git push' is supported" >&2
  push_usage
  exit 2
fi
shift 2

# Only flags are accepted: a refspec argument could name main and bypass the guard.
for arg in "$@"; do
  case "$arg" in
    --force|-f|--force-with-lease) ;;
    *) echo "gh-app.sh: unsupported git push argument: $arg" >&2; push_usage; exit 2 ;;
  esac
done

repo_root="$(git rev-parse --show-toplevel)"
branch="$(git -C "$repo_root" symbolic-ref --quiet --short HEAD)" || {
  echo "gh-app.sh: HEAD is detached; check out a branch first" >&2
  exit 2
}
if [ "$branch" = main ]; then
  echo "gh-app.sh: refusing to push main; check out a working branch first" >&2
  exit 2
fi

export_app_token
# Global and system config are ignored, and `credential.helper=` empties the
# helper list, so no user credential helper can answer before the App's.
# The refspec names its destination so a local remote.origin.push mapping
# cannot redirect the branch onto main.
GIT_CONFIG_GLOBAL=/dev/null \
GIT_CONFIG_NOSYSTEM=1 \
exec git -C "$repo_root" \
  -c credential.helper= \
  -c 'credential.https://github.com.helper=!gh auth git-credential' \
  -c credential.https://github.com.username=x-access-token \
  push --set-upstream "$@" origin "refs/heads/${branch}:refs/heads/${branch}"
