## Goal

* Increase Agent code quality (fewer defects, stronger code base)
* Decrease user overview to planning and reviewing

These are achieved by:
* outlining a workflow that emphasizes specing, planning, testing, verification, and architecture/design
* having a separate agent review at every stage

Requirements from you
* Deeply involved with the speccing/planning stage
* Spend effort on engineering discipline

Downsides
* It takes AI more time to complete its task
* Higher cost to initially complete a feature
  * For a sustained non-prototype code base you save costs due to
    * Fewer defects
    * A more agile code base (future changes are less costly to make)

This configuration pushes you towards a large investment in alignment via /gril-with-docs and then mostly optional involvement after that point.
If configured and allowed, the agent can send Pull Requests.

## Docs

See [CONTRIBUTING.md](./CONTRIBUTING.md) for how to test changes to this repo.

## Implementation

The implementation is in the skills.
The skill files are designed to be generic with respect to programming language and project.
You customize things for your repo by editing
* AGENTS.md (or CLAUDE.md)
* CODING_STANDARDS.md - for writing and reviewing code, this project has a generator

### Installing

This relies heavily on mattpocock/skills.

```
npx skills@latest add mattpocock/skills
```

After the Matt Pocock skills are available in `~/.agents/skills`, install this
repository's overrides and the referenced upstream dependencies with:

```sh
./scripts/install-skills.sh
```

This script creates symlinks to this github repo.
That makes it easy to upgrade by pulling the github repo.

The installer ensures that the dependent Matt Pocock skills are already installed.
When `~/.claude` exists, matching links are also installed in `~/.claude/skills`.

Install the repository's agent definitions with:

```sh
./scripts/install-agents.sh [--dry-run] [--force] [--help]
```

This links `agents/*.md` into `~/.claude/agents` and `.codex/agents/*.toml`
into `~/.codex/agents`. Both destination directories are created as needed;
Overwriting is refused by default: use `--force` to overwrite with a timestamped adjacent backup.

Generate a project's `CODING_STANDARDS.md` from this repository's
[standards/](./standards) documents with:

```sh
./scripts/install-standards.sh [--help] [--list] [--force] [standard...]
# example
./scripts/install-standards.sh bash coding go security > CODING_STANDARDS.md
```

Positional arguments name which `standards/*.md` documents to add to the standard and in which order.


## Workflow

The Overall flow:

Find work -> Spec with a grilling session -> create Tickets -> Implement a ticket

Workflows are started by you, normally with a frontier model using these skills:

* /grill-with-docs (new feature or enhancement)
  * /improve-codebase-architecture (cleanup your slop, goes into a grilling session)
* /diagnosing-bugs

Next work can then be broken down into slices and published with:

* /tickets (/github-tickets for Github users)

Then implemented with

* /implement

This orcestrates planning, implementing, and reviewing. If you install the agents in this repo, it will use them to switch between opus for planning and review and Sonnet for implementation.

You may not always go through the full flow. Sometimes the bug seems very simple and you can just ask the agent to fix it and then send a /pull-request. Or you think a grilling session is unnecessary for a simple change and you go from a conversation to /tickets. The workflow has lots of pieces that you can use however you see fit.


### Differences

The main difference between this repo and using mattpocock/skills directly is

#### Implement with a plan

The override of /implement adds the concept of an Implementation Plan. The spec created by mattpocock/skills is intentionally not very detailed since details can change.
An Implementation Plan is detailed, and is generated at the start of the implementation. This can be done in plan mode by a smarter agent (Opus/Fable).
After the plan is approved a more efficient agent (Sonnet) can take over.

### Model selection

An `implementer` agent is included that actually writes the code.
This agent uses Sonnet (with Claude).
A `planner` agent uses Opus.

If you have a very simple task that you want to oversee, you can just use /plan.
In claude, With permission `defaultMode` is separately set to `plan` and 
the `opusplan` model alias- this can be done in  `.claude/settings.local.json`.
This requires explicit approval to move between planning and implementation.
Opus Plan mode helps ensure cost effective module usage by switching between Opus for planning and Sonnet for implementation.

The workflow in this repo does an automatic planning mode (no user approval required)- this works if you already aligned with the /grill-with-docs.


#### Agent review at every step

A separate agent provides an adversarial review of both the plan and the code.

#### Artifact-based handoffs

The `/implement` skill starts planning, implementation, and review agents with fresh context instead of inheriting the main conversation.
The orchestrator points agents to task-scoped Markdown artifacts in a temporary directory outside the repository.

#### Agent sends a Pull Request

A /pull-request skill is provided. This is Github specific and conditional on setting up access and instructing in AGENTS.md/CLAUDE.md to send a PR.

## Engineering discipline

The key to letting agents do more work for you is increasing the engineering discipline.
Agents are perfectly happy to implement linting, ci, e2e tests, etc *if you direct them to*.
The /implement skill directs the agent to use /tdd.
But the rest is largely project specific and is up to you to specify in your documentation and to spend time implementing these engineering practices.

## Security

We want to let the agent do safe operations without prompting us- prompt fatigue creates security risks.

The agent should operate as a separate OS user in an isolated sandbox (VM/container) with network access restricted.

Otherwise you will need to use the harness (claude code) sandboxing to carefully allow specific commands. Have the agent write code (scripts) for common workflows and commit those.

### Github

If you are going to give the agent autonomy to interact with Github, it is better that it doesn't actually appear to be you and that permissions are restricted as much as possible.
If you use the Claude Github app, the interaction will appear to be directly from you and you cannot alter the permissions, only the repos that it has access to.

There is a skill /github-app in this repo to help the agent authenticate as Github application rather than as you.
This will not work on Claude Code for the Web (cloud) because they block Github requests- you would need to use the Claude Github app there to send a PR or teleport it back to your local Claude first.

### Github Actions CI

There is a /github-actions-ci skill for the purpose of not asking for permission to interact with github actions.
Its check-run helper is bundled and allow-listed with `${CLAUDE_SKILL_DIR}`, so
the repository being checked does not need its own CI wrapper script.

Note that in Codex skills cannot allow list tools- you need to add things allowed by the skill to the permission rules.
