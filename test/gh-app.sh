#!/usr/bin/env bash
# Functional test for skills/github-app/scripts/gh-app.sh and the token cache in
# gh-app-token.sh. gh is a PATH stub and the mint's HTTP call (gh_app_curl) is
# replaced at the function level, so no network or App credentials are needed.
set -euo pipefail

REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "gh-app test: $*" >&2
  exit 1
}

if [ -d /private/tmp ]; then
  TEMP_ROOT=/private/tmp
else
  TEMP_ROOT=/tmp
fi
WORK=$(mktemp -d "$TEMP_ROOT/skills-sdlc-gh-app.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

# The real wrapper and token script; a later gh_app_curl definition replaces
# only the HTTP call of the mint.
SCRIPTS="$WORK/scripts"
mkdir -p "$SCRIPTS"
cp "$REPOSITORY_ROOT/skills/github-app/scripts/gh-app.sh" \
  "$REPOSITORY_ROOT/skills/github-app/scripts/gh-app-token.sh" "$SCRIPTS/"
cat >>"$SCRIPTS/gh-app-token.sh" <<'EOF'
gh_app_curl() {
  printf 'mint\n' >>"$MINT_LOG"
  [ "$MINT_STATUS" = 0 ] || return "$MINT_STATUS"
  printf '%s' "$MINT_BODY"
}
EOF
WRAPPER="$SCRIPTS/gh-app.sh"

mkdir -p "$WORK/bin"
cat >"$WORK/bin/gh" <<'EOF'
#!/usr/bin/env bash
# Test double for gh: records argv (one per line, then an end marker) and GH_TOKEN.
printf '%s\n' "$@" '--end--' >>"$GH_ARGS_LOG"
printf '%s\n' "${GH_TOKEN:-}" >>"$GH_TOKEN_LOG"
exit "$GH_STATUS"
EOF
chmod +x "$WORK/bin/gh"

SECRETS="$WORK/secrets"
mkdir -p "$SECRETS"
printf 'Iv1.fixture' >"$SECRETS/client-id"
printf '123\n' >"$SECRETS/installation-id"
openssl genrsa -out "$SECRETS/private-key.pem" 2048 2>/dev/null \
  || fail "openssl could not generate a fixture key"

export PATH="$WORK/bin:$PATH"
export HOME="$WORK/home" XDG_CACHE_HOME="$WORK/cache" GITHUB_APP_SECRETS_DIR="$SECRETS"
export MINT_LOG="$WORK/mint.log" GH_ARGS_LOG="$WORK/gh-args.log" GH_TOKEN_LOG="$WORK/gh-token.log"
export GIT_LOG="$WORK/git-args.log" GIT_TOKEN_LOG="$WORK/git-token.log" GIT_ENV_LOG="$WORK/git-env.log"
export MINT_STATUS=0 GH_STATUS=0
MINTED_BODY='{"token":"minted-token","expires_at":"2099-01-01T00:00:00Z"}'
export MINT_BODY="$MINTED_BODY"
unset GH_TOKEN GITHUB_TOKEN
CACHE_FILE="$XDG_CACHE_HOME/gh-app/token.123"
MINTED_EXPIRY=4070908800 # 2099-01-01T00:00:00Z

run_wrapper() {
  : >"$MINT_LOG"
  : >"$GH_ARGS_LOG"
  : >"$GH_TOKEN_LOG"
  : >"$GIT_LOG"
  : >"$GIT_TOKEN_LOG"
  : >"$GIT_ENV_LOG"
  last_status=0
  "$WRAPPER" "$@" >"$WORK/out" 2>"$WORK/err" || last_status=$?
  if grep -Fq -e minted-token -e cached-token "$WORK/out" "$WORK/err"; then
    fail "token leaked to command output"
  fi
}

expect_status() {
  [ "$last_status" = "$1" ] || fail "expected exit $1, got $last_status: $(cat "$WORK/err")"
}

expect_mints() {
  [ "$(wc -l <"$MINT_LOG" | tr -d ' ')" = "$1" ] || fail "expected $1 mint(s), got $(wc -l <"$MINT_LOG")"
}

expect_gh_token() {
  [ "$(cat "$GH_TOKEN_LOG")" = "$1" ] || fail "expected gh to get token $1, got: $(cat "$GH_TOKEN_LOG")"
}

expect_gh_not_run() {
  [ ! -s "$GH_ARGS_LOG" ] || fail "gh ran: $(cat "$GH_ARGS_LOG")"
}

seed_cache() {
  mkdir -p "$(dirname "$CACHE_FILE")"
  printf '%s' "$1" >"$CACHE_FILE"
}

has_mode() {
  [ -n "$(find "$1" -prune -perm "$2")" ]
}

expect_secrets_error() {
  local secrets_dir="$1" named="$2" label="$3"
  rm -rf "$XDG_CACHE_HOME"
  GITHUB_APP_SECRETS_DIR="$secrets_dir" run_wrapper api user
  [ "$last_status" != 0 ] || fail "$label exited 0"
  expect_gh_not_run
  expect_mints 0
  grep -Fq 'gh-app-token: failed to obtain installation access token' "$WORK/err" \
    || fail "$label lacked the documented diagnostic: $(cat "$WORK/err")"
  grep -Fq "missing or unusable $named" "$WORK/err" \
    || fail "$label did not name $named: $(cat "$WORK/err")"
  # A raw `cat:` or `openssl:` line would leave the user without a next step.
  ! grep -Eq '^(cat|openssl):|^Could not open' "$WORK/err" \
    || fail "$label leaked a raw tool error: $(cat "$WORK/err")"
  [ ! -e "$XDG_CACHE_HOME" ] || fail "$label wrote a cache"
}

now=$(date +%s)

# A fresh cached token is used without minting.
seed_cache "$((now + 3600))"$'\tcached-token\n'
run_wrapper api user
expect_status 0
expect_mints 0
expect_gh_token cached-token

# No cache: mint once, cache GitHub's expiry, reuse on the next call.
rm -rf "$XDG_CACHE_HOME"
run_wrapper api user
expect_status 0
expect_mints 1
expect_gh_token minted-token
[ "$(cat "$CACHE_FILE")" = "$MINTED_EXPIRY"$'\t'minted-token ] \
  || fail "unexpected cache content: $(cat "$CACHE_FILE")"
has_mode "$CACHE_FILE" 600 || fail "cache file is not mode 600"
has_mode "$(dirname "$CACHE_FILE")" 700 || fail "cache directory is not mode 700"
[ -z "$(find "$(dirname "$CACHE_FILE")" -name '.token.*')" ] || fail "temporary cache file left behind"
run_wrapper api user
expect_mints 0
expect_gh_token minted-token

# Expired, or inside the refresh margin: re-mint.
for expiry in "$((now - 10))" "$((now + 100))"; do
  seed_cache "$expiry"$'\tcached-token\n'
  run_wrapper api user
  expect_status 0
  expect_mints 1
  expect_gh_token minted-token
done

# Corrupt caches fall through to a fresh mint and never run cache content.
# The leading-zero cases must not reach $(( )), where bash would read them as
# octal and abort the call. Expiries past 12 digits are rejected too: bash
# wraps them, and `99999999999999999999 - 300` stays in the future, so an
# unbounded regex would serve that stale token until the cache was deleted.
for corrupt in \
  '' \
  'garbage' \
  $'garbage\tcached-token\n' \
  $'09\tcached-token\n' \
  $'0999999999\tcached-token\n' \
  $'9999999999999\tcached-token\n' \
  $'99999999999999999999\tcached-token\n' \
  "$((now + 3600))"$'\t\n' \
  "$((now + 3600))"$'\n' \
  "$((now + 3600))"$'\tcached-token\textra\n' \
  "$((now + 3600))"$'\tcached-token\r\n' \
  "x[\$(touch $WORK/pwned)]"$'\tcached-token\n'; do
  seed_cache "$corrupt"
  run_wrapper api user
  expect_status 0
  expect_mints 1
  expect_gh_token minted-token
done
[ ! -e "$WORK/pwned" ] || fail "cache content was evaluated"

# A directory where the cache file belongs must not swallow token temp files.
rm -rf "$XDG_CACHE_HOME"
mkdir -p "$CACHE_FILE"
run_wrapper api user
expect_status 0
expect_mints 1
expect_gh_token minted-token
[ -z "$(find "$(dirname "$CACHE_FILE")" -name '.token.*')" ] || fail "temporary cache file left behind"
rm -rf "$XDG_CACHE_HOME"

# An existing cache directory with a loose mode is tightened: the token must
# not sit in a directory another user can list.
mkdir -p "$(dirname "$CACHE_FILE")"
chmod 755 "$(dirname "$CACHE_FILE")"
run_wrapper api user
expect_status 0
has_mode "$(dirname "$CACHE_FILE")" 700 \
  || fail "a pre-existing cache directory was not tightened to mode 700"
rm -rf "$XDG_CACHE_HOME"

# With neither HOME nor XDG_CACHE_HOME there is no cache location: mint without
# caching, and leave the working directory alone. A relative XDG_CACHE_HOME or
# HOME is treated the same way, so a live token never lands in the working tree.
for shape in unset xdg-relative home-relative; do
  rm -rf "$WORK/cwd"
  mkdir -p "$WORK/cwd"
  chmod 755 "$WORK/cwd"
  : >"$MINT_LOG"
  : >"$GH_ARGS_LOG"
  : >"$GH_TOKEN_LOG"
  last_status=0
  case "$shape" in
    unset)
      (cd "$WORK/cwd" && env -u HOME -u XDG_CACHE_HOME "$WRAPPER" api user \
        >"$WORK/out" 2>"$WORK/err") || last_status=$?
      ;;
    xdg-relative)
      (cd "$WORK/cwd" && env XDG_CACHE_HOME=. "$WRAPPER" api user \
        >"$WORK/out" 2>"$WORK/err") || last_status=$?
      ;;
    home-relative)
      (cd "$WORK/cwd" && env -u XDG_CACHE_HOME HOME=. "$WRAPPER" api user \
        >"$WORK/out" 2>"$WORK/err") || last_status=$?
      ;;
  esac
  expect_status 0
  expect_mints 1
  expect_gh_token minted-token
  has_mode "$WORK/cwd" 755 || fail "$shape: the working directory's mode was changed"
  [ -z "$(ls -A "$WORK/cwd")" ] \
    || fail "$shape: files written into the working directory: $(ls -A "$WORK/cwd")"
