---
name: tickets
description: Break a plan, spec, or conversation into tracer-bullet issues for this repo, creating a parent tracking issue with sub-issues when publishing multiple tickets.
disable-model-invocation: true
metadata:
  short-description: Create project tickets with a parent tracking issue when needed.
---

# /tickets

This project builds on top of  the `to-tickets` skill to add more detail.

## Delegate first

Read the `/to-tickets` skill and follow its full process: gather context, draft vertical slices, quiz the
user, iterate until approved, and publish.

If that skill does not exist on this machine, stop and tell the user the
`to-tickets` skill is missing.

## Implementation Decisions override

The original /to-spec states "avoid specific file paths or code snippets: they go stale fast".
This is the wrong approach to staleness.
Instead ensure that all code references use a git commit.
It should be easy enough when implementing to determine if the code reference has now gone stale.
