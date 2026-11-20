---
name: easy-issues
description: Find and work through easy issue-tracker tasks autonomously, simplest first, using one fresh subagent per issue in sequence. Use for clearing straightforward bugs, documentation fixes, and tiny features without operator help.
---

# Easy issues

Work through the project's open issues until no simple work remains, quota is
exhausted, or the operator says to stop.

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

## Working issues

Use `/loop-issues` to work through the issues, using `/implement-simple` to implement each issue.

For each issue add the following steps to the `/loop-issues` process:

1. Read repository instructions and the full issue. Confirm the task is clear,
   small, unclaimed, and solvable without operator help.
2. Determine a solution. For a non-obvious bug, use `/diagnosing-bugs`. If the
   investigation reveals substantial scope or needs operator input, checkpoint
   and return instead of expanding the task or waiting for an answer.

## Continuing to next issues

If an issue needs help, write a progress summary in its artifacts and on the issue if authorized.
Label the issue with an agreed upon label and continue to the next candidate issue without waiting for the operator.

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
