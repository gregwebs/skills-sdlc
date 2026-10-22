## Duplication

Some skill information is duplicated to leverage mattpocock/skills but alter/override flows.
We document this in the metadata section of the skill.

```
metadata:
  inlined-from:
```

Checks for drift are done with

```
./scripts/check-skill-inlines.sh
```

### Instruction ownership and provenance

Skills that copy or behaviorally adapt upstream sections declare
`metadata.inlined-from`: an absolute, `~/`, or explicit `./`/`../` upstream
`SKILL.md`, exact parent heading, scope SHA-256, and source/local heading pairs.
Dot-relative paths resolve from the declaring `SKILL.md`; bare relative paths
remain invalid. Context pointers, delegation, and locally owned replacements
are not inlining.

Validation requires the pinned `vendor/mattpocock` submodule initialized, not
an independently installed home-directory copy. Run `git submodule update --init
--recursive` after cloning or pulling a changed gitlink.

Run `./scripts/check-skill-inlines.sh` to validate all tracked records, or pass
specific `SKILL.md` paths for fixtures. On drift, review the named upstream
scope and local components, port or intentionally decline the behavior, then
refresh the digest. Parent-scope hashes also detect inserted sibling sections;
never refresh a digest merely to silence the checker.


## Command interface tests

GitHub App work goes through the bundled wrapper
`${CLAUDE_SKILL_DIR}/scripts/gh-app.sh`, which exports an App installation
token and runs `gh` unchanged. Sibling skills call it as
`${CLAUDE_SKILL_DIR}/../github-app/scripts/gh-app.sh`, a path that resolves both
in this repository and in installed skill directories. Issue dependencies and
sub-issues, which `gh` has no command for, use the bundled
`gh-app-issue-dependency.sh` and `gh-app-issue-sub-issue.sh`. See
[ADR 0001](docs/adr/0001-gh-cli-instead-of-rest-scripts.md). The
GitHub Actions skill exposes its bundled checker directly through
`${CLAUDE_SKILL_DIR}/scripts/check-ci-runs.sh`, so target repositories do not
need to provide a wrapper. The Verus skill exposes its cheat checker the same
way, as `${CLAUDE_SKILL_DIR}/scripts/check-verus-cheats.sh`; it compares the
pre-edit and current files and needs no Verus installation. That skill is
Rust-specific and lives at `skills/rust/verus`, which `./scripts/install-skills.sh`
skips because it only links top-level skill directories. Smoke-test these
interfaces with:

```text
/github-app        -> bundled ${CLAUDE_SKILL_DIR}/scripts/gh-app.sh -> gh
/github-actions-ci -> bundled ${CLAUDE_SKILL_DIR}/scripts/check-ci-runs.sh
/verus             -> bundled ${CLAUDE_SKILL_DIR}/scripts/check-verus-cheats.sh
```

```sh
./test/repository-interface.sh
./test/gh-app.sh
./test/gh-app-issue-dependency.sh
./test/check-ci-runs.sh
./test/check-verus-cheats.sh
```

`./test/gh-app.sh` and `./test/gh-app-issue-dependency.sh` stub `gh` on `PATH`
and the token mint's HTTP call, so they need no network, `gh`, or App
credentials. They cover the token cache, argument passthrough, `git push`
authentication, and the exact `gh api` calls of the dependency and sub-issue
scripts. `./test/gh-app.sh` also wraps `git` on `PATH` to record the push
invocation before running real `git`. That is a second seam, beyond the single
stubbed process boundary the design assumed: the credential helper and token
are only observable at the push invocation itself, so a successful push alone
would not prove them.

`./test/check-ci-runs.sh` is a fixture-driven functional test (stubbed GitHub API,
no network) covering the checker's exit codes, including the "no GitHub Actions
checks apply to this commit" classification. `./test/check-verus-cheats.sh`
is fixture-driven too, covering each proof shortcut the checker must reject.

For local validation, run: `./test/all.sh`

When updating the submodule, review upstream behavior and provenance scopes
before committing the new gitlink. Never edit vendored files in place or track
a floating branch.

The contract needs `jq`, Bash, OpenSSL, and the initialized skills named by
provenance. ShellCheck and optional skill validation need separately installed
tools; report unavailable tools rather than treating CI as coverage.
