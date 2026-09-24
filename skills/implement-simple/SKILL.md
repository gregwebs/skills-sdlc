---
name: implement-simple
description: "Implement a piece of work based on a spec or set of tickets."
disable-model-invocation: true
---

Before beginning, `/update-working-copy`

Implement the work described by the user in the spec or tickets.

Use `/verify` to verify code as it is written.

Once done, use `/code-review-with-followup` to review the work.

Use `/wrap-up` to get the work merged.

## Completion

Do the following if your instructions authorize/direct it and the capability is available.
* Commit your work. Reference relevant issues/tickets in your commit message.
* Generate a PR
* Watch for CI success

Use the `/document-changes` skill to record your changes.

For out of scope defects seen during implementation, file a bug report.
For any new features/enhancements brought up during implementation, ask the user about them.