done

# No secrets location either: a diagnostic, not an unbound-variable abort.
: >"$GH_ARGS_LOG"
last_status=0
(cd "$WORK/cwd" && env -u HOME -u XDG_CACHE_HOME -u GITHUB_APP_SECRETS_DIR "$WRAPPER" api user \
  >"$WORK/out" 2>"$WORK/err") || last_status=$?
[ "$last_status" != 0 ] || fail "missing secrets location exited 0"
expect_gh_not_run
grep -Fq 'neither GITHUB_APP_SECRETS_DIR nor HOME is set' "$WORK/err" \
  || fail "missing secrets location lacked diagnostic: $(cat "$WORK/err")"

# Without XDG_CACHE_HOME the cache lives under ~/.cache.
: >"$MINT_LOG"
env -u XDG_CACHE_HOME "$WRAPPER" api user >/dev/null 2>&1 || fail "wrapper failed without XDG_CACHE_HOME"
[ -f "$HOME/.cache/gh-app/token.123" ] || fail "default cache path not used"

# An expiry jq cannot parse still yields the token; it is just not cached.
rm -rf "$XDG_CACHE_HOME"
MINT_BODY='{"token":"minted-token","expires_at":"2099-01-01T00:00:00.000Z"}'
run_wrapper api user
MINT_BODY="$MINTED_BODY"
expect_status 0
expect_mints 1
expect_gh_token minted-token
[ ! -e "$CACHE_FILE" ] || fail "token with an unparsed expiry was cached"

