#!/usr/bin/env bash
# Shared lib: mint and cache a short-lived GitHub App installation access token.
# Sourced by gh-app.sh, gh-app-issue-dependency.sh, gh-app-issue-sub-issue.sh and
# ../../github-actions-ci/scripts/check-ci-runs.sh, which depends on this path
# and on the gh_app_token name.
#
# This is the only code here that calls GitHub over HTTP directly: `gh api` has
# no --jwt, so the App JWT -> installation token exchange cannot go through gh.
#
# Reads from $GITHUB_APP_SECRETS_DIR (default ~/.config/github-app; see the
# Setup reference in the /github-app skill):
#   - client-id        the App's client ID (used as the JWT `iss` claim)
#   - installation-id  the installation to mint a token for
#   - private-key.pem  the App's private key (signs the JWT)
#
# Tokens are cached per installation as one "expires_at<TAB>token" line, where
# expires_at is GitHub's expiry as epoch seconds. The cache only saves a mint
# round-trip: any read, parse or write problem falls through to a fresh mint.

# Seconds before GitHub's expiry at which a cached token is no longer handed out,
# so a long gh command does not outlive its token.
GH_APP_TOKEN_REFRESH_MARGIN=300

_gh_app_b64url() {
  openssl base64 -A | tr '+/' '-_' | tr -d '='
}

gh_app_curl() {
  if [ -x /opt/homebrew/opt/curl/bin/curl ]; then
    /opt/homebrew/opt/curl/bin/curl "$@"
  else
    curl "$@"
  fi
}

