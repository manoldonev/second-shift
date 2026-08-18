# 517 — reconcile the committed lean spec against the pre-flight Decision Ledger

**Issue:** [#517](https://github.com/manoldonev/second-shift/issues/517)
**Pre-flight receipt:** `.claude/pipeline-state/517-ledger.md` (19 rows, 8 of them `intent`)

## Problem

A lean run's pre-flight Decision Ledger — the receipt an operator paid an interview for — is
binding input to the build role, and nothing checks that the committed spec carries it. Three
rows of an eight-row receipt were dropped on the founding incident: a test-strength precondition,
an already-accepted cost, and a reversed decision that the spec re-decided the other way without
saying it had. The review session reads the *committed spec*; by the time it looks, the dropped
rows have left no trace to notice their absence against. Nothing in the lane holds the two
documents side by side.

## What this ships

A milestone-1 reconciliation. When `<plansDir>/../.claude/pipeline-state/<issue>-ledger.md`
exists, every receipt row whose Provenance is `user-answered` or `user-delegated` must appear in
the committed spec's `## Decision Ledger` under the same `D-n` id, carrying the same Resolution
text — or carrying a `DEPARTURE — <reason>` in its place.

The reconciliation lives in `ledger-lint.sh` as a new `--reconcile` mode and is reached from
`lean-gate.sh`'s existing `resolve_ledger_lint` seam, so the provenance enum stays single-sited
(`scripts/lockstep-manifest.tsv:370`: "Revisit if a third site starts parsing any of these
enums").

**NON-GOAL, explicitly.** The founding incident's third failure — a spec that faithfully carries
a row whose *test* then asserts something weaker — is out of scope. That is a spec-to-diff gap
and the reviewer's surface; this mechanism reconciles receipt against spec and closes two of the
three failures. Receipt `OR-n` rows are also out of scope: `check_pause_and_ask` (#533) already
gates them.

## Acceptance criteria

- **AC-1** — `ledger-lint.sh` gains a `--reconcile <receipt-path>` mode taking the spec as its
  positional argument. It binds exactly those receipt `| D-n |` rows whose Provenance cell is
  `user-answered` or `user-delegated`, keyed on **provenance and not on the `Kind` cell**: 12 of
  the 41 on-disk receipts predate Kind and carry no such cell, so a Kind-keyed predicate would
  silently no-op on them. The parse reads the 4-column (pre-Kind) and 5-column (receipt) row
  arities alike, since Provenance is the fourth column in both.
- **AC-2** — a bound receipt row with no same-`D-n` row in the spec's Decision Ledger exits 1 and
  names the id. This is the silent-drop failure.
- **AC-3** — a bound row whose spec Resolution differs from the receipt's, compared
  whitespace-normalized and case-sensitively, exits 1 and names the id unless the spec's
  Resolution cell is marked as a departure. This is the unflagged-reversal failure: presence
  alone would leave it on reviewer habit, which is the posture that already failed.
- **AC-4** — a departure is declared by a `DEPARTURE — <reason>` prefix in the spec's Resolution
  cell and the **reason is required**: a `DEPARTURE` marker carrying no alphanumeric reason exits
  1. A departure that states a reason is accepted, and the row stays a legal four-column ledger
  row that #562's provenance lint passes unchanged.
- **AC-5** — a spec whose Decision Ledger states the explicit empty form
  (`No material decisions — all choices codebase-derived.`) against a receipt carrying at least
  one bound row exits 1. This is #503's exact failure, which passes #562's lint clean today: only
  comparing the section against the receipt notices a spec that *claims* emptiness.
- **AC-6** — mode isolation, both directions. A receipt with zero bound rows reconciles clean, and
  `--reconcile` performs no reconciliation work outside the mode: a plain
  `ledger-lint.sh <plan>` and a `ledger-lint.sh --receipt <receipt>` call behave exactly as they
  do today, byte-for-byte in verdict, against a spec/receipt pair that `--reconcile` would refuse.
- **AC-7** — `lean-gate.sh` milestone 1 runs the reconciliation in its **observe pass**, beside
  the #562 lint and `design_state`, since it reads only local files. Its exit codes map onto the
  gate's #532 vocabulary: `0` passes, `1` is `fail_milestone 1` (a fix attempt — editing the
  committed spec is a fix the build role can make, matching #562's classification), and anything
  else is an `envfail`. An **absent** receipt makes the check inert — most tickets never went
  through pre-flight — while an **existing but unreadable** one is an `envfail`, never a silent
  pass: "no ledger" and "a ledger this could not read" are different facts.
- **AC-8** — milestone 1's pass line discloses the reconciliation through `cmd_1`'s existing
  `note` variable, the idiom the design lane already uses for its armed and disarmed states, and
  says nothing extra when no receipt exists.
- **AC-9** — `plugins/dev-pipeline/skills/build-lean/SKILL.md` step 4 states the carry-forward
  obligation. Today it says only that a pre-flight ledger is "binding input when present", so a
  gate demanding a shape the instructions never asked for would burn a fix attempt on every first
  run. Intake-side skills are **not** amended: the receipt's shape does not change, and
  `DEPARTURE` appears only in lean specs, never in receipts.
- **AC-10** — `ledger-lint.sh --help` documents the new mode, and its hand-maintained
  `sed -n '2,Np'` range is re-checked so the header still prints in full and stops before the code.
- **AC-11** — tests, per the tier map. Behavioral cases in `ledger-lint-selftest.sh` for AC-1
  through AC-6 and AC-10; behavioral cases in `lean-gate-selftest.sh` for AC-7 and AC-8; and a
  composed leg in `scenario-liveness-selftest.sh` for the new milestone-1 verdict path, since a
  gate contract nothing composes against is a gate the next `#204` walks through. Editing
  `lean-gate.sh` and `ledger-lint.sh` re-keys their generic mutation survivor ordinals, so
  `tools/mutation-baseline.tsv` is re-baselined in the same diff.

## Flagged defaults (receipt Open Regions, both `reversible-default-and-flag`)

- **OR-1 — exact normalization for AC-3's Resolution compare.** Taken as: collapse every run of
  whitespace to one space, trim the ends, compare **case-sensitively**, and strip no markdown
  (backticks and emphasis are content). Reversible: the compare is one function with its own
  selftest cases, so loosening it after a spurious fire costs an edit, not a redesign. A
  pause-and-ask here would have deadlocked milestone 1 on a detail only implementation surfaces.
- **OR-2 — whether `review-lean` gains a receipt-reading instruction.** Taken as: **no** added
  instruction. The ticket's premise is that nothing in the lane holds the two documents side by
  side; AC-3 makes the gate do exactly that, so a reviewer instruction would be belt-and-braces
  over a mechanized check. Reversible: adding a line to `review-lean/SKILL.md` later costs nothing
  this PR forecloses.

Both are flagged here rather than resolved by an operator comment, which is what their
`reversible-default-and-flag` disposition prescribes.

## Scope boundary against #562 (merged, PR 573)

#562 lints a committed Decision Ledger's **provenance** when the section is present. PR 573's own
commit body carves this ticket out verbatim: "a spec with no Decision Ledger is unaffected, and
that gap is #517's, not this one's." This PR makes the section mandatory when a receipt carries
bound rows; #562's lint continues to validate its provenance, unchanged, on the same call it
makes today.

`.claude/pipeline-state/` is gitignored with zero tracked files, so the receipt is invisible to
CI. This is necessarily a **local milestone-1 gate** and never a merge-boundary one —
`check-lean-chain.sh` could not read the receipt from a CI checkout if it wanted to.

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Which receipt rows the milestone-1 predicate binds | Intent rows only: provenance `user-answered` or `user-delegated`. Keyed on provenance rather than the `Kind` cell, because 12 of 41 on-disk receipts predate Kind while all 41 carry provenance, and interviewing-baseline defines Kind `intent` as exactly those two values | user-answered |
| D-2 | What "carried forward" means in the committed spec | A mandated `## Decision Ledger` section carrying one `D-n` table row per bound receipt row. Reuses the section #562 already lints when present, rather than standing a parallel structure beside it | user-answered |
| D-3 | How a departure is declared, and whether a reason is required | A `DEPARTURE — <reason>` prefix in the Resolution cell, reason REQUIRED. Mirrors the `Design: none — <reason>` disarm and its two-grep idiom at `lean-gate.sh:2871-2876`. The row stays a legal four-column ledger row, so #562's lint passes it unchanged | user-answered |
| D-4 | Whether the gate compares Resolution text or only checks row presence | Whitespace-normalized compare of the spec row's Resolution against the receipt row's. Any difference must carry the DEPARTURE marker. This is what catches the unflagged-reversal class, the founding incident's third failure; presence-only would leave it on reviewer habit, the rung-4 posture the ticket argues already failed | user-answered |
| D-5 | Where the reconciliation lives, and who owns the DEPARTURE vocabulary | A new mode on `plugins/intake-toolkit/skills/plan-interview/tools/ledger-lint.sh`, invoked from `lean-gate.sh` through the existing `resolve_ledger_lint` seam. Keeps the provenance enum single-sited, per the manifest's own instruction at `scripts/lockstep-manifest.tsv:370` to revisit if a third site starts parsing these enums | user-answered |
| D-6 | Whether the PR amends the skill that prescribes the spec | Yes, `build-lean/SKILL.md` step 4 gains the carry-forward obligation. Today it says only that a pre-flight ledger is binding input when present, so a gate demanding a shape would refuse specs the instructions never asked for. Intake-side skills are NOT amended: the receipt shape does not change. SKILL.md is at 47 of its 60-line cap | user-answered |
| D-7 | Whether the receipt's `OR-n` rows are bound too | No, `D-n` intent rows only. Pause-and-ask regions already have a milestone-1 gate that `D-n` lacks (#533's `check_pause_and_ask`), and reversible-default-and-flag regions are surfaced by their own disposition. A second mechanism over a covered surface is what the deletion doctrine refuses | user-answered |
| D-8 | Whether the weakened-test-precondition failure is in scope | Explicit NON-GOAL, stated in the AC set. This mechanism reconciles receipt against spec; a spec that faithfully carries a row whose test then asserts something weaker is a spec-to-diff gap, which is the reviewer's surface. The PR closes two of the three founding failures and says which | user-answered |
