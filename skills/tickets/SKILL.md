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

## Override

The original /to-spec states "avoid specific file paths or code snippets: they go stale fast".
Disregard this section and include specific file paths and code snippets.
We will take a different approach to staleness: ensure that all code references are associated to a git commit.
