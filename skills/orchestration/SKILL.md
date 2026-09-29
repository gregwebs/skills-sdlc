---
name: orchestration
description: "Orchestrate a workflow with subagents"
allowed-tools:
  - Read
  - Write
  - TodoWrite
  - TaskCreate
  - TaskGet
  - TaskUpdate
  - TaskList
---


# Orchestration

Your job is to orchestrate subagents through implementation according to this skill.
Do not perform the subagent duties inline or spend time develop your own detailed understanding.
You may need to do checks/verifications of agent handoffs.

Artifacts should be passed between sub-agents so they start with a summary of all useful information from other sub-agents: this minimizes re-exploration. Create a task-scoped temporary directory outside the repository. Do not commit its contents. Pass absolute artifact paths between agents.

Agents should edit artifacts incrementally- that way if an agent's session ends prematurely more information is persisted.

Start every delegation without inherited conversation history using the mpty-context option on the platform.
Give the sub-agent only its requested action and the artifact or source paths it needs.
Do not paste the conversation transcript into the delegation prompt.

Always run subagents without blocking- this makes it possible to monitor them.
Check on subagents every 15 minutes to see if they are stuck and to see their token usage.

A subagent should compact after 200k tokens regardless of its total limit.
Compaction is accomplished by restarting the agent.
When the subagent gets over 150k tokens, tell it to find a convenient stopping point and checkpoint information in the standard artifact files and to write out any additional files that will be helpful to re-read on restart. Restart the agent with instructions to read these files and continue its work.

If a specific agent (and any listed fallabacks) are unavailable for delegation, stop and ask the user how to proceed.
