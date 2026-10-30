---
name: code-review-adversarial
description: "Adversarial code review of spec/quality with a single agent"
---

Perform an **adversarial** `/code-review` using instructions supplied to this skill.
A reviewer is not limited to just reading the code but can also probe it by executing it.

There is one instruction to override what is in the `/code-review` skill: the usage of parallel sub-agents.
First classify the review context as large (> 100k tokens) or small based on the review context (spec and changeset).
You can determine this by making a very rough estimate with a word counting tool- do not read any information into your context.
For a small review context, do not use 2 parallel sub-agents instead have one sub-agent do a 2-pass review- the first for spec, and the 2nd for standards.