# An unwritable cache location costs a mint, never the call.
printf 'not a directory' >"$WORK/not-a-dir"
XDG_CACHE_HOME="$WORK/not-a-dir" run_wrapper api user
expect_status 0
expect_mints 1
expect_gh_token minted-token

# A failed mint never runs gh, which would otherwise act as the user's own login.
rm -rf "$XDG_CACHE_HOME"
MINT_STATUS=22
run_wrapper api user
MINT_STATUS=0
[ "$last_status" != 0 ] || fail "failed mint exited 0"
expect_gh_not_run
grep -Fq 'failed to obtain installation access token' "$WORK/err" || fail "mint failure lacked diagnostic"

MINT_BODY='{"expires_at":"2099-01-01T00:00:00Z"}'
run_wrapper api user
MINT_BODY="$MINTED_BODY"
[ "$last_status" != 0 ] || fail "mint without a token exited 0"
expect_gh_not_run

GITHUB_APP_SECRETS_DIR="$WORK/absent" run_wrapper api user
[ "$last_status" != 0 ] || fail "missing secrets exited 0"
expect_gh_not_run

# Any Setup file the mint needs can be missing. Each case must fail with the
# documented diagnostic naming the file, not a raw `cat:`/`openssl:` error, and
# must never run gh, which would act as the user's own login instead.
for missing in installation-id client-id private-key.pem; do
  partial_secrets="$WORK/secrets-without-${missing%%.pem}"
  rm -rf "$partial_secrets"
  mkdir -p "$partial_secrets"
  for file in client-id installation-id private-key.pem; do
    [ "$file" = "$missing" ] || cp "$SECRETS/$file" "$partial_secrets/"
  done
  expect_secrets_error "$partial_secrets" "$partial_secrets/$missing" "missing $missing"
