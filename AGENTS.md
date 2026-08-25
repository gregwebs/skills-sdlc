Important Documentation

* README.md is a starting point
* Discover additional applicable standards documents when they apply such as `CONTRIBUTING.md` and `CODING_STANDARDS.md`.

# Writing style

When writing something intended for human consumption, (comment, commit message, reply to prompt):
* Pick every word meticulously to reduce the volume of output. Less is more.
* Get to the point first and then add details.

Avoid superlatives and praise. Give me the cold hard truth and tell me when I am wrong.

# Tool Usage

## Github

If the /github-app skill is availble and configured:
* Use it for access to the Github repo.
* Even if you don't need to auth, still use that skill because it allow lists scripts for the interaction patterns we used.
* If the /github-actions-ci skill is available, use it for interactions with Github CI.

## Temporary file handling for Codex

- `/private/tmp` is an approved writable location.
- Create throwaway test harnesses and diagnostic artifacts there without asking permission.
  Do not request escalation merely to read or write `/private/tmp`.
- Prefer `mktemp -d /private/tmp/tiny-desk-splitter.XXXXXX` for isolated temporary work.
- Use a direct-write repository script for temporary Markdown bodies.
- Do not use `apply_patch` for temporary files; reserve it for repository edits.

## Shell command execution

Run approved repository scripts directly- do not prefix these commands with zsh -lc, env, PATH=..., or similar wrappers unless the command cannot run directly. Only use `/bin/zsh -lc` when shell syntax, environment assignment, or a multi-command pipeline is strictly required.
If an environment adjustment is required, see if the shell scripts can be updated so that the adjustment is no longer needed.

Use allow listed commands from skills and settings.

If commands that you run require approval, propose writing a script for that which can be permanently allow listed.
