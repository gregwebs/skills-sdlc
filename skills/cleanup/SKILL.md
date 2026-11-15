---
name: cleanup
description: Clean up after merged work. Remove the local branch and its git worktree, delete the remote branch, then delete temp files, containers, images, and leftover test processes that the work left behind.
---

# Cleanup after merge

Reclaim what a finished branch consumed. Discover the footprint first, then
delete. Every deletion below is irreversible: confirm the work is merged and
that nothing else depends on what you are removing.

## Confirm the work is merged

Discover the remote and default branch from repository instructions and
`git remote show`, rather than assuming `origin` and `main`.

Fetch, then verify the branch landed in the default branch. A squash or rebase
merge leaves commit hashes unmatched, so check for the change itself:
`git log <default> --oneline --grep`, the PR's merged state, or a diff of the
branch against the default branch. `git branch --merged` alone is not proof.

Stop and report if the branch is unmerged, has an open PR, or is the base of
another branch. Do not clean up work that can still be needed.

## Remove the branch and its worktree

Start the working copy elsewhere. If the current checkout is the branch being
removed, switch to the updated default branch first; git refuses to delete a
branch that is checked out.

```sh
git worktree list
git worktree remove <worktree-path>
git worktree prune
```

`git worktree remove` refuses a dirty worktree. Inspect what is uncommitted,
and only pass `--force` when the user authorizes discarding it. Never remove a
worktree belonging to another branch or another agent's active task.

Delete the local branch with the safe form, so git itself refuses an unmerged
branch:

```sh
git branch -d <branch>    # -D only if a squash merge makes the check moot
```

Delete the remote branch with the configured access path, then verify:

```sh
git push <remote> --delete <branch>            # or the github-app wrapper's push
git ls-remote --heads <remote> <branch>        # expect no output
```

Some projects keep the branch for a stacked PR's base, or delete remotely on
merge already. Check before pushing a delete.

## Remove temp files

Look for what this work created, and keep the scope to it:

* workflow artifacts such as task briefs, implementation plans, results, and
  review notes
* scratch directories, coverage and build output outside version control
* editor and agent caches keyed to the branch or worktree path
* the worktree directory itself, once git no longer tracks it

Use the repository's ignore rules and modification times to find candidates,
and list them before deleting. Leave user data, dependencies to be reinstalled
deliberately, and artifacts belonging to other branches. Ask when a path is
ambiguous or outside the repository.

## Stop leftover processes and containers

Enumerate processes and containers.
For any that you are certain belong to your session, kill/stop them.
If you are unsure, report them to the operator instead.

Remove test images created by this session.

Never remove shared base images, containers or images of other worktrees and
active agents, or volumes holding data. Volume and system-wide prunes
(`docker volume prune`, `docker system prune`) need explicit approval.

Prefer the project's own teardown commands over raw `docker` commands when the
repository documents one.

## Report

Summarize what was removed: branch and worktree, remote branch, temp files,
containers, images, and killed processes. List what you deliberately left,
with the reason, and anything needing an operator decision.
