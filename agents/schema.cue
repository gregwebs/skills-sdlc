package agents

// One agent, installed for each platform the user picks. Platform blocks use
// that platform's own field vocabulary, so rendering copies them through
// instead of translating them. Blocks are closed: add a field here before an
// agent uses it, and every renderer passes it on to that platform.
#Agent: {
	name!:        string
	description!: string
	claude?:      #Claude
	codex?:       #Codex
	antigravity?: #Antigravity
}

// ~/.claude/agents/<name>.md frontmatter.
#Claude: {
	model?:          string
	tools?:          [...string]
	fallbackModels?: [...string]
	permissionMode?: string
}

// ~/.codex/agents/<name>.toml.
#Codex: {
	model?:                 string
	model_reasoning_effort?: "low" | "medium" | "high"
	sandbox_mode?:           "read-only" | "workspace-write" | "danger-full-access"
}

// ~/.gemini/config/agents/<name>.md frontmatter.
#Antigravity: {
	model?:                  #AntigravityModel
	tools?:                  [...#AntigravityTool]
	mainAgent?:              bool
	subagent?:               bool
	commandExecutionPolicy?: "off" | "auto" | "eager" | "sandbox"
}

// A tier alias that Antigravity resolves from the user's configuration, or a
// concrete model id such as gemini-4-neon-high. Aliases outlive the model
// catalog; ids pin an exact model and thinking level.
#AntigravityModel:
	"inherit" | "flash_lite" | "flash" | "pro" |
		=~"^[a-z][a-z0-9]*(-[a-z0-9]+)+$"

// Antigravity hangs a subagent whose tools list names an unmapped tool, so this
// list stays short. Extend it only with a name verified in
// https://antigravity.google/docs/subagents/ or in the agy binary.
// Tool names for an Antigravity agent's `tools` list. The CLI and the App name
// the same capabilities differently, so both sets are accepted. Provenance for
// every name: docs/adr/0002-agents-from-one-cue-source.md.
#AntigravityTool:
	// Antigravity CLI: the tool set of a live session, and the names the
	// shipped migrate-agent-settings skill tells an agent to write.
	"read_file" |
		"write_file" |
		"edit_file" |
		"run_command" |
		"manage_task" |
		"update_steps" |
		"send_message" |
		"schedule" |
		"invoke_subagent" |
		"define_subagent" |
		"manage_subagents" |
		"search_web" |
		"ask_question" |
		"run_workflow" |
		// Retired from the CLI baseline, still enabled for agents that list
		// them (CLI changelog).
		"find_by_name" |
		"grep_search" |
		"list_dir" |
		// Antigravity App and IDE (custom subagents docs).
		"view_file" |
		"write_to_file" |
		"replace_file_content" |
		"read_url_content"
