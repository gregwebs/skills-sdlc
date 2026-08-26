---
name: github-app
description: Read and update GitHub issues, push branches, and create or update pull requests, issues, and comments through App-authenticated scripts. Use for GitHub reads or writes, including "open a PR", "send a pull request", "file/read/update an issue", "comment on the PR/issue", "mark an issue as blocked by / blocking another", or an App-authenticated push.
user-invocable: true
allowed-tools:
  - Read
  - Write
  - Bash(./scripts/*)
  - Bash(git push *)
  - Bash(git rev-parse *)
  - Bash(git branch -c *)
  - Bash(git switch *)
  - Bash(git status *)
  - Bash(git commit *)
---

# /github-app — GitHub PR / issue / comment via the App scripts

The stable `./scripts/gh-app.sh` dispatcher delegates to implementation scripts
bundled with this skill. Those scripts hit the GitHub REST API authenticated as
a GitHub App installation. They mint their own short-lived (~9 min) token per
call — nothing to log into. Each script prints
the resulting `html_url` on success; **always relay that URL back to the user.**

These are **outward-facing actions** (they publish to GitHub and notify people).
This skill only runs when explicitly requested by the user- this includes explicitly invoking another skill that explicitly invokes this skill.
Confirm the target (repo, branch, title) before running if there's any ambiguity.

## Setup reference

Two pieces of metadata are required that live outside of this repo.:
In `~/.config/github-app/ (Override with `GITHUB_APP_SECRETS_DIR`) are:

- `client-id` — the App's client ID (used as the JWT `iss` claim)
- `installation-id` - the installation scope id
- `private-key.pem` — the App's private key (signs the JWT)

These files should only be accessible to the user (permission 0600).

If these files are missing, the skill is not configured.
If the skill needs to be used, prompt the user to add these files.

## The scripts

These scripts are located relative to this SKILL.md file, which is probably
$HOME/.agents/skills/github-app/scripts/*.sh

| Action | Dispatcher command | Required args |
|---|---|---|
| Push a branch | `./scripts/gh-app.sh push` | none |
| Open a PR | `./scripts/gh-app.sh pr-create` | `--base BASE --head HEAD --title TITLE` |
| Read an issue | `./scripts/gh-app.sh issue-get` | `--issue NUMBER` |
| File an issue | `./scripts/gh-app.sh issue-create` | `--title TITLE` |
| Link sub-issue | `./scripts/gh-app.sh issue-sub-add` | `--parent NUMBER --child NUMBER` |
| Link blocked-by | `./scripts/gh-app.sh issue-block-add` | `--blocked NUMBER --blocker NUMBER` |
| Remove blocked-by | `./scripts/gh-app.sh issue-block-remove` | `--blocked NUMBER --blocker NUMBER` |
| List blocking edges | `./scripts/gh-app.sh issue-block-list` | `--issue NUMBER` |
| Comment on issue/PR | `./scripts/gh-app.sh issue-comment` | `--issue NUMBER` (PRs count as issues here) |

Common optional args: `--repo OWNER/REPO`, `--body TEXT`, `--body-file FILE`.
Issue creation also takes repeatable `--label LABEL`.

`--repo` defaults to this directory's `github.com` origin remote — **omit it**
unless acting on a different repo.

## Recording blocked-by / blocking dependencies

GitHub stores this as a single directed edge: "issue A blocks issue B" is
recorded as "B is blocked_by A". There is no separate write for the "blocking"
direction — pick the end that names the issue that **cannot start**:

```
./scripts/gh-app.sh issue-block-add --blocked 42 --blocker 40
```

reads as "issue 42 is blocked by issue 40". `issue-block-list --issue N` reads
the edge from either end (`blocked by:` / `blocking:`), and
`issue-get --issue N --format md` also shows both lines for that issue.

To undo a link, pass the same `--blocked`/`--blocker` pair to
`issue-block-remove`:

```
./scripts/gh-app.sh issue-block-remove --blocked 42 --blocker 40
```

## Permission-efficient command shapes

Use the repository dispatcher directly. Do not prefix it with `PATH=...`, call
the GitHub API with raw `curl`, or substitute `gh`. The dispatcher and git
credential helper select `/opt/homebrew/opt/curl/bin/curl` internally when it
exists, so the command remains compatible with a narrow persistent approval
rule.

Stable command prefixes are:

```text
./scripts/gh-app.sh
git push
```

GitHub requires network access. In a restricted Codex sandbox, request network
escalation on the first attempt with the narrow dispatcher or `git push` prefix;
do not first run a command that is expected to fail DNS and then retry it. A
previously persisted approval can then match without another prompt.

Use the `github-actions-ci` skill for check status and waiting; do not use raw
Actions API calls from this skill.

## Body text: always use `--body-file`, never `--body`

Write the body to a temp file, then pass `--body-file`. Do this even for
one-liners.

In Codex, create these temp body files with `exec_command` and a direct write
under `/private/tmp` (for example, `printf '%s\n' 'body text' >
/private/tmp/pr-body.md`). Do **not** use `apply_patch` for `/private/tmp`
body files; `apply_patch` is for repository edits and can trigger an
unnecessary approval prompt for absolute paths outside the workspace.

Do **not** ask the user for permission before creating these temp body files
under `/private/tmp`. They are required workflow scratch files, they are outside
the repo, and `/private/tmp` is an allowed writable temp location in Codex.
Only ask for approval if the GitHub action itself is ambiguous or if a command
requires escalated permissions.

Reasons:

- This sandbox mangles `!` into `\!` in Bash-tool arguments and heredocs, so an
  inline `--body "...!..."` corrupts the body. The Write tool is unaffected.
- Multiline / Markdown bodies with backticks, quotes, and `$` are painful to
  quote safely on a command line.

```
# 1. Write the body to /private/tmp/pr-body.md
# 2. Pass it
./scripts/gh-app.sh pr-create --base main --head my-branch \
  --title "..." --body-file /private/tmp/pr-body.md
```

## Opening a PR

1. **The head branch must already be pushed to origin** — the API resolves
   `--head` against the remote. If it isn't, push first (the repo's git config
   pushes via the same App credentials). Confirm with the user before pushing if
   they haven't asked.
2. `--base` is usually `main`; `--head` is the current feature branch
   (`git rev-parse --abbrev-ref HEAD`). Use `./scripts/gh-app.sh push`; its
   bundled credential helper handles App authentication and curl selection.
3. Follow repository instructions or conventions for PR Body contents.
4. Write the body file, run the script, relay the printed PR URL.

## Filing an issue

```
./scripts/gh-app.sh issue-create --title "Title" \
  --body-file "$TMPDIR/issue-body.md" --label bug --label "needs triage"
```
`--label` repeats per label. Relay the printed issue URL.

## Commenting on an issue or PR

GitHub treats PR conversation comments as issue comments, so the **same script
and PR/issue number** work for both:
```
./scripts/gh-app.sh issue-comment --issue 1 --body-file "$TMPDIR/comment.md"
```

## Failure modes

- **`403 Resource not accessible by integration`** — the installation lacks the
  needed permission scope (`Contents`/`Pull requests`/`Issues: write`). Granting
  it in the App settings also requires the owner to *accept* the upgraded grant
  at https://github.com/settings/installations. Report this to the user; you
  can't fix it from here.
- **`--repo required (not in a github.com git repo)`** — run from the repo, or
  pass `--repo OWNER/REPO`.
- **`422` on PR create** — usually the head branch isn't pushed, a PR already
  exists for that branch, or base == head. Check the error body the script
  prints to stderr.
- These scripts use `curl`/`jq` (not `gh`) on purpose: `gh` fails TLS against
  `api.github.com` in this sandbox. They automatically prefer the Homebrew curl
  required on this host. Don't add a `PATH` prefix or substitute `gh`.
- **`404`/`415` from `issue-block-add`/`issue-block-remove`/`issue-block-list`** —
  the pinned REST API version (`2022-11-28` in `lib.sh`) may not serve the
  issue-dependencies endpoints. Retry with
  `GH_APP_API_VERSION=2026-03-10 ./scripts/gh-app.sh ...`; if that fixes it,
  update the default in `lib.sh` instead of setting the variable every call.
