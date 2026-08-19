# second-shift #581 — catalog anchors rot against line content, and the earn-your-keep rule
would red the sweep if applied literally (lean spec)

Issue: https://github.com/manoldonev/second-shift/issues/581
Parent: #567 (mutation-sweep reshape), decomposition slice D — "register diet". Independent of
the A→B chain (#579→#583) and of slice C (#580); not probed at intake (D-28: "bounded data
triage"). Pre-flight ledger: none filed for #581 specifically; `.claude/pipeline-state/567-ledger.md`
is the parent receipt the ticket cites — D-9 through D-11 are binding input here, D-13/D-23
place this slice, D-28 records the intentional probe skip. No sequencing dependency on #579,
#580 or #583 landing first; measured fresh against `main` regardless.

## Problem

Two register-rot classes, both raised by the ticket:

1. **`tools/mutation-catalog.tsv` rows are sed programs anchored by literal line content**
   (id, guard, sed, note). D-3's PATTERN ADDRESSES ONLY rule already forbids bare line
   addresses, but a pattern anchored to prose that later gets reworded for non-behavioral
   reasons still drifts — `tools/mutation-sweep.sh:1859-1860` treats that as **anchor drift =
   red**, correct behavior that is nonetheless an ongoing tax on whoever next edits the guard.
2. **The "earn-your-keep" rule**, read literally ("each register row must name the regression
   class that ONLY IT catches, with a dated incident"), is not written into any contract surface
   today — `grep -rn "earn-your-keep"` outside the ticket/ledger prose returns nothing. Applied
   literally it would delete baseline rows whose entire content is "this site is unkillable by
   construction," which reds later sweeps on known-benign survivors (D-10).

## What this slice measured

**Every catalog row is currently live.** A mechanical replay of `mutation-sweep.sh`'s own three
catalog checks (sed exit code, byte-identical-output, `bash -n` validity — `tools/mutation-sweep.sh:1850-1866`)
against all 66 data rows in `tools/mutation-catalog.tsv` on this branch's base found **zero**
anchor-drift, zero invalid-sed, and zero `bash -n` failures. No guard path is missing. The
per-row result table is in the PR body, not duplicated here — this file states the rule the
table was produced under.

**Earn-your-keep, applied non-literally per D-10, culls nothing further.** D-10 already
resolved that the literal "dated incident" reading is not applied; the rows it would have culled
(baseline rows reading only "unkillable by construction") are deleted as a *consequence* of
slice A/#579, not by this test. Applied to its actual scope — catalog rows and execution
surfaces — the test is "does the row's `note` name the regression class a survivor would mean":
every one of the 66 catalog notes already does this (that discipline predates this ticket — see
the header's THE LOUD RULE / PATTERN ADDRESSES ONLY blocks). No catalog row is dropped on this
basis either.

**`tools/mutation-exclusions.tsv` already satisfies AC-3.** Two of its four rows
(`_effective-registry.sh`, `install-gh-bot.sh`) cite CLAUDE.md's "Genuine exceptions" register
as their origin, ending "Origin: CLAUDE.md, not this file," exactly matching CLAUDE.md's own
"This register is authoritative" paragraph. The other two (`.claude/tools/second-shift-doctor.sh`,
`tools/mutation-sweep.sh`'s recursion guard) are named by CLAUDE.md itself as having no
counterpart there ("local operator tooling, the sweep's own recursion guard... the sweep's
alone"). This slice verifies the property; no row moves.

## What this slice does

Since no catalog row needs re-anchoring or dropping, and the exclusions file is already
correct, the register-diet work here is **entirely a documentation fix**: writing the
earn-your-keep rule into a contract surface for the first time, scoped so a future reader
cannot apply it literally and red the sweep — which is the state that let the ticket's literal
reading exist unchallenged in the first place.

- `docs/testing.md`'s "Test-the-tests: the mutation sweep" section gains a paragraph stating
  the rule, the two row kinds it binds (catalog rows, execution surfaces), and the one kind it
  is exempt from (baseline rows recording unkillable-by-construction), citing D-10's reasoning
  for the exemption.
- `CLAUDE.md`'s "Test-the-tests." paragraph gains one sentence pointing at the rule and its
  scope, consistent with that paragraph's existing "Full contract: docs/testing.md" pattern —
  it summarizes, it does not duplicate.

No code path changes. `tools/mutation-catalog.tsv` and `tools/mutation-exclusions.tsv` are
unedited by this PR — the register mass for those two files is unchanged, stated with the other
two (which this slice does not touch) in the PR body per AC-4.

## Acceptance criteria

- **AC-1 — every catalog row is triaged, per row.** All 66 rows in `tools/mutation-catalog.tsv`
  are classified as (a) anchor still stable, (b) re-anchored to a more stable literal, or
  (c) DROPPED with reasoning — stated as a per-row table in the PR body, not in aggregate. This
  slice's measurement (see above) classifies all 66 as (a); the table names the mechanical check
  each row passed.
- **AC-2 — a DROPPED row states what regression class is lost.** Conditional: no row is DROPPED
  by this slice (AC-1's result), so this AC is vacuously satisfied. Stated explicitly in the PR
  body rather than left silent, per D-24's process lesson on interleaved judgment.
- **AC-3 — exclusions rows still cite their origin.** Both `tools/mutation-exclusions.tsv` rows
  that restate CLAUDE.md's coverage register still end "Origin: CLAUDE.md, not this file," and
  no row asserts an independent rationale for an entry CLAUDE.md owns. No pair moved; the PR
  body states this rather than assuming it.
- **AC-4 — register mass re-derived, not quoted.** The PR body states today's line counts for
  all four registers (`tools/mutation-baseline.tsv`, `tools/mutation-catalog.tsv`,
  `tools/mutation-pair-map.tsv`, `tools/mutation-exclusions.tsv`), measured at build time, next
  to the parent ticket's stale filing-time figures — not a substitute for them.
- **AC-5 — the earn-your-keep rule is written into a contract surface, scoped.** `docs/testing.md`
  states the rule, names the row kinds it binds (catalog rows, execution surfaces), and names
  the exempt kind (baseline rows recording an unkillable-by-construction site) — so the next
  reader cannot apply it literally and red the sweep the way an unscoped reading of the ticket
  would have.
- **AC-6 — no baseline row is deleted by this slice.** `tools/mutation-baseline.tsv` is
  byte-identical before and after this PR; baseline shrink is slice A's (#579), and
  double-counting the same deletion across two slices would overstate both.

## Non-goals

- #248's pair-map liveness lints (parked by the parent ticket).
- Any change to the catalog TSV schema (D-11 struck the function/behavior-key column).
- Baseline rows (slice A's territory).
- The moat: nightly sweep of record, merge boundary, never-self-merge.
