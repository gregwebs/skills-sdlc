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
#AntigravityTool:
	"grep_search" |
		"list_directory" |
		"manage_task" |
		"multi_replace_file_content" |
		"read_url_content" |
		"replace_file_content" |
		"run_command" |
		"search_web" |
		"view_file" |
		"write_to_file"
