---
name: verify
description: "Verify software by intentional testing."
---

# Core Principles

1. **Good Code is easy to verify and needs fewer tests**
   If altering code reduces the amount of verification needed or makes it easier, that is likely a worthwhile change to make.
   Use strong typing to reduce edge cases.

2. **Verify behavior, not implementation details**
   Treat implementation and verification as separate reasoning tasks.
   Derive expectations from requirements, contracts, documentation, and domain rules rather than the implementation.

3. **Optimize for fault detection**
   Coverage is useful for identifying untested areas. It is not a measure of test quality.
   When deciding whether to add a test, ask:
    > What plausible defect would this test detect that the existing tests would not?
   When deciding whether testing is sufficient, ask:
    > If this implementation is subtly wrong, how likely is the current verification strategy to expose it?

4. **Keep tests deterministic, understandable, and maintainable**
   Avoid unnecessary mocks, brittle implementation coupling, arbitrary sleeps, order dependencies.
   Write seeds for creating data that is needed for testing and avoid duplicated setup.

5. **Verify while coding**
   Code should be verified immediately after writing it (or sooner).
   Run progressively broader verification as more code is written, ending with e2e.
   For bug fixes, strongly prefer reproducing with a regression test before fixing.

# Workflow

1. **Develop Automated Tests**
   See **Test writing Process**

2. **Perform manual verifications**
   e2e tests in particular may not be worth automating.

3. **Perform an adversarial review**
   Are the tests meeting these outlined standards and process?
   Is the specification/plan fully verified?

4. **Final Report**
   Briefly report:
   * behavior that was verified
   * verification commands or checks run
   * important tests added or changed
   * stronger testing techniques used
   * remaining risks or under tested areas


# Test writing Process

1. **Understand the behavior**
   Before writing tests, identify:
   * intended behavior and public contracts
   * important business rules
   * boundaries and edge cases
   * failure paths
   * state transitions
   * integration boundaries
   * existing test conventions

   Derive expectations from requirements, contracts, documentation, and domain rules rather than the implementation.

2. **Establish a Baseline**
   Run relevant existing tests.
   Note any pre-existing failures and use coverage, when available, to identify potentially untested areas.

3. **Look for high-value test areas**
   Look for counterexamples to code by probing:
   * changed or important behavior
   * boundary conditions
   * error handling
   * important branches and state transitions
   * regressions
   * integration behavior that could realistically fail

4. **Look for high-defect areas**
   Think about areas likely to have subtle bugs before implementing; for each, state likely mistakes and plausible alternative interpretations, then come up with a check where the results differ (prefer asymmetric / boundary examples on both sides of the boundary).

5. **Choose appropriate techniques**
   Unit test examples are not the only way to verify.
   * Leverage types and static analysis (linting or other tools) first.
   * property-based testing for invariants and large input spaces
   * differential testing when a trustworthy alternative implementation or oracle exists
   * fuzzing for parsers, protocols, serialization, untrusted input, and similar boundaries
   * mutation testing for important logic or subtle defects
   When randomizing, lean towards inputs that will explore complicated state and code paths.

6. **Review Inputs and Outputs**
   For non-trivial logic, actively try to construct an input that breaks it.
   For high risk areas, independently re-derive the result without context on production code and compare.


# Advanced Testing Methods

## Property-based tests

Use when behavior can be expressed as general invariants across many inputs.

Look especially for:

* round trips
  `decode(encode(x)) == x`

* idempotence
  `normalize(normalize(x)) == normalize(x)`

* preservation: sorting preserves the input elements
* algebraic relationships
* monotonicity
* bounds
* equivalence between transformations
* invariants across state transitions


## Differential tests

Use when a trustworthy alternative implementation or oracle exists.

Examples:

* old implementation vs. replacement
* reference implementation vs. optimized implementation
* two independent libraries implementing the same specification
* server calculation vs. client calculation
* legacy parser vs. rewritten parser

Generate or collect diverse inputs and investigate disagreements.

## Fuzz testing

Consider fuzzing for code that processes:

* parsers
* file formats
* network input
* protocol messages
* untrusted text or binary data
* serialization
* compilers/interpreters
* security-sensitive boundaries

Use discovered failures to create minimized permanent regression tests.

## Mutation testing

Use selectively for important logic when ordinary test results and coverage do not provide enough confidence.

Mutation testing is particularly useful for determining whether tests would detect subtle changes to:

* conditions
* comparisons
* arithmetic
* boolean expressions
* return values
* control flow

Investigate surviving mutants.

Add a test when the survivor represents a plausible defect that the test suite should detect.

Equivalent or irrelevant mutants do not require tests.
