# skills-sdlc

Agent skills, standards, and scripts for running software delivery with coding
agents.

## GitHub App access

**Installation token**:
A short-lived (one hour) GitHub credential for the App's installation, minted
from the App's private key and handed to `gh` as `GH_TOKEN`.
_Avoid_: App token, access token, PAT

**Token cache**:
The per-installation file `${XDG_CACHE_HOME:-~/.cache}/gh-app/token.<installation-id>`
holding the current installation token and its expiry.
_Avoid_: token store, credential cache

**Wrapper**:
`skills/github-app/scripts/gh-app.sh`, the entry point that runs `gh`, or
an App-authenticated `git push`, as the installation.
_Avoid_: dispatcher, shim, helper

**Non-native operation**:
A GitHub operation with no `gh` command (issue dependencies and sub-issues),
served by a bundled script over `gh api`.
_Avoid_: custom command, extension
