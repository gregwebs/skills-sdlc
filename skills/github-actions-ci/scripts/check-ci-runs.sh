#!/usr/bin/env bash
# Report GitHub Actions check runs for a commit.
#
# Usage: check-ci-runs.sh [--wait] [--job JOB_NAME] [COMMIT]
# COMMIT defaults to HEAD. With --wait, poll until the selected check runs complete.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOKEN_HELPER="$SCRIPT_DIR/../../github-app/scripts/gh-app-token.sh"

usage() {
  echo "usage: check-ci-runs.sh [--wait] [--job JOB_NAME] [COMMIT]" >&2
}

wait_for_result=false
job_filter=""
commit="HEAD"
while [ $# -gt 0 ]; do
  case "$1" in
    --wait)
      wait_for_result=true
      shift
      ;;
    --job)
      if [ -z "${2:-}" ]; then
        usage
        exit 2
      fi
      job_filter="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    -*)
      usage
      exit 2
      ;;
    *)
      if [ "$commit" != "HEAD" ]; then
        usage
        exit 2
      fi
      commit="$1"
      shift
      ;;
  esac
done

REPO_ROOT="$(git rev-parse --show-toplevel)"
sha=$(git -C "$REPO_ROOT" rev-parse "$commit")
origin=$(git -C "$REPO_ROOT" config --get remote.origin.url)
repo=${origin#*github.com[:/]}
repo=${repo%.git}

if [ -n "${CHECK_CI_CURL:-}" ]; then
  curl_bin="$CHECK_CI_CURL"
elif [ -x /opt/homebrew/opt/curl/bin/curl ]; then
  curl_bin=/opt/homebrew/opt/curl/bin/curl
else
  curl_bin=curl
fi

github_app_auth=false
github_app_secrets_dir="${GITHUB_APP_SECRETS_DIR:-$HOME/.config/github-app}"
if [ -r "$github_app_secrets_dir/client-id" ] \
  && [ -r "$github_app_secrets_dir/installation-id" ] \
  && [ -r "$github_app_secrets_dir/private-key.pem" ]; then
  if [ ! -r "$TOKEN_HELPER" ]; then
    echo "check-ci-runs: GitHub App token helper not found: $TOKEN_HELPER" >&2
    exit 1
  fi
  # TOKEN_HELPER is resolved relative to this script, so the dynamic source is intentional.
  # shellcheck disable=SC1090
  source "$TOKEN_HELPER"
  github_app_auth=true
fi

if [ "$github_app_auth" = true ]; then
  interval=${CHECK_INTERVAL_SECONDS:-10}
else
  # Anonymous GitHub API reads have a low shared-IP rate limit.
  interval=${CHECK_INTERVAL_SECONDS:-60}
fi

# How long to keep polling an ambiguous "no check runs yet" result before
# concluding that no GitHub Actions check will ever apply to this commit.
grace=${CI_ABSENT_GRACE_SECONDS:-120}
first_absent_epoch=""

# curl_get prints the JSON body for an API path or propagates curl's failure
# (still under set -e), used for the primary check-runs fetch that must hard
# fail on a transport/HTTP error rather than be misread as "no CI".
curl_get() {
  local auth_args=()
  if [ "$github_app_auth" = true ]; then
    auth_args=(-H "Authorization: Bearer $(gh_app_token)")
  fi
  "$curl_bin" -fsS \
    "${auth_args[@]}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/$1"
}

# probe_get is curl_get for the optional "why is this absent" probes: it
# prints nothing (never aborts the script) on any transport/HTTP error, so a
# probe failure can only fall back to the pending/undetermined behavior.
probe_get() {
  curl_get "$1" 2>/dev/null || true
}

# shellcheck disable=SC2016 # jq sees $job; the shell must not expand it.
actions_checks_query='
  [.check_runs[]
   | select(.app.slug == "github-actions")]
  | sort_by(.name, (.started_at // .created_at // ""))
  | group_by(.name)
  | map(max_by(.started_at // .created_at // ""))
  | sort_by(.name)
'
other_runs_query='[.check_runs[] | select(.app.slug != "github-actions")]'

while true; do
  checks_raw=$(curl_get "repos/$repo/commits/$sha/check-runs?per_page=100")

  actions_checks=$(jq -c "$actions_checks_query" <<<"$checks_raw")
  selected=$(jq -c --arg job "$job_filter" \
    '[.[] | select($job == "" or .name == $job)]' <<<"$actions_checks")
  other_runs=$(jq -c "$other_runs_query" <<<"$checks_raw")

  actions_count=$(jq 'length' <<<"$actions_checks")
  selected_count=$(jq 'length' <<<"$selected")
  other_count=$(jq 'length' <<<"$other_runs")

  other_note=""
  if [ "$other_count" -gt 0 ]; then
    other_slugs=$(jq -r '[.[].app.slug] | unique | join(", ")' <<<"$other_runs")
    other_note=" ($other_count check runs from other apps: $other_slugs)"
  fi

  if [ "$selected_count" -eq 0 ]; then
    if [ -n "$job_filter" ] && [ "$actions_count" -gt 0 ]; then
      # The job hasn't reported yet, but other GitHub Actions checks exist for
      # this commit, so CI does apply here; keep this as ordinary "pending".
      echo "$job_filter: not found among $actions_count GitHub Actions checks for $sha" >&2
      if [ "$wait_for_result" = true ]; then
        sleep "$interval"
        continue
      fi
      exit 2
    fi

    # No GitHub Actions check run matched at all. Distinguish "nothing will
    # ever run here" (success: exit 0) from "still registering" (exit 2)
    # instead of collapsing both into one ambiguous state.
    runs_probe=$(probe_get "repos/$repo/actions/runs?head_sha=$sha&per_page=1")
    runs_total=""
    if [ -n "$runs_probe" ]; then
      runs_total=$(jq -r '.total_count // empty' <<<"$runs_probe" 2>/dev/null || true)
    fi

    if [ -n "$runs_total" ] && [ "$runs_total" != "0" ]; then
      echo "CI checks: not found for $sha (a workflow run is in progress)$other_note" >&2
      if [ "$wait_for_result" = true ]; then
        sleep "$interval"
        continue
      fi
      exit 2
    fi

    if [ "$runs_total" = "0" ]; then
      workflows_probe=$(probe_get "repos/$repo/actions/workflows?per_page=100")
      active_count=""
      if [ -n "$workflows_probe" ]; then
        active_count=$(jq -r '[.workflows[]? | select(.state == "active")] | length' \
          <<<"$workflows_probe" 2>/dev/null || true)
      fi

      if [ "$active_count" = "0" ]; then
        echo "CI checks: no GitHub Actions workflows configured for $repo$other_note" >&2
        exit 0
      fi

      if [ -n "$active_count" ]; then
        now=$(date +%s)
        if [ -z "$first_absent_epoch" ]; then
          first_absent_epoch=$now
        fi
        elapsed=$((now - first_absent_epoch))
        if [ "$elapsed" -ge "$grace" ]; then
          echo "CI checks: no GitHub Actions checks apply to $sha (confirmed after ${elapsed}s)$other_note" >&2
          exit 0
        fi
        echo "CI checks: not found for $sha (waiting up to ${grace}s to confirm no CI applies)$other_note" >&2
        if [ "$wait_for_result" = true ]; then
          sleep "$interval"
          continue
        fi
        exit 2
      fi
    fi

    # A probe failed or returned unusable data (rate limit, private repo
    # without auth, transport error). Never guess "no CI" here.
    echo "CI checks: not found for $sha$other_note" >&2
    if [ "$wait_for_result" = true ]; then
      sleep "$interval"
      continue
    fi
    exit 2
  fi

  jq -r '.[] | "\(.name): \(.status) (\(.conclusion // "pending"))\n\(.html_url)"' <<<"$selected"

  if jq -e 'all(.[]; .status == "completed" and (.conclusion | IN("success","skipped","neutral")))' \
    >/dev/null <<<"$selected"; then
    exit
  fi

  if jq -e 'any(.[]; .status == "completed" and (.conclusion | IN("success","skipped","neutral") | not))' \
    >/dev/null <<<"$selected"; then
    exit 1
  fi

  if [ "$wait_for_result" = false ]; then
    exit 2
  fi
  sleep "$interval"
done
