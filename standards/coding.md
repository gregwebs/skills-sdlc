# Code Quality Guidelines

## Documentation

Comments state design constraints, invariants, and **why**. Not **what** the code does. If you feel a comment is needed to restate what the next line does, that means the code should be refactored to make what it is doing easier to understand. For example extract a function with a descriptive name.

### Architecture

Ensure that we are developing deep modules as described in the `/codebase-design` skill.

## Correctness

### Testing and verification

Reference the `/verify` skill for how to write good tests

### Types

Use strong typing. Make invalid states unrepresentable with types. Represent the problem domain properly with types. Use enums and case analysis.

After data is validated/parsed it should be given a new type, even if the underlying type is still string.

Minimize the need for a function to first check the invariants of its arguments before using them: the caller should produce validated data proved by the types passed to the function.

Anti-patterns:
* dynamic types (e.g. as `any` in Go). Use generic types when possible. Convert dynamic types to strong types as quickly as possible.
* function(a: bool, b: bool). Avoid using the same type multiple times in a row for function arguments. Use a newtype for one of the arguments or use named arguments (via a struct or other language construct) for some of the function arguments.


### Error Handling

Always handle errors. Logging an error at the error site is equivalent to ignoring it. An error should be passed up callers until it reaches an error handler that can deal with it. Catch all error handlers should only exist at a top level and must properly handle the error by terminating the program in an exit state or returning an error code after logging the error.


### DRY

Follow the DRY (Don't Repeat Yourself) principle and avoid duplicating Code or Logic: favor abstractions.

Don't go overboard:
* Prefer readability over DRY when the abstraction requires indirection that obscures what the code does — a small amount of duplication is often better than an obscure helper.
* Don't couple unrelated concepts in an attempt to DRY- these can only be served by truly generic functionality

### Configuration and Constants

Maintain a single source of truth for configuration values.
Define thresholds and parameters as named constants.

### Tracing and Logging

We should be able to understand (INFO: high level) and debug (DEBUG: low level) our program by looking at the logs.
Use log sections- metadata indicating what part of the codebase is being exercised.
Programs should be able to set the log level (to DEBUG) only for particular log sections via environment variables or CLI.

API logs should have a parameter to correlate logs to a particular request and a particular client.

### Avoid embedding code

Keep code it in its native file format where it can be independently ran and tested and call it from there.
A common anti-pattern is embedding multi-line bash scripts into Makefiles or Dockerfiles.
