---
name: spec
description: "Turn the current conversation into a spec and publish it to the project issue tracker: no interview, just synthesis of what you've already discussed."
disable-model-invocation: true
---

# /spec

This project builds on top of  the `spec` skill to add more detail.

## Delegate first

Read the `/to-spec` skill and follow its full process: gather context, draft vertical slices, quiz the
user, iterate until approved, and publish.

If that skill does not exist on this machine, stop and tell the user the
`to-spec` skill is missing.

## Implementation Decisions override

The original /to-spec states "Do NOT include specific file paths or code snippets. They may end up being outdated very quickly.". This is the wrong approach to staleness. Instead ensure that all code references use a git commit.
It should be easy enough when implementing to determine if the code reference has now gone stale.
