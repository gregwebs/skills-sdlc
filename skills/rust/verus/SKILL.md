---
name: verus
description: Verify Rust code with Verus by writing proof annotations. Use when a Verus file fails verification with requires/ensures errors, when asked to prove or verify Rust code with the verus! macro and vstd, or when running verus or cargo verus.
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/check-verus-cheats.sh *)
---

# Verus proofs

The job is to add proof annotations until the verifier reports no errors,
without touching what is being proved.
Read the [LLM chapter](https://verus-lang.github.io/verus/guide/llmforverusproof.html)
of the Verus guide before the first run.

## Guardrails

* Add only proof code: proof functions, `assert`/`assert ... by`, `proof`
  blocks, loop invariants, loop `decreases` clauses, helper lemmas, ghost state.
* Never change `requires`, `ensures`, `recommends`, a function-level `decreases`,
  a `spec fn` body, or executable code. A proof that needs one of these is a
  specification bug: stop and report it.
* Never use `assume`, `admit`, `axiom`, `assume_specification`,
  `#[verifier::external_body]`, `#[verifier::external]`, or
  `uninterp spec fn`. A goal you cannot close is a result, not a failure to hide.

## 1. Preflight

1. Find the verifier command. Try the repository's documented one first
   (`AGENTS.md`, `CONTRIBUTING.md`, `justfile`, `Makefile`, CI config), then
   `verus --version` for a single file and `cargo verus verify` (or
   `cargo verus focus` to skip dependency crates) for a crate. Do not build
   Verus from source without asking; the release binary is the normal install.
2. Keep the pre-edit file. `git show HEAD:PATH > BASELINE` or copy it aside.
   The cheat check diffs against it, so it must be the pristine version.
3. Locate the references the proof will need: `vstd/` ships next to the
   `verus` binary in a release, the Verus test suite is `rust_verify_test` in
   the Verus source, and lemma signatures are in the
   [vstd docs](https://verus-lang.github.io/verus/verusdoc/vstd/) and the
   [guide](https://verus-lang.github.io/verus/guide/).
4. Run inside the project's sandbox or container. Verification needs many
   verifier invocations and no human intervention in between.

## 2. Develop the proof

Run the verifier, read the complete error output, edit annotations, repeat.
The errors are the design feedback; one attempt per proof is luck.

* Verify one item at a time when a file has many failures:
  `verus FILE.rs --verify-root --verify-function '*name*'`. Pass the same
  flags through a crate build with `cargo verus verify -- FLAGS`.
* Add `--expand-errors` when the failing predicate is unclear.
* Leave `--rlimit` near its default. Raising it to hundreds of seconds buys a
  slow failure; splitting the goal into lemmas buys a proof. Report the
  `--rlimit` you used.
* Use `--profile-all` or `--time` before blaming the tool for slowness.
* A loop body does not inherit facts from the function's `requires`. Repeat what
  the proof needs in the loop `invariant`, or assertions inside the loop fail
  with no visible cause.
* Search `vstd` and the project for an existing lemma before writing one.
  Prefer a lemma that states the needed fact over a long `assert` chain.
* Prefer `assert(...) by { ... }` over a monolithic proof body, and discharge
  quantifiers with `assert forall ... by`.
* An `assert` the verifier does not need is dead weight. Re-run without it
  before keeping it.

When a goal will not close, say which goal, why the available lemmas do not
reach it, and what lemma would. That is the handoff a human needs.

## 3. Cheat check

Both checks must pass before you report success.

```sh
verus FILE.rs --no-cheating
${CLAUDE_SKILL_DIR}/scripts/check-verus-cheats.sh BASELINE FILE.rs
```

`--no-cheating` rejects `assume`, `admit`, `external_body`, and
`assume_specification`. The script rejects the remaining shortcuts: `axiom`,
`uninterp spec`, changed signatures (which is where `requires`, `ensures`, and
function-level `decreases` live), deleted functions, and removed or rewritten
lines inside functions that already existed. It exits `1` and prints the
finding.

Loop invariants and loop `decreases` clauses are proof, not specification: the
checker treats them as body edits, so keep them honest yourself. An older Verus
without `--no-cheating` reports an unknown-option error: say so and rely on the
script, which needs no Verus install.

Treat a finding as a bug in your proof. Do not edit the checker, do not pass a
baseline that already contains the change, and do not describe a failing check
as clean. If the specification really is wrong, stop and ask the user to change
it.

## 4. Finish

* Verify the whole crate, not just the edited file, so nothing else regressed.
* LLM proofs run 2-3x longer than necessary. Delete annotations the verifier
  does not need, then verify again.
* Report: what now verifies, the exact command, any remaining errors, the
  highest `--rlimit` used, and any specification or executable change you
  believe is required.

## Where this fails

Expect trouble with inductive invariants, macro-generated code, opaque or
closed `spec fn`s that need the right `reveal`, and large functions. Decompose
the goal or hand back partial progress before spending a long budget; a single
hard proof can cost more than the rest of the task.