# Fails when no cache location is known (both HOME and XDG_CACHE_HOME unset)
# or the root is not absolute, so the caller can skip the cache rather than
# guess a path. A relative root would put the live token inside the working
# tree, where a later `git add -A` could commit it; the XDG spec says relative
# paths are to be ignored.
_gh_app_cache_file() {
  local root="${XDG_CACHE_HOME:-${HOME:+$HOME/.cache}}"
  [ -n "$root" ] || return 1
  [[ "$root" = /* ]] || return 1
  printf '%s/gh-app/token.%s' "$root" "$1"
}

# The expiry is validated before arithmetic: bash evaluates non-numeric text in
# $(( )) as an expression, which aborts under `set -u` and can run commands.
# A leading zero is rejected because bash would read the value as octal.
_gh_app_cached_token() {
  local cache_file="$1" expires_at token
  [ -f "$cache_file" ] && [ -r "$cache_file" ] || return 1
  IFS=$'\t' read -r expires_at token <"$cache_file" || return 1
  [[ "$expires_at" =~ ^[1-9][0-9]{0,11}$ ]] || return 1
  [[ "$token" =~ ^[[:graph:]]+$ ]] || return 1
  [ "$(date +%s)" -lt "$((expires_at - GH_APP_TOKEN_REFRESH_MARGIN))" ] || return 1
  printf '%s' "$token"
}

# Reports an unusable Setup file as a diagnostic that names it. The prefix is
# the one SKILL.md documents for this cause, so its guidance stays true; the
# remedy lives in the Setup reference of the /github-app skill.
_gh_app_secrets_error() {
  printf 'gh-app-token: failed to obtain installation access token: missing or unusable %s; set it up as described in the Setup reference of the /github-app skill\n' "$1" >&2
}

# Fails on the first missing or unreadable Setup file among $2..., naming it, so
# no raw `cat:` or `openssl:` error reaches the user. Both tests are needed:
# -r alone accepts a directory, which openssl would then report itself.
_gh_app_require_secrets() {
  local secrets_dir="$1" name
  shift
  for name in "$@"; do
    if [ -f "$secrets_dir/$name" ] && [ -r "$secrets_dir/$name" ]; then
      continue
    fi
    _gh_app_secrets_error "$secrets_dir/$name"
    return 1
  done
}

# Prints "expires_at<TAB>token" for a freshly minted installation token.
# expires_at is 0 when GitHub's expiry does not parse: the token is still good,
# it just is not cached.
_gh_app_mint() {
  local secrets_dir="$1" installation_id="$2"
  local client_id now header claims signing_input signature jwt response expires_at token
  # stderr dropped: the caller's check names a missing or unreadable file.
  client_id=$(cat "$secrets_dir/client-id" 2>/dev/null) || return 1
  now=$(date +%s)
  header=$(printf '{"alg":"RS256","typ":"JWT"}' | _gh_app_b64url)
  claims=$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' "$((now - 60))" "$((now + 540))" "$client_id" | _gh_app_b64url)
  signing_input="${header}.${claims}"
  # A missing or unreadable key was already named by the caller; a key openssl
  # still rejects fails the mint, which the caller reports. Its stderr is
  # dropped for the same reason: no raw tool error reaches the user.
  signature=$(printf '%s' "$signing_input" | openssl dgst -sha256 -sign "$secrets_dir/private-key.pem" 2>/dev/null | _gh_app_b64url) \
    || return 1
  jwt="${signing_input}.${signature}"

  response=$(gh_app_curl -fsS -X POST \
    -H "Authorization: Bearer $jwt" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/app/installations/${installation_id}/access_tokens") || return 1
  token=$(printf '%s' "$response" | jq -r '.token // empty') || return 1
  [[ "$token" =~ ^[[:graph:]]+$ ]] || return 1
  expires_at=$(printf '%s' "$response" | jq -r '.expires_at | fromdateiso8601' 2>/dev/null) || expires_at=0
  [[ "$expires_at" =~ ^[1-9][0-9]{0,11}$ ]] || expires_at=0
  printf '%s\t%s' "$expires_at" "$token"
}

# Best effort: a cache that cannot be written only costs the next call a mint.
_gh_app_cache_write() {
  local cache_file="$1" expires_at="$2" token="$3" cache_dir tmp
  # `mv` into a directory would keep the temp file, so never write there.
  [ -d "$cache_file" ] && return 0
  cache_dir=$(dirname "$cache_file")
  (umask 077 && mkdir -p "$cache_dir") 2>/dev/null || return 0
  chmod 700 "$cache_dir" || return 0
  tmp=$(mktemp "$cache_dir/.token.XXXXXX") || return 0
  if chmod 600 "$tmp" \
    && printf '%s\t%s\n' "$expires_at" "$token" >"$tmp" \
    && mv -f "$tmp" "$cache_file"; then
    return 0
  fi
  rm -f "$tmp"
  return 0
}

gh_app_token() {
  local secrets_dir installation_id cache_file minted expires_at token
  # A diagnostic instead of an unbound-variable abort when HOME is unset.
  if [ -n "${GITHUB_APP_SECRETS_DIR:-}" ]; then
    secrets_dir="$GITHUB_APP_SECRETS_DIR"
  elif [ -n "${HOME:-}" ]; then
    secrets_dir="$HOME/.config/github-app"
  else
    echo "gh-app-token: neither GITHUB_APP_SECRETS_DIR nor HOME is set" >&2
    return 1
  fi
  installation_id=$(cat "$secrets_dir/installation-id" 2>/dev/null) \
    || { _gh_app_secrets_error "$secrets_dir/installation-id"; return 1; }
  if ! [[ "$installation_id" =~ ^[0-9]+$ ]]; then
    echo "gh-app-token: installation-id must be numeric" >&2
    return 1
  fi
  cache_file=$(_gh_app_cache_file "$installation_id") || cache_file=""
  if [ -n "$cache_file" ] && _gh_app_cached_token "$cache_file"; then
    return 0
  fi
  # Only a mint needs these two, and a missing one must be named: gh with the
  # user's own login is the fallback this whole wrapper exists to prevent. The
  # check is here, not in the mint, so the diagnostic is printed once.
  _gh_app_require_secrets "$secrets_dir" client-id private-key.pem || return 1
  if ! minted=$(_gh_app_mint "$secrets_dir" "$installation_id"); then
    echo "gh-app-token: failed to obtain installation access token" >&2
    return 1
  fi
  IFS=$'\t' read -r expires_at token <<<"$minted"
  [ -z "$cache_file" ] || [ "$expires_at" = 0 ] \
    || _gh_app_cache_write "$cache_file" "$expires_at" "$token"
  printf '%s' "$token"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  case "${1:-}" in
    --help|-h)
      cat <<EOF
usage: $0

Defines gh_app_token when sourced. When run directly, prints nothing.
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
