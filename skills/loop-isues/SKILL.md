---
name: loop-issues
description: Loop through issues/tickets autonomously, using one fresh subagent per issue in sequence.
---

Work through a series of issues until completed or blocked.

Use `/orchestration` to manage subagents.
Keep the coordinator focused on triage and handoffs; delegate investigation and
implementation.

## Looping through issues

Run only one issue at a time, including its child workflows.

When an issue is completed, inform the user without waiting for a response.
Check for quota exhaustion and operator stop instructions before
starting another issue.

If access, quota, configuration, etc is blocking you from finishing an issue,
stop rather than attempting every issue against the same blocker.

## Issues to work

The skill invoker must tell you what issues to work.
Iterate through issues ensuring that you implement dependencies first.

## Working an issue

Use a separate branch/worktree for each issue.
Use `/orchestration` to start a fresh subagent without inherited conversation history.
Give it the issue link, repository and artifact paths, relevant constraints, and this assignment:

1. Use `/implement-simple` or an alternative specified by the user to implement and finish the issue.
2. Update the issue's progress artifact incrementally. Return a concise status:
   completed, needs operator help, complicated, or quota exhausted. Include
   findings, changes, verification results, branch/worktree and commit/PR links,
   remaining work, and the exact input needed to continue, when applicable.
