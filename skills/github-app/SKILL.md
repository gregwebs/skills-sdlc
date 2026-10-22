---
name: github-app
description: Read, update, assign, and transfer GitHub issues, push branches (including force push), create or update pull requests, issues, and comments, and record issue dependencies and sub-issues, all as a GitHub App through the gh CLI. Use for GitHub reads or writes, including "open a PR", "send a pull request", "file/read/update/assign/transfer an issue", "comment on the PR/issue", "mark an issue as blocked by / blocking another", or an App-authenticated push (with --force when asked).
user-invocable: true
allowed-tools:
  - Read
  - Write
  - Bash(${CLAUDE_SKILL_DIR}/scripts/gh-app.sh *)
  - Bash(${CLAUDE_SKILL_DIR}/scripts/gh-app-issue-dependency.sh *)
  - Bash(${CLAUDE_SKILL_DIR}/scripts/gh-app-issue-sub-issue.sh *)
  - Bash(git rev-parse *)
  - Bash(git remote get-url *)
  - Bash(git branch -c *)
  - Bash(git switch *)
  - Bash(git status *)
  - Bash(git commit *)
---

# /github-app — GitHub as the App, through `gh`

`${CLAUDE_SKILL_DIR}/scripts/gh-app.sh` runs the real `gh` CLI as a GitHub App
installation. It exports an installation token as `GH_TOKEN` and passes your
arguments to `gh` unchanged. Flags, output, exit codes, and `--help` are
`gh`'s own. When a command prints a URL — creating, editing or transferring
an issue or PR — **always relay it back to the user.** `${CLAUDE_SKILL_DIR}` is
the directory containing this SKILL.md.

These are **outward-facing actions** (they publish to GitHub and notify people).
This skill only runs when explicitly requested by the user- this includes explicitly invoking another skill that explicitly invokes this skill.
Confirm the target (repo, branch, title) before running if there's any ambiguity.

## Guardrails

`gh` can do anything the token allows, so these rules are the guard:

- Ask the user before acting on a repository outside the current project.
- Read the target project's `AGENTS.md` and `CONTRIBUTING.md` first and follow
  their restrictions.
- The App's granted scopes are the hard ceiling: `write` on `actions`,
  `contents`, `issues`, `pull_requests`, and `workflows`; the remaining 20
  scopes are read-only. That still allows deleting branches and editing
  workflows: it is a ceiling, not a guard.
- Never move or delete the default branch through `gh` (for example
  `gh api …/git/refs/heads/main` or `gh repo sync --force`); the `git push`
  guard does not cover it.
- Report a `403` to the user. Never work around it.
- Never run bare `gh`: it acts as the user, not the App.

## Setup reference

Three files live outside this repo, in `~/.config/github-app/` (override with
`GITHUB_APP_SECRETS_DIR`):

- `client-id` — the App's client ID (used as the JWT `iss` claim)
- `installation-id` — the installation scope id
- `private-key.pem` — the App's private key (signs the JWT)

These files should only be accessible to the user (permission 0600).

If these files are missing, the skill is not configured.
If the skill needs to be used, prompt the user to add these files.

The token is minted for you and cached in `${XDG_CACHE_HOME:-~/.cache}/gh-app/`
until five minutes before it expires. You never handle the private key.
Requires `gh`, `jq`, `curl`, and OpenSSL.

## Commands

