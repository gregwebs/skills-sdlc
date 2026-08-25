---
name: bug-investigation
description: "Investigate a bug/defect. Triggered by 'fix/investigate a bug/defect'"
---

If a bug is non-trivial, use /diagnosing-bugs to investigate it.

Generate a root cause analysis of the defect.

A fix can be implemented immediately without an issue/ticket if it has a simple straightforward root cause and fix.

Otherwise, integrate the fix into the current workflow.
If you are in the midst of implementation and the implementation changes caused the bug, fix it as part of the implementation.

## Issues/Tickets

If there is already a defect ticket, save the root cause analysis on the ticket for the defect.
If there is no ticket referenced for a fresh bug report, ask the user if you should create one using /to-tickets. If you know how to search the issue tracker, first search it for a similar bug report.
As a bonus suggest how to fix the defect based on your existing defect analysis if you are able, but don't explore the code base further to do that- focus on completing and reporting the root cause analysis.
