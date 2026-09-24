---
name: update-working-copy
description: Fetch the latest from the remote. Update the working branch or switch to main if the branch is defunct.
---

The defaults we use are remote=origin, branch=main. However, these may have different values in this project.

Make sure the repository is up to date- fetch the latest from the remote.

If the remote branch is ahead of the local branch, pull that in.

If you are on a branch that is not `main`:
* If your branch commits are included in the tip of `main` (directly or via rebase or squashing), switch to the tip of `main`
* If your branch is behind the tip of `main`, ask the user whether you should merge that in or move to that.
