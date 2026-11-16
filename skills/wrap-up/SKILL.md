---
name: wrap-up
description: "After implementing, commit and finish your work"
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

Ask the user whether to create tickets/issues for out of scope work brought up:
* Unrelated defects
* Small related features/enhancements
* Improving the software development process- altering documentation or skills to streamline agent usage
* A new tool or enhancing existing tools that would encompass ad-hoc code that was written to help analyze/test and then discarded

If a `/cleanup` has not been performed,
* If there is a /pull-request tell the user you will run `/cleanup` once it is merged, and monitor the /pull-request for a merge.
* Otherwise ask the user if they want you to `/cleanup`
