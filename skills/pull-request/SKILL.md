---
name: pull-request
description: Send a Github Pull Request of your work. Normally done after completing a ticket/issue. Check on CI and follow up on any failures.
metadata:
  short-description: Send a Github Pull Request and check on CI
---

## Definitions

PR=Pull Request

## Access

Access Github if the capability is available and the user instructs it.
* skills
  * /github-app skill: create the PR with `./scripts/gh-app.sh pr-create`
  * /github-actions-ci: check on CI with its bundled helper
* Github API or MCP
* github CLI 

## Branching

Update the default branch to the latest from the origin.
If you were already on the default branch, branch from there.
Otherwise, check if the current branch has been merged into the updated default (could be a squash merge).
If it has been merged, then branch off the updated default (move your changes there).
Otherwise, branch off of the current branch. First ensure the updated default is merged into it.

If you are working on a sub issue of a parent issue, then look for an active parent branch to use as the base.
All sub issues that do not have dependencies should use the discovered default branch or the parent branch as their base branch.

If the issue requires an existing PR to be merged, then the base branch will be the branch for that PR.
Create it as a [Stacked PR](https://github.github.com/gh-stack/introduction/overview/).

## Description

For the PR description, use the `/document-changes` skill.
If the PR resolves an issue, ensure it is auto-closed by using the "Resolves" keyword: "Resolves #10".

When you write a commit message, follow these 7 rules:
Rule 1: Separate the subject line from the body with a single blank line.
Rule 2: Limit the subject line to 50 characters (72 is the absolute hard limit).
Rule 3: Capitalize the first letter of the subject line.
Rule 4: Do not end the subject line with a period.
Rule 5: Use the imperative mood in the subject line (e.g., "Fix bug," "Add feature,"
        not "Fixed" or "Adds"). Test formula: It must complete the sentence: "If applied,
        this commit will [your subject line here]".
Rule 6: Wrap the body text manually at 72 characters to prevent Git formatting issues.
Rule 7: Use the body to explain what and why vs. how. Assume the code explains the how;
        the message must explain the context and reasoning.

## Check on CI

When CI access is available and the user requested PR follow-up, check the CI run for the PR.
If there are CI failures, investigate them and change the PR.

If the CI failures are not related to your work, suggest filing an issue or otherwise fixing them separately.
If they are related to your work, and the changes needed are not minor, ensure proper usage of standard flow for code changes.