| Action | Command |
|---|---|
| Push the current branch | `${CLAUDE_SKILL_DIR}/scripts/gh-app.sh git push` |
| Open a PR | `${CLAUDE_SKILL_DIR}/scripts/gh-app.sh pr create --base BASE --head HEAD --title TITLE --body-file FILE` |
| Update a PR | `${CLAUDE_SKILL_DIR}/scripts/gh-app.sh pr edit NUMBER --title TITLE --body-file FILE` |
| Read an issue | `${CLAUDE_SKILL_DIR}/scripts/gh-app.sh issue view NUMBER --json number,title,state,labels,body` |
| File an issue | `${CLAUDE_SKILL_DIR}/scripts/gh-app.sh issue create --title TITLE --body-file FILE` |
| Update an issue | `${CLAUDE_SKILL_DIR}/scripts/gh-app.sh issue edit NUMBER --body-file FILE` |
| Assign an issue | `${CLAUDE_SKILL_DIR}/scripts/gh-app.sh issue edit NUMBER --add-assignee USER` |
| Transfer an issue | `${CLAUDE_SKILL_DIR}/scripts/gh-app.sh issue transfer NUMBER OWNER/REPO` |
| Comment on an issue or PR | `${CLAUDE_SKILL_DIR}/scripts/gh-app.sh issue comment NUMBER --body-file FILE` |
| Link blocked-by | `${CLAUDE_SKILL_DIR}/scripts/gh-app-issue-dependency.sh add --blocked NUMBER --blocker NUMBER` |
| Remove blocked-by | `${CLAUDE_SKILL_DIR}/scripts/gh-app-issue-dependency.sh remove --blocked NUMBER --blocker NUMBER` |
| List blocking edges | `${CLAUDE_SKILL_DIR}/scripts/gh-app-issue-dependency.sh list --issue NUMBER` |
| Link sub-issue | `${CLAUDE_SKILL_DIR}/scripts/gh-app-issue-sub-issue.sh add --parent NUMBER --child NUMBER` |

Anything else `gh` does, run through `${CLAUDE_SKILL_DIR}/scripts/gh-app.sh`
with `gh`'s own arguments, for example `api`, `pr view`, or `run view`. Use the
`github-actions-ci` skill for check status and waiting.

Commands act on the repository of the directory they run in, which `gh`
resolves for itself.

With more than one remote (for example a fork with `upstream`), that resolution
does not follow the remote `git push` uses: with no default set,
`{owner}/{repo}` and `issue create` resolve to `upstream`, so a write lands in
the wrong repository. Name the repository explicitly instead. Use `origin`, the
remote `git push` uses:

```text
git remote get-url origin
```

That prints `git@github.com:OWNER/REPO.git` or
`https://github.com/OWNER/REPO.git`, possibly without the trailing `.git`;
`OWNER/REPO` is the part after the host.
Pass it as `--repo OWNER/REPO` to the `gh` subcommands that accept it and to
both issue scripts, and use a `repos/OWNER/REPO/...` path with `gh api`, which
has no `--repo`. Pass `--repo` for another repository only when the user asked
for it, and ask first (see Guardrails). `repo set-default --view` shows only a
default that was set explicitly, not what `gh` would otherwise resolve; never
run `repo set-default` without an argument, because it fails when not run
interactively. Run `repo set-default OWNER/REPO` only when the user asks for
it, because it writes `remote.<name>.gh-resolved` into the repository's config.

Other skills call the same scripts as
`${CLAUDE_SKILL_DIR}/../github-app/scripts/gh-app.sh` (and likewise for the two
issue scripts). Skill directories are siblings both in this repo and when
installed.

## Recording blocked-by / blocking dependencies

`gh` has no command for issue dependencies or sub-issues, so two bundled
scripts call `gh api` and resolve issue numbers to the database ids GitHub
needs.

GitHub stores a dependency as a single directed edge: "issue A blocks issue B"
is recorded as "B is blocked_by A". Name the issue that **cannot start** with
`--blocked`:

```
${CLAUDE_SKILL_DIR}/scripts/gh-app-issue-dependency.sh add --blocked 42 --blocker 40
```

reads as "issue 42 is blocked by issue 40". `list --issue N` prints both
directions (`blocked by:` / `blocking:`). To undo a link, pass the same pair to
`remove`.

## Permission-efficient command shapes

Run the scripts directly. Do not prefix them with `PATH=...` or call the GitHub
API with raw `curl`. Stable command prefixes are:

```text
${CLAUDE_SKILL_DIR}/scripts/gh-app.sh
${CLAUDE_SKILL_DIR}/scripts/gh-app-issue-dependency.sh
${CLAUDE_SKILL_DIR}/scripts/gh-app-issue-sub-issue.sh
```

