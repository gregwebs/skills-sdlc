# Agents are authored once in CUE and installed per platform

Claude Code, Codex, and Antigravity all read subagent definitions from a
directory in the home folder, in three incompatible formats: Claude and
Antigravity use markdown with YAML frontmatter (different keys and tool names),
Codex uses TOML. The repository used to keep one hand-maintained copy per
platform, so the same agent drifted between them and only one platform was ever
current.

An agent is now three files under `agents/`:

- `<name>.cue` — the definition. Shared fields (`name`, `description`) sit at the
  top; each platform block holds fields written in that platform's own
  vocabulary, so rendering copies them through instead of translating them.
- `<name>.json` — `cue export` of that definition, checked in.
- `<name>.md` — the system prompt, identical for every platform.

`./scripts/install-agents.sh --platform claude|codex|antigravity` renders the
JSON and body through one jq template per platform and copies the result into
that platform's agent directory. `./scripts/generate-agents-json.sh --check`
fails when a checked-in JSON no longer matches its CUE.

## Considered Options

- **Keep per-platform copies.** Rejected: that is the drift this replaces.
- **YAML frontmatter as the single source, parsed at install time.** Rejected:
  neither `yq` nor PyYAML is present by default, and `pip install --user` is
  blocked by PEP 668 on Homebrew Python. Writing a YAML parser (in bash or
  otherwise) for a handful of fields is worse than the constraint it removes.
- **JSON as the single source.** Rejected for authoring: no types, no
  validation, and comments are impossible.
- **CUE only, rendered at install time.** Rejected: installing would then need a
  CUE toolchain on every machine, and a copy checked in also lets someone edit
  the JSON directly and skip CUE.
- **One canonical `tools` list plus a mapping table.** Rejected: Antigravity's
  tool names (`read_file`, `edit_file`, `run_command`) have no safe mapping
  from Claude's (`Read`, `Grep`, `Bash`), and
  [its docs](https://antigravity.google/docs/subagents/) warn that a misspelled
  tool name can hang the subagent. Tools are declared per platform and
  validated against `#AntigravityTool` in `agents/schema.cue`.
- **Templating in bash.** Rejected: TOML and YAML quoting rules (escaped
  backslashes, `"""` blocks) belong in a language with a real string type. jq is
  already a documented dependency of this repository.

## Consequences

- Installing needs only `jq`; `cue` is needed only to change a definition, and
  CI installs it so stale JSON cannot be merged.
- The platforms' fields stay visible and typed: `agents/schema.cue` rejects a
  Codex `sandbox_mode` that is not a real mode and an Antigravity tool name that
  does not exist.
- Installed files are copies, not symlinks, so a source change needs a reinstall
  and a hand edit in a destination is detected (refused without `--force`)
  instead of silently diverging.
- Pi is not a target. Its subagent frontmatter differs between the plugins that
  provide subagents, and the model names it accepts differ from the ones this
  repository pins.

## Antigravity tool names

An unmapped name in `tools` can hang the subagent, so `#AntigravityTool` is an
allowlist. Two surfaces use different names for the same capabilities, and the
allowlist had mixed them with a step name. Where each name comes from, checked
against `agy` 1.5.16:

| Names | Evidence |
| --- | --- |
| `read_file`, `write_file`, `edit_file`, `run_command`, `manage_task`, `update_steps`, `send_message`, `schedule`, `invoke_subagent`, `define_subagent`, `manage_subagents`, `search_web`, `ask_question`, `run_workflow` | The tool set recorded in a real CLI conversation (`~/.gemini/antigravity-cli/conversations/*.db`), and the six-tool list the shipped `migrate-agent-settings` skill writes into a migrated agent's `tools`. |
| `find_by_name`, `grep_search`, `list_dir` | The CLI changelog: retired from the default baseline "while keeping them available to custom agents that explicitly list them in `tools`". |
| `view_file`, `write_to_file`, `replace_file_content`, `read_url_content` | The [custom subagents docs](https://antigravity.google/docs/subagents/) example, and the `antigravity.localharness` tool configs in the binary. These are the App and IDE names; the CLI has no `view_file`. |

`list_directory` was dropped: it is a step type (`CortexStepListDirectory`,
`ActionListDirectory`), not a tool. The tool is `list_dir`.

There is no runtime proof of this table. The CLI on this machine is not signed
in ("You are not logged into Antigravity"), so invoking a probe subagent per
candidate name was impossible. The shipped agents therefore list only CLI names,
which a live session confirms, and the schema still accepts the App names so a
definition aimed at the App validates too.

The CLI resolves a `model` tier alias to a concrete model from its own config
(`flash` to `gemini-4-hydrogen-tiered-high`, `pro` to
`gemini-4-hydrogen-tiered-xhigh`), so an alias and a model id are both portable
enough to pin.
