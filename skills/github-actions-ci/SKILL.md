---
name: github-actions-ci
description: Monitor, wait for, diagnose, rerun, and cancel a repository's GitHub Actions checks and runs. Use the bundled helper for check status and the GitHub App wrapper for rerun and cancel. Use after pushing or opening/updating a PR, when asked to watch CI or verify a named job such as Playwright, or when a GitHub Actions check fails.
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

## Several check runs share a name

One commit can carry more than one check run per workflow. A repository that
triggers CI on both `push` and `pull_request` runs each workflow twice, so the
same commit has two `build-and-test` check runs from two workflow runs, and
GitHub's own PR rollup fails the commit when **either** fails
(`mergeStateStatus: UNSTABLE`).

The helper reports every one of them and judges every one; when a name repeats,
it prints the workflow run id so the two triggers stay distinguishable:

```text
build-and-test: completed (success) [run 41197892063]
https://github.com/o/r/actions/runs/41197892063/job/…
build-and-test: completed (failure) [run 41197885241]
https://github.com/o/r/actions/runs/41197885241/job/…
```

It never collapses a repeated name to the newest run. Doing that once reported a
green PR while the `push` run for the same commit had failed — the two runs were
six seconds apart, so "latest" was the passing one.

For a PR, `gh pr view <number> --json statusCheckRollup` lists the same check
runs and is the second opinion to read before acting: a difference between it
and the helper means a check run is attached to the commit but not selected by
the PR, or the reverse. Read the run ids before rerunning anything.

## Rerun failed jobs

After confirming a failure is transient or unrelated to the change, rerun the
failed jobs for the workflow run with the GitHub App wrapper, which runs `gh` as
the App:

```sh
${CLAUDE_SKILL_DIR}/../github-app/scripts/gh-app.sh run rerun RUN_ID --failed
```

The stable approval prefix is:

```text
${CLAUDE_SKILL_DIR}/../github-app/scripts/gh-app.sh
```

Use the workflow run ID from the failed job URL. This reruns only failed jobs;
it does not create a new workflow run or rerun successful jobs. Monitor the
replacement checks with
`${CLAUDE_SKILL_DIR}/scripts/check-ci-runs.sh --wait COMMIT`.

## Cancel runs

Cancel a workflow run by its run ID with the GitHub App wrapper:

```sh
${CLAUDE_SKILL_DIR}/../github-app/scripts/gh-app.sh run cancel RUN_ID
```

Add `--force` when a normal cancel is not taking effect:

```sh
${CLAUDE_SKILL_DIR}/../github-app/scripts/gh-app.sh run cancel RUN_ID --force
```

Both share the rerun command's stable approval prefix. Get the
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

A repeated name counts as several selected checks: `--job build-and-test`
judges both triggers' runs, so one failing is exit `1` even when the other
passed.

Always relay the job URL printed by the helper.

## No CI configured

When the helper's stderr reports that no GitHub Actions checks apply (exit
`0` with no job listing on stdout), tell the user the PR/commit has no
GitHub Actions CI rather than saying "CI passed" — there is nothing to point
a job URL at. Stop there: do not rerun the helper, start `--wait` again, or
otherwise keep monitoring a commit that has nothing to report.

## Handle results

On success, run the unfiltered helper once to report the complete final CI
state when the repository workflow requires all jobs to pass. "Complete" means
every check run the helper lists, repeated names included — do not report a
commit green from a `--job` run alone, and on a PR cross-check
`gh pr view <number> --json statusCheckRollup` before calling it green.

On failure:

1. Open the printed job URL, or read the job log with
   `${CLAUDE_SKILL_DIR}/../github-app/scripts/gh-app.sh run view --job JOB_ID --log`.
2. Identify the first substantive failing step; ignore teardown noise caused by
   the failure.
3. Reproduce with the repository's documented local command when the host
   supports it.
4. Make only in-scope changes, run the relevant local checks, push, and wait for
   the replacement CI run.

For CI architecture, artifacts, and project specific troubleshooting, create
and update project specific documentation rather than duplicating it here.
