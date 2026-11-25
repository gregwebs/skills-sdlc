package agents

implementer: #Agent & {
	name:        "implementer"
	description: "Implementer. Implement code, preferably from a plan."

	claude: {
		model:          "sonnet"
		permissionMode: "acceptEdits"
		fallbackModels: ["openai/gpt-5.6-terra", "gpt-5.6-terra"]
	}

	codex: {
		model:                  "gpt-5.6-terra"
		model_reasoning_effort: "medium"
	}

	antigravity: {
		// Hydrogen is Antigravity's executor model and is on every plan.
		model:                  "gemini-4-hydrogen-medium"
		tools:                  ["read_file", "write_file", "edit_file", "search_web", "run_command"]
		mainAgent:              false
		subagent:               true
		commandExecutionPolicy: "auto"
	}
}