GitHub requires network access. In a restricted Codex sandbox, request network
escalation on the first attempt with one of these prefixes; do not first run a
command that is expected to fail DNS and then retry it. A previously persisted
approval can then match without another prompt.

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
${CLAUDE_SKILL_DIR}/scripts/gh-app.sh pr create --base main --head my-branch \
  --title "..." --body-file /private/tmp/pr-body.md
```

## Opening a PR

1. **The head branch must already be pushed to origin.** If it isn't, push it
   first with `${CLAUDE_SKILL_DIR}/scripts/gh-app.sh git push`. Confirm with
   the user before pushing if they haven't asked.
2. `--base` is usually `main`; `--head` is the current feature branch
   (`git rev-parse --abbrev-ref HEAD`).
3. Follow repository instructions or conventions for PR Body contents.
4. Write the body file, run the command, relay the printed PR URL.

## Pushing and force pushing

`${CLAUDE_SKILL_DIR}/scripts/gh-app.sh git push` pushes the current branch to
`origin` and sets its upstream. It ignores your global git configuration and
authenticates as the App for that one command. It refuses `main`, a detached
HEAD, and any argument other than these force flags:

```
${CLAUDE_SKILL_DIR}/scripts/gh-app.sh git push --force
${CLAUDE_SKILL_DIR}/scripts/gh-app.sh git push --force-with-lease
```

Force push rewrites remote history and is destructive — run it only when the
user has explicitly asked, and confirm the branch first. Prefer
`--force-with-lease`, which refuses if the remote branch has moved since your
last fetch.

## Filing an issue

```
${CLAUDE_SKILL_DIR}/scripts/gh-app.sh issue create --title "Title" \
  --body-file "$TMPDIR/issue-body.md" --label bug --label "needs triage"
```
`--label` repeats per label. Relay the printed issue URL.

## Transferring an issue

```
${CLAUDE_SKILL_DIR}/scripts/gh-app.sh issue transfer 42 OWNER/DESTINATION
```

Only issues (not PRs) can move. Both repositories must share an owner, and the
destination must have issues enabled. The installation must cover both
repositories. Labels and milestones carry over only where the destination has
matching ones. The issue number may change: relay the printed URL. If the
command fails, check where the issue now is (read-only) before retrying,
because GitHub may already have moved it.

## Assigning an issue

```
${CLAUDE_SKILL_DIR}/scripts/gh-app.sh issue edit 42 --add-assignee alice,bob
${CLAUDE_SKILL_DIR}/scripts/gh-app.sh issue edit 42 --remove-assignee alice
```

`--add-assignee` adds to the current assignees; it does not replace them.
Assignees must be users with access to the repo. PRs take the same flags via
`pr edit`.

## Commenting on an issue or PR

```
${CLAUDE_SKILL_DIR}/scripts/gh-app.sh issue comment 1 --body-file "$TMPDIR/comment.md"
```

GitHub treats PR conversation comments as issue comments, so an issue number or
a PR number works here.

## Failure modes

- **`403 Resource not accessible by integration`** — the installation lacks the
  needed permission scope. Granting it in the App settings also requires the
  owner to *accept* the upgraded grant at
  https://github.com/settings/installations. Report this to the user; you can't
  fix it from here. A cached token keeps its old scopes: once the grant is
  accepted, delete `${XDG_CACHE_HOME:-~/.cache}/gh-app/token.*` so the next
  call mints a new one.
- **`401 Bad credentials`** — the cached token is no longer valid: the App was
  reinstalled or the token revoked, or this machine's clock is more than five
  minutes behind GitHub's. Delete `${XDG_CACHE_HOME:-~/.cache}/gh-app/token.*`
  and retry; the next call mints a new token. If it persists, report it.
- **`gh-app-token: failed to obtain installation access token`** — the Setup
  reference files are missing or wrong, or GitHub is unreachable. Report it; do
  not fall back to bare `gh`.
- **`422` on `pr create`** — usually the head branch isn't pushed, a PR already
  exists for that branch, or base == head. Read `gh`'s error output.
- Any other failure is `gh`'s own error and exit code. Report it as-is; do not
  route around it with `curl`.
