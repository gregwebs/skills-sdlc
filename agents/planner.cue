package agents

planner: #Agent & {
	name:        "planner"
	description: "Produces an implementation plan to handoff to an implementer. Also usable as an architect."

	claude: {
		model:          "opus"
		tools:          ["Read", "Grep", "Glob", "Bash"]
		fallbackModels: ["openai/gpt-5.6-sol", "gpt-5.6-sol"]
	}

	codex: {
		model:                  "gpt-5.6-sol"
		model_reasoning_effort: "high"
		sandbox_mode:           "read-only"
	}

	antigravity: {
		// Gemini 4 Neon needs a paid plan; on Free, use
		// gemini-4-hydrogen-high or the "pro" alias.
		model:     "gemini-4-neon-high"
		tools:     ["view_file", "grep_search", "list_directory", "run_command"]
		mainAgent: false
		subagent:  true
	}
}
