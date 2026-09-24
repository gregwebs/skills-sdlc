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

The stable repository entry point for GitHub App work is `./scripts/gh-app.sh`;
its bundled implementation is internal and must not be invoked directly. The
GitHub Actions skill exposes its bundled checker directly through
`${CLAUDE_SKILL_DIR}/scripts/check-ci-runs.sh`, so target repositories do not
need to provide a wrapper. The Verus skill exposes its cheat checker the same
way, as `${CLAUDE_SKILL_DIR}/scripts/check-verus-cheats.sh`; it compares the
pre-edit and current files and needs no Verus installation. That skill is
Rust-specific and lives at `skills/rust/verus`, which `./scripts/install-skills.sh`
skips because it only links top-level skill directories. Smoke-test these
interfaces with:

```text
/github-app        -> ./scripts/gh-app.sh -> bundled dispatcher
/github-actions-ci -> bundled ${CLAUDE_SKILL_DIR}/scripts/check-ci-runs.sh
/verus             -> bundled ${CLAUDE_SKILL_DIR}/scripts/check-verus-cheats.sh
```

```sh
./test/repository-interface.sh
./test/check-ci-runs.sh
./test/check-verus-cheats.sh
```

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
