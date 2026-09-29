---
name: github-actions-ci
description: Monitor, wait for, diagnose, rerun, and cancel a repository's GitHub Actions checks and runs. Use the bundled helper for check status and the GitHub App helper for rerun and cancel. Use after pushing or opening/updating a PR, when asked to watch CI or verify a named job such as Playwright, or when a GitHub Actions check fails.
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/check-ci-runs.sh *)
---

# GitHub Actions CI

Use the bundled helper as the single interface for check-run status. It selects
the host-compatible curl binary, resolves the repository and commit, and uses
GitHub App authentication when local App credentials are available.

## Monitor checks

Run one of these stable command shapes from the repository root:

```sh
${CLAUDE_SKILL_DIR}/scripts/check-ci-runs.sh
${CLAUDE_SKILL_DIR}/scripts/check-ci-runs.sh --wait
${CLAUDE_SKILL_DIR}/scripts/check-ci-runs.sh --job JOB --wait
${CLAUDE_SKILL_DIR}/scripts/check-ci-runs.sh --job JOB --wait COMMIT
```

The stable approval prefix is:

```text
${CLAUDE_SKILL_DIR}/scripts/check-ci-runs.sh
```

## Rerun failed jobs

After confirming a failure is transient or unrelated to the change, rerun the
failed jobs for the workflow run with the GitHub App helper:

```sh
./scripts/gh-app.sh actions-rerun-failed RUN_ID
```

The stable approval prefix is:

```text
./scripts/gh-app.sh
```

Use the workflow run ID from the failed job URL. This reruns only failed jobs;
it does not create a new workflow run or rerun successful jobs. Monitor the
replacement checks with
`${CLAUDE_SKILL_DIR}/scripts/check-ci-runs.sh --wait COMMIT`.

## Cancel runs

Cancel a workflow run by its run ID with the GitHub App helper:

```sh
./scripts/gh-app.sh actions-cancel RUN_ID
```

Use `actions-force-cancel` when a normal cancel is not taking effect:

```sh
./scripts/gh-app.sh actions-force-cancel RUN_ID
```

Both share the `./scripts/gh-app.sh` stable approval prefix as rerun. Get the
run ID from the failed job URL. Cancellation is destructive: only cancel a run
when the user has asked, and confirm the run ID first.

GitHub requires network access. In a restricted Codex sandbox, request network
escalation on the first call using that narrow prefix. Do not probe with raw
`curl` or first run the helper without network access when DNS failure is
expected. A persisted prefix approval can then match later invocations without
another prompt.

With `--wait`, keep the process running and poll its existing execution session
at intervals no longer than 30 seconds so the user continues to receive timely
updates. Do not start duplicate monitors. Authenticated polling defaults to ten
seconds; the helper backs off to sixty seconds when App credentials are absent
to respect GitHub's anonymous rate limit. When no check runs are found yet, the
helper waits up to `CI_ABSENT_GRACE_SECONDS` (default 120s) before concluding
that no GitHub Actions checks apply to the commit.

Exit status means:

- `0`: every selected check completed successfully, **or** the helper
  determined that no GitHub Actions checks apply to this commit at all. Read
  the stderr line to tell which — a "no GitHub Actions workflows configured"
  or "no GitHub Actions checks apply to `<sha>`" message means the latter.
- `1`: at least one selected check completed unsuccessfully.
- `2`: selected checks are pending or undetermined when not using `--wait`.

Always relay the job URL printed by the helper.

## No CI configured

When the helper's stderr reports that no GitHub Actions checks apply (exit
`0` with no job listing on stdout), tell the user the PR/commit has no
GitHub Actions CI rather than saying "CI passed" — there is nothing to point
a job URL at. Stop there: do not rerun the helper, start `--wait` again, or
otherwise keep monitoring a commit that has nothing to report.

## Handle results

On success, run the unfiltered helper once to report the complete final CI
state when the repository workflow requires all jobs to pass.

On failure:

1. Open the printed job URL or use the GitHub App read helpers where they cover
   the needed metadata.
2. Identify the first substantive failing step; ignore teardown noise caused by
   the failure.
3. Reproduce with the repository's documented local command when the host
   supports it.
4. Make only in-scope changes, run the relevant local checks, push, and wait for
   the replacement CI run.

For CI architecture, artifacts, and project specific troubleshooting, create
and update project specific documentation rather than duplicating it here.
