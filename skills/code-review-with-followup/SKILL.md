---
name: code-review-with-followup
description: "Adversarial code review with explicit followup instructions"
---

Use the `/orchestration` skill to manage sub-agents.

Delegate review to a `reviewer` sub-agent. Use `planner` as an alternate.

A `reviewer` performs a `/code-review-adversarial` using instructions supplied to this skill.
Persist its ouput as `code-review.md`.

If there are no findings in review (rare unless the changes is trivial), code review is complete.
Otherwise, perform a followup review.

Give a `coder` (alternate `implementer`) sub-agent `code-review.md` along with what was reviewed.
Ask the `coder` to make changes and provide an explanation for them as `code-review-followup.md`

Perform a followup review of how concerns in `code-review.md` were addressed by `code-review-followup.md` and a diff of the followup changes. Have the `coder` address any further followup changes needed.
