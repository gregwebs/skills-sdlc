---
name: breakdown
description: Break a plan, spec, or the current conversation into a set of tracer-bullet tickets, each declaring its blocking edges
metadata:
  inlined-from:
    - source: ../../vendor/mattpocock/skills/engineering/to-tickets/SKILL.md
      source-scope: "## Process"
      source-scope-sha256: "ae2ac74402ccc657dbe771d0dc2489f6f8a9f48c4cfa2b3bdcde9a529253c9d9"
      components:
        - source-section: "### 1. Gather context"
          local-section: "### 1. Gather context"
        - source-section: "### 2. Explore the codebase (optional)"
          local-section: "### 2. Explore the codebase (optional)"
        - source-section: "### 3. Draft vertical slices"
          local-section: "### 3. Draft vertical slices"
        - source-section: "### 4. Quiz the user"
          local-section: "### 4. Quiz the user"
---

# Breakdown

Turn already-understood work into locally useful tracer-bullet slices. Unlike
`/to-tickets`, this skill intentionally stops before publishing tickets.

## Process

### 1. Gather context

Work from whatever is already in the conversation context. If the user passes a reference (a spec path, an issue number or URL) as an argument, fetch it and read its full body and comments.

### 2. Explore the codebase (optional)

If you have not already explored the codebase, do so to understand the current state of the code. Ticket titles and descriptions should use the project's domain glossary vocabulary, and respect ADRs in the area you're touching.

Look for opportunities to prefactor the code to make the implementation easier. "Make the change easy, then make the easy change."

### 3. Draft vertical slices

Break the work into **tracer bullet** tickets.

<vertical-slice-rules>

- Each slice cuts a narrow but COMPLETE path through every layer (schema, API, UI, tests) — vertical, NOT a horizontal slice of one layer
- A completed slice is demoable or verifiable on its own
- Each slice is sized to fit in a single fresh context window
- Any prefactoring should be done first

</vertical-slice-rules>

Give each ticket its **blocking edges** — the other tickets that must complete before it can start. A ticket with no blockers can start immediately.

**Wide refactors are the exception to vertical slicing.** A **wide refactor** is one mechanical change — rename a column, retype a shared symbol — whose **blast radius** fans across the whole codebase, so a single edit breaks thousands of call sites at once and no vertical slice can land green. Don't force it into a tracer bullet; sequence it as **expand–contract**. First expand: add the new form beside the old so nothing breaks. Then migrate the call sites over in batches sized by blast radius (per package, per directory), each batch its own ticket blocked by the expand, keeping CI green batch to batch because the old form still exists. Finally contract: delete the old form once no caller remains, in a ticket blocked by every migrate batch. When even the batches can't stay green alone, keep the sequence but let them share an integration branch that all block a final integrate-and-verify ticket — green is promised only there.

### 4. Quiz the user

Present the proposed breakdown as a numbered list. For each ticket, show:

- **Title**: short descriptive name
- **Blocked by**: which other tickets (if any) must complete first
- **What it delivers**: the end-to-end behaviour this ticket makes work

Ask the user:

- Does the granularity feel right? (too coarse / too fine)
- Are the blocking edges correct — does each ticket only depend on tickets that genuinely gate it?
- Should any tickets be merged or split further?

Iterate until the user approves the breakdown.
