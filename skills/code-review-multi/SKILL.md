---
name: code-review-multi
description: "Perform multiple code reviews"
---

Use the `/code-review-with-followup` skill using instructions supplied to this skill.

However, instead of performing just 1 code review, perform multiple independent code reviews.
Synthesize the independent reviews into one large review before giving that to the `coder`.

Every independent code review should use a different model.
Use models/agents specified by the caller if given.

Otherwise try to get a
* weaker model review by `reviewer-simple` or `coder`
* strong model review by `reviewer` or `planner`.

Use the strongest model for both review synthesis and followup.
