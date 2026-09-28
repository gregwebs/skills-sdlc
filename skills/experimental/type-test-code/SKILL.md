---
name: type-test-code
description: "Write types first, then test and code independently"
---

When writing code
1. first design and implement the types.
2. write tests with an indepdent subagent: done by the `tester`
3. write code independent of the tests: done by the `coder`

The task is complete when both
* the `coder` has completed the implementation plan (written all the code)
* the `tester` is satisfied with the level of testing.

## Types

Make all type changes at testing seams.
This includes either interfaces or function/method stubs.
You may need to write stub code inside a function to satisfy type checking.
In this case use either a standard for "unimplemented" or a TODO comment so the incompletion is obvious.

Ensure the code type checks.

## Tester

Once types are in place, spawn a separate `tester` sub-agent for writing tests.
If there is no `tester` sub-agent role defined than use the `implementer` sub-agent role.

Write the tests **without looking at the implementation, just the types**.

Use `/verify` to guide the writing of tests.

If tests are to be written in the same file as the code, see if you can first write tests in a separate file and then later move them into the code file after the code implementation is complete.

Maintain a persistent testing sub-agent to continue to run the tests until they all pass.
When notified that an implementation section has landed, run the relevant tests.
When there is a test failure due to an implementation issue, notify the `coder`.

## Coder

Spawn a separate `coder` sub-agent for writing the code.
If there is no `coder` sub-agent role defined than use the `implementer` sub-agent role.
The sub-agent should be given an `/implementation-plan` for the changes.

Write the implementation for the types **without looking at the tests**.

When a section of code writing is completed, notify the `tester` sub-agent.
When you are notified about a test failure, you can then look at the test and run it yourself.
