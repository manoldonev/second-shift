# #398 — tracker README undercounts the lean lane's adapter-sensitive operations

## Problem

`plugins/dev-pipeline/skills/run/tools/tracker/README.md:52-55` (the lean-lane operation
table) carries four rows — **entry**, **claim**, **exit**, **reconcile** — since #388 added
the reconcile row. Two prose sites still count that table at three, from before #388:

- `run/tools/tracker/README.md:24-25` — "the lean lane's **three** adapter-sensitive
  operations follow it"
- `run/tools/tracker/jira/README.md:14` — "The lean lane's **three** adapter-sensitive
  operations are tabulated in `../README.md`"

`README.md:43` ("`lean-gate.sh` ... branches at exactly **three** sites") is a separate,
correct claim about gate branch sites, not lane operations, and must not be touched.

#395 documents review-lean's jira-key resolution, a further adapter-sensitive operation with
no script branch and no table row. Adding a fifth row for it is one way to make the prose
correct again, but the count has already gone stale once (three → four) and would be
positioned to do so again on the next addition. Dropping the count from both prose sites is
the more durable fix: the sentences point at the table instead of restating its size.

## Fix

At both prose sites, rephrase to drop the numeric count while keeping the pointer to the
table:

- `run/tools/tracker/README.md:24-25`: "the lean lane's adapter-sensitive operations follow
  it" (no count).
- `run/tools/tracker/jira/README.md:14`: "The lean lane's adapter-sensitive operations are
  tabulated in `../README.md`" (no count).

No table restructuring, no row added for review-lean's jira-key resolution.
`README.md:43`'s "exactly three sites" (about `lean-gate.sh`'s branch count, not the lane
operation table) is left unchanged, and the sentence there that separately counts
`lean-reconcile.sh`'s one branch stays as-is.

## Acceptance criteria

- **AC-1** (critic): neither `run/tools/tracker/README.md:24-25` nor
  `run/tools/tracker/jira/README.md:14` states a numeric count of lean-lane
  adapter-sensitive operations that could disagree with the table it points at.
- **AC-2** (critic): `run/tools/tracker/README.md:43`'s "exactly three sites" (for
  `lean-gate.sh`'s branch count) is unchanged, and the doc still distinguishes gate branch
  sites from lane operations.
- **AC-3** (oracle — CI): prose-only change — no gate script or selftest edits; existing
  suites pass untouched.
- **AC-4** (critic): commit carries a `Changelog:` trailer.

## Out of scope

Adding a table row for review-lean's jira-key resolution (#395); restructuring the
lean-lane operation table itself.
