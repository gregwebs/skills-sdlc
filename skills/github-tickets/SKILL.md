---
name: github-tickets
description: Break a plan, spec, or conversation into tracer-bullet GitHub issues for this repo, creating a parent tracking issue with sub-issues when publishing multiple tickets.
disable-model-invocation: true
metadata:
  short-description: Create project tickets with a parent tracking issue when needed.
---

# /github-tickets

This project builds on top of  the `tickets`/`to-tickets` skill so multi-ticket breakdowns
are published with a parent tracking issue (epic) and native GitHub sub-issue links.

It also asks for more detail in the ticket.

## Delegate first

Read the `/tickets` and `/to-tickets` skill and follow its full process. This skill just modifies the publishing portion.
If the `/tickets` skill is unavailable, just use `/to-tickets`.

If `/to-tickets` skill does not exist on this machine, stop and tell the user the
`to-tickets` skill is missing.

## Publishing override for this repo

This section provides specific details for how to publish to "A real issue tracker"

Create all issues with `./scripts/gh-app.sh issue-create`. Write issue
bodies to temp files and pass them with `--body-file`; never pass Markdown with
`--body`.

After each create command, extract the issue number strictly from the printed
URL. It must match `https://github.com/<owner>/<repo>/issues/<digits>` for this
repo's origin. If extraction fails, stop and report the URL instead of passing a
garbage number to another script.

If the approved breakdown has exactly one ticket, keep the base behavior: create
one `ready-for-agent` issue and do not create a parent issue.

If the approved breakdown has two or more tickets:

1. Create a parent epic tracking issue first.
   - Title: the short name of the work.
   - Body: the source spec verbatim, or a synthesized spec if working only from
     conversation, prefixed with one line saying this is a tracking issue whose
     sub-issues are the implementation tickets.
   - Labels: none.
2. Create child issues in dependency order.
   - Apply the `ready-for-agent` label.
   - Use the base issue template.
   - Include `## Parent` with a reference to the parent issue number.
3. After each child issue is created, attempt:
   `./scripts/gh-app.sh issue-sub-add --parent N --child M`
4. Sub-issue linking is failure-tolerant. If linking fails because of a 403,
   422, rate limit, or similar API issue, record the failure, keep creating the
   remaining children, and report all link outcomes at the end.
5. Once every child issue exists, record the approved breakdown's blocking
   edges as native dependencies. For each ticket with declared blockers, run:
   `./scripts/gh-app.sh issue-block-add --blocked M --blocker K`
   (`M` is the blocked child's issue number, `K` is each blocker's). Do this as
   a final pass after all children exist — a blocker's issue number isn't
   necessarily known yet when its dependents are created. Same
   failure-tolerant contract as sub-issue linking: on 403, 422, rate limit, or
   similar, record the failure, keep going, and report all outcomes at the end.
6. After all children are created, update the parent with
   `./scripts/gh-app.sh issue-update --issue N --body-file FILE`,
   re-sending the full body plus an appended `## Implementation tickets`
   section. List every child URL in dependency order, note its blockers in
   prose (e.g. `blocked by #12, #13`) so the graph survives even where a link
   attempt failed, and note any native sub-issue or blocked-by links that
   failed.

Relay all created issue URLs back to the user, parent first, including any
sub-issue or blocked-by link failures.
