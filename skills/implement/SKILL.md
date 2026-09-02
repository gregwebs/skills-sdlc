---
name: implement
description: "Implement a piece of work based on a spec or ticket with the flow: Plan -> Execute -> Review -> Verify -> Completion"
---

# Agent Delegation

Your job is solely to orchestrate subagents through implementation according to this skill.
Do not perform the planning or implementation inline or develop your own detailed understanding of either.
At most you will do simple checks/verifications between handoffs.
Any modifications to the workflow must be approved by the user.

You will rely on sub-agents using 2 different agents:
The `planner` agent is smarter and more costly and produces the design.
The `implementer` agent implements the plan and is designed to lower costs.
The sub-agents can ask you to interact with the user if needed.

Artifacts are passed between sub-agents so they start with a summary of all useful information from other sub-agents: this minimizes re-exploration. Create a task-scoped temporary directory outside the repository. Do not commit its contents. Pass absolute artifact paths between agents.

Start every planner, reviewer, and implementer delegation without inherited
conversation history. In Codex use `fork_turns="none"`; use the equivalent
empty-context option on other platforms. Give the delegate only its requested
action and the artifact or source paths it needs. Do not paste the conversation
transcript into the delegation prompt.

# Flow

## Phase 1 - A good plan

Delegate planning to a fresh `planner` sub-agent using `/implementation-plan`.
An implementation plan needs a spec, that will be `task-brief.md` with contents:
* For a single user input that is a spec or references a spec without reference to a larger conversation, write the user request verbatim, stripped of any workflow/orchestration modification instructions for you. Do not act on the user request (unless it has workflow/orchestration instructions) yourself or attempt to resolve links to specs yourself.
* Otherwise, provide a summary of implementation needs based on the conversation.
The `planner` output should be persisted as `implementation-plan.md`.

The `/implementation-plan` skill calls for a separate sub-agent review- ensure that it happens- you may need to spawn the sub-agent review. The exception is if the plan review notes state that this is a trivial change.

## Phase 2 - Plan execution

Delegate to a fresh `implementer` sub-agent with only
* `task-brief.md`
* `implementation-plan.md`

If the required implementer delegation is unavailable, stop after
planning and ask the user for an implementer/model handoff (the /handoff skill may be available). Do not execute the plan inline on the planning model.

If the implementer stops due to a plan issue, have the planner sub-agent review the plan issue and revise the plan accordingly.
Then restart **Phase 2 - Plan execution** with the revised implementation plan. The first step will be to review any existing implementation changes and make sure it satisfies with the newly revised plan. If a change does not, delete or overwrite the change.

### implementer sub-agent prompt

Execute an already-approved implementation plan. Do NOT redesign the plan.

#### Inputs (read both fully, in order)
- `task-brief.md`
- `implementation-plan.md`
These are self-contained. The plan restates all needed issue detail.

#### How to work

- Follow the plan's step-by-step sequence.
- Use TDD at the seams the plan identifies (invoke the `/tdd` skill where practical).
- Read repo documentation (INSERT SPECIFIC DOCS) for conventions before editing code.
- Run typechecking regularly, single test files regularly, and the full test suite once at the end.
- Do not document *what* code does; make it self-documenting via good names/extraction. Add *why* comments only where a requirement or a deliberately-rejected alternative needs explaining.
- Stay strictly within this ticket's scope.
- Perform a `/code-review` of your own code changes but without any sub-agents. Your inputs are the spec and your working changes are the fixed point.


#### STOP immediately and report if:
* Verification fails repeatedly
* The plan
  * has a critical gap
  * an instruction you don't understand


#### Output

Persist a final report as `implementation-result.md`.

Separately, extract all verification (from the plan and anything you performed or recommend) into  `verifications.md`.
Note whether the verifications have been performed (and their result).

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

Delegate to a fresh `implementer` sub-agent to perform required verifications. They should have access to
* `task-brief.md`
* `implementation-plan.md`
* `implementation-result.md`
* `verifications.md`

### implementer sub-agent

Verify manually that the changes work as expected in an e2e end user setting.
Test edge cases and failure modes in addition to the happy path.
Look at `verifications.md` for verification tests to perform.

Consider whether any manual verification steps can and should be added as automated tests.
Write these additional tests.

Don't make any changes to data that cannot be undone.
If possible work against a backup of data or seed data.

## Phase 4 - Completion

Do the following if your instructions authorize/direct it and the capability is available.
* Commit your work. Reference relevant issues/tickets in your commit message.
* Generate a PR
* Watch for CI success

Use the `/document-changes` skill to record your changes.
