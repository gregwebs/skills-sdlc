---
name: implementation-plan
description: "Create a detailed Implementation Plan for a ticket or spec, corresponding to a single Pull Request."
metadata:
  inlined-from:
    - source: ~/.agents/skills/code-review/SKILL.md
      source-scope: "## Process"
      source-scope-sha256: "26477abdda062b77d1f11e4666a8ed60bbde57b6b50dceb74a0a0d73aed3b3e2"
      components:
        - source-section: "### 2. Identify the spec source"
          local-section: "### Identify the spec source"
        - source-section: "### 3. Identify the standards sources"
          local-section: "### Identify the standards sources"
---

## Overview

Create a detailed Implementation Plan for one work item. If an existing plan
already meets this skill's requirements, use it rather than creating another.

## Prerequisites

If you are running inline in the main conversation and have reason to believe
this turn is not on a reasoning-tier model, say so and ask whether to switch
before planning. If you are running as a subagent, do not ask — note the
limitation in your result and plan anyway.

### Identify the spec source

Use a user-supplied path or ticket first; then an accessible referenced issue;
then a matching tracked spec; then conversation context. If none exists,
suggest `/grill-with-docs` or `/to-spec` before planning.
If a ticket links to other related documentation or pull requests, fetch them as well if you have access.
If there is a parent issue or related issues that are completed, look at those completed issues. You can do this by looking at the commit history if the commit documents the issue.

### Identify the standards sources

Discover applicable tracked standards documents. `CONTEXT.md`, ADRs, and
conventional filenames are useful when present, but are not prerequisites.

## Scope management

Decide whether the work plausibly fits one pull request.
You can use the skill `/breakdown` as a guide, but do not to invoke it from inside planning.
If it does not, explain the split needed and suggest `/to-tickets`;

## What to include

The plan must give an implementer enough detail to execute without redesign.

High-level details:
1. **Background** — Explain only the system needed for the change. Start with an optional beginner-friendly mental model, then narrow to the exact components, contracts, and prior behavior involved.
2. **Intuition** — Explain the core idea before implementation detail. Use small concrete toy inputs and outputs with diagrams and examples where apropriate. Show the old and new behavior when comparison makes the change clearer.

Implementation details:
- Walk through the changes in conceptual groups, ordered by execution or dependency flow rather than arbitrary file order. Include precise file and line references when available, but do not dump an entire diff.
- Detailed file-level type and function signature changes, including snippets for important non-obvious ideas
- Tests to implement
- Documentation updates
- Include a pre-agreed TDD seam, or an explanation of why automated tests do not apply.
- Verifications to perform

Include the assumptions, and relevant standards constraints (these may be present in the spec).
Explain relevant failure modes and how to handle them.

Create diagrams and examples for:
- important state transitions
- flow diagrams for requests, data, or control flow;
- before/after panels for changed behavior;
- labeled component cards for system boundaries and connections;
- compact tables for mappings, invariants, and toy data.

Convert user stories into concrete tests or manual verification criteria.

Include a task checklist

## Review

Include a Review notes section in the plan. Put the text "no independent review" in this section when the plan is written out and not yet independently reviewed.

Perform a self-review according to the Review criteria.

If the change is trivial, no independent review is needed. Put the text "trivial change: independent review not needed" in the review section.
Otherwise, have an independent subagent perform an adversarial review of the plan.

## Review criteria

Review in this order and incorporate the findings into the plan:

1. **Spec** — completeness and scope.
2. **Architecture**
   - Ensure that we are developing deep modules as described in the `/codebase-design` skill.
   - module boundaries and trade-offs; use optional glossary and ADR context
3. **Quality** — standards, tests, and operational risks.

Present the revised plan as the reviewable output.