done
expect_secrets_error "$WORK/absent/secrets" "$WORK/absent/secrets/installation-id" \
  "missing secrets directory"

# A non-numeric installation-id is refused before the mint, the gh call, and any
# cache write: its contents are a path component of the cache file name, so
# `12/../../escape` would otherwise write the token outside the cache directory.
for installation_id in 'abc' '12/../../escape' '7 7'; do
  bad_secrets="$WORK/secrets-${installation_id//[^a-z]/}"
  rm -rf "$bad_secrets"
  mkdir -p "$bad_secrets"
  cp "$SECRETS/client-id" "$SECRETS/private-key.pem" "$bad_secrets/"
  printf '%s' "$installation_id" >"$bad_secrets/installation-id"
  rm -rf "$XDG_CACHE_HOME"
  : >"$MINT_LOG"
  : >"$GH_ARGS_LOG"
  last_status=0
  GITHUB_APP_SECRETS_DIR="$bad_secrets" "$WRAPPER" api user >"$WORK/out" 2>"$WORK/err" \
    || last_status=$?
  [ "$last_status" != 0 ] || fail "installation-id '$installation_id' was accepted"
  expect_gh_not_run
  expect_mints 0
  grep -Fq 'installation-id must be numeric' "$WORK/err" \
    || fail "installation-id '$installation_id' lacked diagnostic: $(cat "$WORK/err")"
  [ ! -e "$XDG_CACHE_HOME" ] \
    || fail "installation-id '$installation_id' wrote a cache: $(find "$XDG_CACHE_HOME" -type f)"
done

# Arguments reach gh verbatim, and gh's exit status is the wrapper's.
run_wrapper issue create --title 'a  b' --body-file 'x y.md' '' '--flag=$HOME'
expect_status 0
[ "$(cat "$GH_ARGS_LOG")" = "$(printf '%s\n' issue create --title 'a  b' --body-file 'x y.md' '' '--flag=$HOME' --end--)" ] \
  || fail "arguments changed on the way to gh: $(cat "$GH_ARGS_LOG")"
run_wrapper --help
[ "$(cat "$GH_ARGS_LOG")" = "$(printf '%s\n' --help --end--)" ] || fail "--help did not reach gh"
GH_STATUS=7
run_wrapper pr view 1
GH_STATUS=0
expect_status 7

# git push: refuses main, detached HEAD, refspecs and other git commands before
# minting; pushes the current branch with upstream otherwise.
# git is a PATH stub too: it records what the push invocation saw, then runs the
# real git, so the stub remote below stays a real push.
REAL_GIT="$(command -v git)"
export REAL_GIT
cat >"$WORK/bin/git" <<'EOF'
#!/usr/bin/env bash
# Test double for git: records a push's argv and environment, then runs real git.
for arg in "$@"; do
  if [ "$arg" = push ]; then
    printf '%s\n' "$@" '--end--' >>"$GIT_LOG"
    printf '%s\n' "${GH_TOKEN:-unset}" >>"$GIT_TOKEN_LOG"
    printf '%s\n' "${GIT_CONFIG_GLOBAL:-unset}|${GIT_CONFIG_NOSYSTEM:-unset}" >>"$GIT_ENV_LOG"
    break
  fi
