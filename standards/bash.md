# Bash

Use `set -euo pipefail` for basic safety.

Be very careful with using `rm` and other destructive commands.

Prefer simple shell idioms- require a lower level of bash proficiency for reviewers.

When functions are being written, question whether shell should be used.
Functions can end up interacting poorly with `set -e`

Shell is generally only for entry points and automation: running commands in sequence, passing arguments and handling exit statuses. Simple transforms of data from external systems are fine (a jq filter, `awk '{print $2}'`, a sed substitution). Parsing, policy decisions, loops over records and helper functions beyond `fail`/`usage` should be done in a different programming language. The main exception to this is dealing with bootstrapping issues.
