# GitHub App work goes through the gh CLI, not bespoke REST scripts

The `/github-app` skill once shipped 18 `curl` + `jq` wrappers, a shared HTTP
library, and a dispatcher. They existed because `gh` was believed to fail TLS
against `api.github.com` on the agent host. That no longer reproduces: `gh`
2.102.0 handles REST, GraphQL and `gh auth git-credential` with an App
installation token. So the skill now exports that token as `GH_TOKEN` and
`exec`s `gh` unchanged (`skills/github-app/scripts/gh-app.sh`). Agents use
`gh`'s documented vocabulary, output and exit codes, and upstream fixes arrive
for free.

Two deliberate exceptions keep direct code:

- **Token mint** (`gh-app-token.sh`) still calls GitHub over HTTP. `gh api` has
  no `--jwt`, so the App JWT → installation token exchange has no `gh` command.
  Tokens are cached per installation until five minutes before GitHub's expiry.
- **Issue dependencies and sub-issues** (`gh-app-issue-dependency.sh`,
  `gh-app-issue-sub-issue.sh`) have no `gh` command. These scripts resolve issue
  numbers to database ids and call `gh api`.

## Considered Options

- **Keep the REST scripts.** Rejected: a private command vocabulary, a script,
  test and permission rule per operation, and no upstream improvements.
- **A `gh` shim on `PATH`.** Rejected: `~/.local/bin` is not on the host's
  `PATH`, and the `PATH` entry that is (`/opt/agent/.local/bin`) is root-owned.
- **`gh auth login --with-token`.** Rejected: it persists the App token into the
  user's `gh` config and changes what bare `gh` does for the user.

## Consequences

The old scripts were a whitelist; `gh` is not. The guard is now the skill's
prose (ask before touching other repositories, honour the target project's
`AGENTS.md`/`CONTRIBUTING.md`, report `403`s) plus the App's granted scopes.
Those scopes are a ceiling, not a guard. If `gh`'s TLS failure ever returns, it
will show up loudly in `gh`'s own errors instead of being silently routed
around.

The token cache stores the installation token unencrypted, despite
`standards/security.md` ("Secrets should only be stored encrypted"). The file
is mode 600 in a 700 directory and the token expires within an hour: the same
protection as the private key it is minted from, which never expires.
