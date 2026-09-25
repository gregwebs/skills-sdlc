---
name: wrap-up
description: "After implementing, commit and push up work for final review"
---

Ensure you are on a branch at the apropriate location.
This is usually the tip of main.
Do a fetch of the origin repo to see if there have been updates.

Commit your work.
Squash your commits down to a concise history useful for future viewers of history (usually just 1 commit).
Use the `/document-changes` skill to help record your changes in commit messages and pull requests.

Do the following if your instructions authorize/direct it and the capability is available.
* Generate a `/pull-request`
* Watch for CI success

For a multi-commit Pull Request, generate a combined commit message that can be used in a squash merge.
When fixing CI failures, if the PR has not yet been reviewed, continue to squash commits together and force push the branch.
If the PR has been reviewed, generate a single squash commit message to be used when the PR is merged.

Ask the user whether to create tickets/issues for:
* Out of scope defects seen during implementation
* New features/enhancements brought up during implementation
