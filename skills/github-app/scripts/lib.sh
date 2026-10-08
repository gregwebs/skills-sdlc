#!/usr/bin/env bash
# Shared helpers for the gh-app-*.sh scripts in this directory. These call
# the GitHub REST API directly (not the gh CLI) using a token minted from a
# GitHub App installation - see ./gh-app-token.sh in this directory.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/gh-app-token.sh"

GH_APP_API_VERSION="${GH_APP_API_VERSION:-2022-11-28}"

# Best-effort "owner/repo" from the current directory's origin remote.
gh_app_default_repo() {
  local url
  url=$(git config --get remote.origin.url 2>/dev/null) || return 1
  url=${url#*github.com[:/]}
  url=${url%.git}
  printf '%s' "$url"
}

# Resolve a --body/--body-file pair into final body text (file wins if both given).
gh_app_resolve_body() {
  local body="$1" body_file="$2"
  if [ -n "$body_file" ]; then
    cat "$body_file"
  else
    printf '%s' "$body"
  fi
}

# POST $2 (a JSON payload) to API path $1 (e.g. "repos/owner/repo/issues"),
# authenticated with a freshly minted App installation token. Prints the
# response's html_url on success; prints the error body to stderr and
# returns 1 on a >=400 response.
gh_app_api_post() {
  local path="$1" payload="$2" token response status body
  token=$(gh_app_token)
  response=$(gh_app_curl -s -w '\n%{http_code}' -X POST \
    -H "Authorization: token $token" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: ${GH_APP_API_VERSION}" \
    "https://api.github.com/${path}" \
    -d "$payload")
  status=$(printf '%s' "$response" | tail -n1)
  body=$(printf '%s' "$response" | sed '$d')
  if [ "$status" -ge 400 ]; then
    echo "GitHub API error ($status):" >&2
    printf '%s\n' "$body" | jq . >&2 2>/dev/null || printf '%s\n' "$body" >&2
    return 1
  fi
  printf '%s' "$body" | jq -r '.html_url'
}

# PATCH $2 (a JSON payload) to API path $1 (e.g. "repos/owner/repo/pulls/42"),
# authenticated with a freshly minted App installation token. Prints the
# response's html_url on success; prints the error body to stderr and
# returns 1 on a >=400 response.
gh_app_api_patch() {
  local path="$1" payload="$2" token response status body
  token=$(gh_app_token)
  response=$(gh_app_curl -s -w '\n%{http_code}' -X PATCH \
    -H "Authorization: token $token" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: ${GH_APP_API_VERSION}" \
    "https://api.github.com/${path}" \
    -d "$payload")
  status=$(printf '%s' "$response" | tail -n1)
  body=$(printf '%s' "$response" | sed '$d')
  if [ "$status" -ge 400 ]; then
    echo "GitHub API error ($status):" >&2
    printf '%s\n' "$body" | jq . >&2 2>/dev/null || printf '%s\n' "$body" >&2
    return 1
  fi
  printf '%s' "$body" | jq -r '.html_url'
}

# DELETE API path $1 (e.g. "repos/owner/repo/issues/42/dependencies/blocked_by/123"),
# authenticated with a freshly minted App installation token. Prints the
# response's html_url on success; prints the error body to stderr and
# returns 1 on a >=400 response.
gh_app_api_delete() {
  local path="$1" token response status body
  token=$(gh_app_token)
  response=$(gh_app_curl -s -w '\n%{http_code}' -X DELETE \
    -H "Authorization: token $token" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: ${GH_APP_API_VERSION}" \
    "https://api.github.com/${path}")
  status=$(printf '%s' "$response" | tail -n1)
  body=$(printf '%s' "$response" | sed '$d')
  if [ "$status" -ge 400 ]; then
    echo "GitHub API error ($status):" >&2
    printf '%s\n' "$body" | jq . >&2 2>/dev/null || printf '%s\n' "$body" >&2
    return 1
  fi
  printf '%s' "$body" | jq -r '.html_url'
}

# GET API path $1 (e.g. "repos/owner/repo/pulls/42"),
# authenticated with a freshly minted App installation token. Prints the
# response JSON on success; prints the error body to stderr and returns 1
# on a >=400 response.
gh_app_api_get() {
  local path="$1" token response status body
  token=$(gh_app_token) || return $?
  response=$(gh_app_curl -sS -w '\n%{http_code}' -X GET \
    -H "Authorization: token $token" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: ${GH_APP_API_VERSION}" \
    "https://api.github.com/${path}") || return $?
  status=$(printf '%s' "$response" | tail -n1)
  body=$(printf '%s' "$response" | sed '$d')
  if ! [[ "$status" =~ ^2[0-9][0-9]$ ]]; then
    echo "GitHub API error ($status):" >&2
    printf '%s\n' "$body" | jq . >&2 2>/dev/null || printf '%s\n' "$body" >&2
    return 1
  fi
  printf '%s' "$body"
}

# GraphQL mutations must not be retried automatically: a transport failure
# can occur after GitHub has already applied the mutation.
gh_app_api_graphql() {
  local query="$1" variables="$2" payload token response status body
  payload=$(jq -n --arg query "$query" --argjson variables "$variables" \
    '{query: $query, variables: $variables}') || return $?
  token=$(gh_app_token) || return $?
  response=$(gh_app_curl -sS -w '\n%{http_code}' -X POST \
    -H "Authorization: token $token" \
    -H "Accept: application/vnd.github+json" \
    -H "Content-Type: application/json" \
    "https://api.github.com/graphql" \
    -d "$payload") || return $?
  status=$(printf '%s' "$response" | tail -n1)
  body=$(printf '%s' "$response" | sed '$d')
  if ! [[ "$status" =~ ^2[0-9][0-9]$ ]]; then
    echo "GitHub GraphQL HTTP error ($status):" >&2
    printf '%s\n' "$body" >&2
    return 1
  fi
  if ! printf '%s' "$body" | jq -es 'length == 1 and (.[0] | type == "object")' >/dev/null; then
    echo "GitHub GraphQL: malformed JSON response" >&2
    return 1
  fi
  if ! printf '%s' "$body" | jq -e '.errors == null or .errors == []' >/dev/null; then
    echo "GitHub GraphQL errors:" >&2
    printf '%s\n' "$body" >&2
    return 1
  fi
  printf '%s\n' "$body"
}

# Download a raw API response, following GitHub's redirect to the short-lived
# signed download URL. Authentication is scoped to the api.github.com request;
# curl does not forward the Authorization header to a different redirect host.
gh_app_api_download() {
  local path="$1" output="${2:-}" token
  token=$(gh_app_token)
  if [ -n "$output" ]; then
    gh_app_curl -fsSL \
      -H "Authorization: token $token" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: ${GH_APP_API_VERSION}" \
      "https://api.github.com/${path}" \
      -o "$output"
  else
    gh_app_curl -fsSL \
      -H "Authorization: token $token" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: ${GH_APP_API_VERSION}" \
      "https://api.github.com/${path}"
  fi
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  case "${1:-}" in
    --help|-h)
      cat <<EOF
usage: $0

Shared helper library for gh-app scripts. Source this file from another script.
EOF
      exit 0
      ;;
    "")
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 1
      ;;
  esac
fi
