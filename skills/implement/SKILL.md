---
name: implement
description: "Implement a piece of work based on a spec or ticket with the flow: Plan -> Execute -> Review -> Verify -> Completion"
allowed-tools:
  - Read
  - Write
  - TodoWrite
  - TaskCreate
  - TaskGet
  - TaskUpdate
  - TaskList
---

This skill uses other skills. If a skill is missing, stop and ask the user to install it.

Before beginning, `/update-working-copy`

Any modifications to the workflow must be approved by the user.

# Agent Delegation

Use the /orchestration skill to manage subagents.

# Flow

## Phase 1 - A good plan

Delegate planning to a `planner` sub-agent using `/implementation-plan`.
An implementation plan needs a spec, that will be `task-brief.md` with contents:
* For a single user input that is a spec or references a spec without reference to a larger conversation, write the user request verbatim, stripped of any workflow/orchestration modification instructions for you. Do not act on the user request (unless it has workflow/orchestration instructions) yourself or attempt to resolve links to specs yourself.
* Otherwise, provide a summary of implementation needs based on the conversation.
The `planner` output should be persisted as `implementation-plan.md`.

Have an independent subagent perform an adversarial review of the plan.
The exception is if the plan review notes state that this is a trivial change.
Use a `plan-reviewer` subagent if available, otherwise use a `reviewer`.

## Phase 2 - Plan execution

Delegate to a fresh `coder` (falling back to `implementer`) sub-agent, with only
* `task-brief.md`
* `implementation-plan.md`

If the `coder` stops due to a plan issue, have the planner sub-agent review the plan issue and revise the plan accordingly.
Then restart **Phase 2 - Plan execution** with the revised implementation plan. The first step will be to make any needed updates to existing changes to satisfy the newly revised plan.

### coder sub-agent prompt

Implement an already-approved implementation plan. Do NOT redesign the plan.

#### Inputs (read both fully, in order)
- `task-brief.md`
- `implementation-plan.md`
These are self-contained. The plan restates all needed issue detail.

#### How to work

- Follow the plan's step-by-step sequence.
- Stay strictly within this ticket's scope. For out of scope bugs or enhancements, suggest creating a ticket.
- Use `/verify` to verify code as it is written.
- Read repo documentation (INSERT SPECIFIC DOCS) for conventions before editing code.
- On completion, perform a `/code-review` of your own code changes but without any sub-agents. Your inputs are the spec and your working changes are the fixed point.


#### STOP immediately and report if:
* Verification fails repeatedly
* The plan
  * has a critical gap
  * an instruction you don't understand


#### Output

Persist a final report as `implementation-result.md`.

Separately, extract all verification (from the plan and anything you performed or recommend) into  `verifications.md`.
Provide evidence for all the verifications have been performed along with their results.

## Phase 3 - Review

Delegate `/code-review-with-followup` to an sub-agent. Look for an existing defined agent in this order:
* `reviewer`
* `planner`

Use these files:
* `task-brief.md`
* `implementation-plan.md`
* `implementation-result.md`
* `verifications.md`

During the review, add any new requested verifications to `verifications.md`.
Update `implementation-result.md` according to changes made from the code review.

## Phase 3 - Verification

Delegate to a `verifier` (falling back to `implementer`) sub-agent to perform required verifications. They should have access to
* `task-brief.md`
* `implementation-plan.md`
* `implementation-result.md`
* `verifications.md`

Review the verification report produced by the verifier.
Push back on any claims that verifications tests cannot be run in the environment- investigate those claims yourself.
For verifications that were ran, be skeptical of claims of the strength of verification (what was verified).

### verifier sub-agent

Verify manually that the changes work as expected in an e2e end user setting.
Test edge cases and failure modes in addition to the happy path.
Look at `verifications.md` for verification tests to perform.

Consider whether any manual verification steps can and should be added as automated tests.
Write these additional tests.

Don't make any changes to data that cannot be undone.
If possible work against a backup of data or seed data.

Provide a report on verifications performed.
Manual verifications or automated tests not ran on the CI must document how they were ran (pointing to other docs is good) and their result.

## Phase 4 - Completion

Use `/wrap-up` to get the work merged.