done
exec "$REAL_GIT" "$@"
EOF
chmod +x "$WORK/bin/git"

REPO="$WORK/repo" ORIGIN="$WORK/origin.git"
git init -q --bare "$ORIGIN"
git init -q "$REPO"
git -C "$REPO" symbolic-ref HEAD refs/heads/main
git -C "$REPO" -c user.name=test -c user.email=test@example.com commit -q --allow-empty -m init
git -C "$REPO" remote add origin "$ORIGIN"


for args in 'git push' 'git push --force' 'git push --force-with-lease'; do
  # shellcheck disable=SC2086 # split the case into words on purpose
  (cd "$REPO" && run_wrapper $args && expect_status 2 && expect_mints 0) || exit 1
  grep -Fq 'refusing to push main' "$WORK/err" || fail "$args on main lacked diagnostic"
done
git -C "$ORIGIN" rev-parse -q --verify refs/heads/main >/dev/null && fail "main reached origin"

git -C "$REPO" switch -q -c feature
for args in 'git push origin HEAD:main' 'git push --tags' 'git status' 'git'; do
  # shellcheck disable=SC2086 # split the case into words on purpose
  (cd "$REPO" && run_wrapper $args && expect_status 2 && expect_mints 0) || exit 1
done
git -C "$ORIGIN" rev-parse -q --verify refs/heads/main >/dev/null && fail "refspec bypassed the main guard"

# Global git config is ignored: a global pre-push hook must not run.
mkdir -p "$HOME/hooks"
printf '#!/bin/sh\ntouch "%s"\n' "$WORK/global-hook-ran" >"$HOME/hooks/pre-push"
chmod +x "$HOME/hooks/pre-push"
git config --file "$HOME/.gitconfig" core.hooksPath "$HOME/hooks"
# A local push refspec cannot redirect the branch onto main.
git -C "$REPO" config remote.origin.push refs/heads/feature:refs/heads/main
(cd "$REPO" && run_wrapper git push && expect_status 0) || exit 1
git -C "$ORIGIN" rev-parse -q --verify refs/heads/feature >/dev/null || fail "feature was not pushed"
[ "$(cat "$GIT_TOKEN_LOG")" = minted-token ] \
  || fail "push did not carry the App token: $(cat "$GIT_TOKEN_LOG")"
[ "$(cat "$GIT_ENV_LOG")" = '/dev/null|1' ] \
  || fail "push did not isolate git config: $(cat "$GIT_ENV_LOG")"
[ "$(cat "$GIT_LOG")" = "$(printf '%s\n' -C "$REPO" \
  -c credential.helper= \
  -c 'credential.https://github.com.helper=!gh auth git-credential' \
  -c credential.https://github.com.username=x-access-token \
  push --set-upstream origin "refs/heads/feature:refs/heads/feature" --end--)" ] \
  || fail "unexpected git push invocation:"$'\n'"$(cat "$GIT_LOG")"
[ "$(git -C "$REPO" rev-parse --abbrev-ref 'feature@{upstream}')" = origin/feature ] || fail "upstream not set"
[ ! -e "$WORK/global-hook-ran" ] || fail "global git config was used"
git -C "$ORIGIN" rev-parse -q --verify refs/heads/main >/dev/null && fail "remote.origin.push mapped the branch onto main"
git -C "$REPO" config --unset remote.origin.push

git -C "$REPO" -c user.name=test -c user.email=test@example.com commit -q --allow-empty --amend -m rewritten
(cd "$REPO" && run_wrapper git push --force-with-lease && expect_status 0) || exit 1
[ "$(git -C "$ORIGIN" rev-parse refs/heads/feature)" = "$(git -C "$REPO" rev-parse HEAD)" ] \
  || fail "--force-with-lease did not update origin"

git -C "$REPO" switch -q --detach
(cd "$REPO" && run_wrapper git push && expect_status 2 && expect_mints 0) || exit 1

echo 'gh-app test passed'
