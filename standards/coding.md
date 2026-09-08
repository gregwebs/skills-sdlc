# Code Quality Guidelines

## Documentation

Comments state design constraints, invariants, and **why**. Not **what** the code does. If you feel a comment is needed to restate what the next line does, that almost always means the code should be refactored to make what it is doing easier to understand. For example extract a function with a descriptive name.

## Correctness

### Testing

Think about areas likely to have subtle bugs before implementing; for each, state likely mistakes and plausible alternative interpretations, then come up with a check where the results differ (prefer asymmetric / boundary examples on both sides of the boundary).
After implementing, for high risk areas, independently re-derive the result without context on production code and compare.
When feasible, use property-based testing or randomized inputs to try to explore the space, minimizing effort on no-panic or no-crash randomization. Commit these as test cases.
When randomizing, lean towards inputs that will explore interesting state and code paths (don't just naively randomize inputs that all fall into the same error paths); this may require structured random inputs
Use contracts- automated contract is preferred, but contracts as comments can be used.
Write seeds for creating data that is needed for testing.
Use mocks only as a last resort.
Look at the /tdd skill for further testing guidance.



### Types

Use strong typing. Make invalid states unrepresentable with types. Represent the problem domain properly with types. Use enums and case analysis.

Examples:
* After a string is validated/parsed it should be given a new type.
* Don't use dynamic types (e.g. as `any` in Go). Use generic types. If using a library that uses dynamic types, convert them to strong types as quickly as possible.
* Don't use the same type multiple times in a row for function arguments (these could get confused). Use a newtype for one of the arguments or use named arguments (via a struct or other language construct) for some of the function arguments.
* The callee should require validated types in its arguments that the caller should produce.


### Error Handling

Always handle errors. Logging an error at the error site is equivalent to ignoring it. An error should be passed up callers until it reaches an error handler that can deal with it. Catch all error handlers should only exist at a top level and must properly handle the error by terminating the program in an exit state or returning an error code after logging the error.


## Quality

Every new feature must improve or maintain high standards for the quality of the codebase.
A small bugfix should focus on correctness and does not need to be concerned about code quality.

### Architecture

Ensure that we are developing deep modules as described in the `/codebase-design` skill.

### DRY

Follow the DRY (Don't Repeat Yourself) principle and avoid duplicating Code or Logic.
* Avoid duplicating code for similar functionality- favor abstractions.

Don't go overboard:
* Prefer readability over DRY when the abstraction requires indirection that obscures what the code does — a small amount of duplication is often better than an obscure helper.
* Don't couple unrelated concepts in an attempt to DRY- these can only be served by truly generic functionality
* It is okay to wait until you have 3 concrete instances if the value/work for DRY appears low for just 2 instances.

### Configuration and Constants

Maintain a single source of truth for configuration values.
Define thresholds and parameters as named constants.

### Tracing and Logging

API logs should have a parameter to correlate logs to a particular request and a particular client.
We should be able to understand (INFO: high level) and debug (DEBUG: low level) our program by looking at the logs.
Use log sections- metadata indicating what part of the codebase is being exercised.
Programs should be able to set the log level (to DEBUG) only for particular log sections via environment variables or CLI.
