---
name: easy-issues
description: Find and work through easy issue-tracker tasks autonomously, simplest first, using one fresh subagent per issue in sequence. Use for clearing straightforward bugs, documentation fixes, and tiny features without operator help.
---

# Easy issues

Work through the project's open issues until no simple work remains, quota is
exhausted, or the operator says to stop.

Use `/orchestration` to manage subagents.
Keep the coordinator focused on triage and handoffs; delegate investigation and
implementation. Run only one issue at a time, including its child workflows.
Finish or stop that issue's agents before starting another, so several issues
cannot exhaust quota together.

## Find and rank work

Identify the project's tracker from repository instructions and remotes. Use its
configured access workflow.

Read open issues, including their descriptions, relevant comments, dependencies,
and linked work. Labels such as `good first issue` are hints, not requirements or proof of simplicity.
Skip issues already being implemented or covered by an open PR.

Find small changes with clear intended behavior and verification that an agent
can complete without operator input. Typical candidates are documentation fixes,
obvious bugs, and tiny features such as changing the text of a message. Exclude
work requiring product decisions, unavailable access, operator-only reproduction,
unresolved dependencies, or broad design changes.
Label these issues with an agreed upon label such as `simple` or `good first issue`.

When you find a very straightforward and simple issue, go ahead and work that one first.
Otherwise go through issues and rank them by expected total effort and uncertainty and
work the simplest issues first.

## Working an issue

Use a separate branch/worktree for each issue.
Use `/orchestration` to start a fresh subagent without inherited conversation history.
Give it the issue link, repository and artifact paths, relevant constraints, and this assignment:

1. Read repository instructions and the full issue. Confirm the task is clear,
   small, unclaimed, and solvable without operator help.
2. Determine a solution. For a non-obvious bug, use `/diagnosing-bugs`. If the
   investigation reveals substantial scope or needs operator input, checkpoint
   and return instead of expanding the task or waiting for an answer.
3. Once the solution is determined, use `/implement-simple` to implement, verify,
   review, and finish it. Follow that workflow's existing authorization rules for
   commits, PRs, and tracker updates.
4. Update the issue's progress artifact incrementally. Return a concise status:
   completed, needs operator help, complicated, or quota exhausted. Include
   findings, changes, verification results, branch/worktree and commit/PR links,
   remaining work, and the exact input needed to continue, when applicable.


## Continuing to next issues

If an issue needs help, write a progress summary in its artifacts and on the issue if authorized.
Label the issue with an agreed upon label and continue to the next candidate issue without waiting for the operator.

If an issue is completed, inform the user without waiting for a response.

Check for quota exhaustion and operator stop instructions before
starting another issue.

If access, quota, configuration, etc is blocking you from finishing an issue,
stop rather than attempting every issue against the same blocker.

## Stop and report

After stopping, give a short status report.
Report why the run stopped and summarize completed work with issue and commit/PR
links. Then list issues needing triage or operator help, ordered by how easy they
are for the operator to unblock: a quick answer or supplied example before
reproduction work or a larger design decision. For each, state progress, the
precise question or next action, and where partial work is saved. Distinguish
deferred issues from candidates not attempted before stopping; disclose any
uninspected backlog rather than claiming it contains no easy work.

When no candidates remain, check for new issues before declaring that no simple issues remain.
