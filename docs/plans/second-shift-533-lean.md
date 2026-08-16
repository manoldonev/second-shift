# second-shift #533 — the pause-and-ask guard reads the issue body; intake writes the ledger

Part of #525. Shares a seam with #517 (both land a ledger reader into milestone 1 of
`lean-gate.sh`); at the time of this build #517 carries no labels and has not landed, so this PR
is the one that creates the seam rather than consuming it.

## Summary

`check_pause_and_ask` (milestone 1's guard against an unresolved `pause-and-ask` Open Region)
derived region ids from the issue body alone. Intake's `plan-interview` writes regions to the
pre-flight ledger (`.claude/pipeline-state/<issue>-ledger.md`) instead — so a run whose spec came
out of pre-flight had its regions sitting somewhere the guard never looked, and milestone 1 passed
with an unresolved region standing. Under `tracker.type: jira` the guard already short-circuited
unconditionally (no `gh issue` to read), which was doubly blind: the ledger is tracker-agnostic
and jira has no other source at all.

## Acceptance criteria

**AC-1 — region ids are derived from BOTH the pre-flight ledger and the issue body; a region
declared in either is seen.** The ledger's `## Open Regions` table is the same shape
`interviewing-baseline` defines for the issue body, so the existing `pause_and_ask_ids` parser
reads it unchanged — only the source differs. This is a union, not an either/or: the issue body
stays a *supported* source (an issue that does carry an Open Regions table keeps working) even
when a ledger also exists, since a github consumer could in principle carry a region in either
place. Ids from the two sources are deduplicated before resolution is checked, so a region
declared in both is reported once.

**AC-2 — the ledger read has an injectable seam, symmetric with `--issue-file`/`--comments-file`.**
`--ledger-file <path>` reads the ledger from that path instead of the resolved default
(`$STATE_DIR/<issue>-ledger.md`, the sibling of every other per-issue file in that directory —
`plan-lint.sh`'s `{issue}-ledger.md` convention for the same file). Required, not optional:
`scenario-liveness-selftest.sh`'s composed lean legs depend on this seam (alongside the two
existing ones) to stay zero-network and to avoid writing into `$STATE_DIR` — a directory shared,
mutable, across every worktree on the machine.

**AC-3 — the guard is reachable under `tracker.type: jira`.** The ledger read is unconditional
(both trackers); only the issue-body read and the comment-trail fetch are skipped under jira, since
neither has anything to read there. An unresolved region under jira can still be cleared by a
ratified intent-gap record — the one resolution artifact that is tracker-agnostic.

**AC-4 — an unreadable ledger is distinguishable from an absent one, and neither silently reports
"clear".** Mirrors the existing contract for the two `gh` arms (#532): a ledger path that does not
exist is legitimate absence (most tickets never go through pre-flight) and is silently treated as
"no ids from this source" — not an error, and not by itself a CLEAR verdict, since the issue body
is still consulted. A ledger path that exists but cannot be read (permission, or any other `cat`
failure) is an environment refusal (rc=2), exactly like a dead `gh issue view` or an unparseable
`--issue-file` — an unreadable ledger must cost no fix-budget attempt and must not be reported as
"declares no region".

## Explicitly out of scope

Mirroring regions from the ledger back into the issue body (or vice versa) — the ticket's own
resolved design call rejects it as new drift surface. Anything about `#517`'s own scope (spec
reconciliation against the ledger's Decision Ledger rows) — this PR touches only the pause-and-ask
guard.

## Tests

`lean-gate-selftest.sh`, extending the existing `(y)` block:

- a region declared only in the ledger (no Open Regions section in the issue body) refuses,
  naming it — AC-1's ledger-only half.
- a region declared in both the ledger and the issue body is reported once, not twice — the
  dedup half of AC-1's union.
- a ledger declaring `reversible-default-and-flag` only never refuses — AC-1 applies the existing
  AC-9 disposition rule to the new source, not just to the pause-and-ask disposition.
- `--ledger-file` pointed at a missing path is an environment refusal (explicit-seam contract,
  symmetric with `--issue-file`); the resolved DEFAULT path being absent is legitimate absence
  instead and does not refuse — the two "missing" cases are deliberately different outcomes.
- an unreadable ledger at the resolved path (`chmod 000`, the repo's existing precedent from
  `lane-registry-selftest.sh`) is rc=2, named, and spends no fix-budget attempt — AC-4.
- under `tracker.type: jira`: a ledger declaring an unresolved pause-and-ask region now refuses
  milestone 1 (AC-3's non-vacuity — the existing `(n16)` jira case is re-pointed to prove this
  rather than the retired "jira short-circuits entirely" behavior), and a ratified intent-gap
  record still clears it with no comment trail available.
