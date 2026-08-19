# Milestone 3 runs the same diff-scoped mutation sweep that PR CI already runs

Closes #580. Part of #567.

Binding input: `.claude/pipeline-state/567-ledger.md` — the epic's pre-flight receipt, cited by
the ticket body (D-2, D-7, D-8, D-9, D-10, D-11, D-12 in that ledger's numbering). There is no
`.claude/pipeline-state/580-ledger.md`; the slice's settled decisions were carried into the
ticket body verbatim and are restated below. No Open Region in that ledger belongs to this slice
— OR-1 is slice A's (#579, landed).

Design: none — `.claude/second-shift.config.json` declares no `design.provider`, so no RS rows
exist to arm.

## What this deletes and why

`lean-gate.sh`'s milestone 3 carries decision **D-18**: a diff-scoped mutation sweep, invoked as
`tools/mutation-sweep.sh --mode pr --base "origin/$BASE_BRANCH"` when the target repo carries a
sweep, and a printed `SKIPPED` notice when it does not. That is the **identical invocation** the
`mutation-sweep-pr` CI job already makes (`.github/workflows/ci.yml`), so the in-session lane is
CI-duplicated work idle-blocking a build session on a contended machine. The merge boundary
re-derives the same truth for free.

The duplication was measured, not assumed (ledger D-2): over 28 distinct branches
(2026-08-11..18), 17 of 22 guard-touching PRs produced 11–71 verdicts each at ~5s wall. PR-mode
**stays** — this slice deletes the in-session caller only.

## Acceptance Criteria

- **AC-1:** WHEN milestone 3 runs THEN no mutation sweep is invoked, and neither the
  `milestone-3: mutation sweep (diff-scoped)` line nor the
  `mutation-sweep.sh absent — mutation sweep SKIPPED` notice is emitted — on any tree, whether or
  not it carries `tools/mutation-sweep.sh`. The `| milestone-3 | skipped | mutation-sweep.sh
  absent` progress row is likewise never written again.

- **AC-2:** WHEN the D-18 block is deleted THEN every **live** statement of the D-18 contract is
  updated rather than orphaned. The enumerated set, derived by grepping the tree rather than
  quoted from the ticket:

  | Surface | Statement being repaired |
  | --- | --- |
  | `plugins/dev-pipeline/skills/build-lean/lean-gate.sh` | the D-18 block itself, its `sweep` local, and the four in-file comments that order other lanes relative to it (the `lane_failure_class` scoping note, extraLanes' AC-6 placement note, the zero-lane guard's two notes, and the design live-render's placement note) |
  | `CLAUDE.md` | "Test-the-tests" — states where the sweep runs |
  | `docs/testing.md` | "Where it runs" under *Test-the-tests: the mutation sweep* |
  | `docs/config-schema.md` | the `gates` row's `mutation` description |
  | `schema/second-shift.config.schema.json` | `gates.mutation`'s `description` |
  | `docs/onboarding.md` | the repo-carried-sweep section ("yours to carry and ours to run") |
  | `docs/live-render.md` | "Milestone 3, after `extraLanes` and before the mutation sweep" |
  | `docs/migrations/v1-to-v2.md` | the `unitTestScope` retirement note, which asserts present-tense gate behaviour |
  | `plugins/dev-pipeline/tools/config-lint.sh` | the `unitTestScope` rejection message |
  | `plugins/second-shift/skills/onboard/tools/config-grill.sh` | the T1/T4 mutation-seam rationale comments |
  | `plugins/second-shift/skills/onboard/SKILL.md` | question 4's mutation prose |
  | `plugins/second-shift/skills/onboard/tools/config-grill-selftest.sh` | the "ONE owner … the green gate executes" comment |
  | `plugins/second-shift/skills/doctor/tools/doctor-selftest.sh` | the T1/T4 fixture rationale comments |
  | `plugins/second-shift/skills/doctor/tools/doctor-fixtures/config-t1-waived.json` | the waiver reason naming "the green gate SKIPPED notice" |

  **Frozen historical records are NOT rewritten**, and this is a deliberate disposition rather
  than an omission: `docs/plans/acme-303.md` (which carries the original `| D-18 | Mutation sweep
  |` ledger row), the other `docs/plans/*` files, and `CHANGELOG.md` are records of what was
  decided when they were written. `docs/plans/acme-303.md` has not been touched since the commit
  that authored it (`1e2d7f7`, #307) across every subsequent gate change, so leaving it is the
  established convention, not a lapse. The D-18 *identifier* dies with the code; the record that
  it was once decided stays true.

- **AC-3:** WHEN `lean-gate-selftest.sh` runs THEN the cases that exist only to drive this lane
  are gone, not left asserting a deleted behaviour:
  - case **(i)** "D-18: mutation sweep absent is a printed skip" is deleted, along with the block
    header comment's claim that the block is "about the mutation-sweep notice". The `(i-392)`
    allowUnverified cases that share its captured output survive unchanged.
  - case **(dj1)** re-anchors: it currently proves the milestone-3 body ran in a detached process
    by finding `mutation sweep SKIPPED` in both the runner's log and the waiter's stdout. It must
    key on a surviving body-emitted line instead, so it still proves both halves.
  - case **(i7)** — the AC-6 ordering case — is **re-stated, not weakened**. `fixed keys ->
    extraLanes -> mutation sweep` loses its final term; the replacement third term is milestone
    3's own terminal pass line, so the case still asserts three ordered observables and still
    fails if extraLanes migrate out of their slot.

- **AC-4:** WHEN `scenario-liveness-selftest.sh` runs THEN no composed verdict path routes
  through a deleted gate. Verified by grep at build time: that suite contains **no** reference to
  the mutation lane, so no scenario composes a milestone-3 verdict through it. The evidence
  (`grep -n 'mutation' scenario-liveness-selftest.sh` returning nothing) is recorded in the PR
  body; this AC is discharged by verification, and any hit found at build time is repaired.

- **AC-5:** WHEN the PR is opened THEN the breaking verb is in the **TITLE** (`feat!:` — ledger
  D-8: a behaviour is removed from a shipped gate whose `rc != 0` path calls `fail_milestone 3`,
  and this repo's precedent for shipped-gate deletions is `type!:`, per #348/#577), and the
  `Changelog:` trailer carries the `Migration:` line: a consumer repo carrying its own
  `tools/mutation-sweep.sh` must wire its own nightly sweep, because the shipped gate no longer
  runs one.

- **AC-6:** WHEN `gates.mutation` is considered THEN the PR states the disposition explicitly.
  **The key SURVIVES.** Grounds:
  1. It never armed the deleted lane. D-18 branched on `[ -f "$sweep" ]` — the file's presence,
     never the config key. Retiring `gates.mutation` would therefore delete something the
     deletion does not reach.
  2. Its live readers are advisory and keep working: `config-grill.sh`'s `T4.mutation-plumbing.*`
     (declared intent vs. shipped plumbing) and `T1.mutation-sweep.*` (a test lane with no
     sweep), both surfaced through `/second-shift:doctor`, plus `config-lint.sh`'s `gates`
     allow-list. None of them reads the gate.
  3. Precedent is on the record: #574's D-5 kept it for exactly this reason.
  4. The #569 failure mode is a **dead** key that silently disarms a consumer's blocking gate.
     `gates.mutation` arms no gate before this change and arms no gate after it — it is a
     declared-intent signal graded by advisories, so the class does not apply.

  What changes is only the *rationale prose*: every reader that justified the key by "the green
  gate runs your sweep" is rewritten to say the seam is repo-carried **and repo-run**. That
  rewrite is inside AC-2's set.

- **AC-7:** WHEN the mutation registers are considered THEN the PR proves whether the deletion
  re-keys any baselined survivor ordinal, rather than asserting it does not. CLAUDE.md's
  test-the-tests obligation binds every guard edit; this diff edits a guard. The claim to be
  proven: `tools/mutation-baseline.tsv`'s three `lean-gate.sh` rows are all `default::n`, whose
  sites sit far **above** the deleted block, and `tools/mutation-catalog.tsv`'s `lean-gate.sh`
  rows are pattern-addressed and none anchors the deleted lines — so no register row changes.
  Evidence is a replayed site enumeration, not an argument.

## Non-goals

- `--mode pr` in CI. It **stays** (ledger D-2). This slice deletes the in-session caller only.
- #566's supervision stratum (the detached runner, marker file, rejoin, `INTERRUPTED_BUDGET_M3`,
  `m3_joinable`, the lane-registry ceiling). #566 is open at `needs-spec-work`, unassigned, and
  not in flight; it owns milestone 3's local **selftest** sweep. Adjacent, not duplicate
  (ledger D-12). `(dj1)`'s re-anchor touches that stratum's suite but not its behaviour.
- The moat: the nightly sweep of record, the merge boundary, never-self-merge.
- Shipping a consumer nightly template (ledger D-7): nothing new ships. `tools/mutation-sweep.sh`
  exists only at this repo's `tools/`; no plugin ships it and the consumer template set carries
  no mutation workflow, so D-18's `[ -f "$sweep" ]` branch already takes the printed-skip path in
  every consumer repo today. A template would be a net ADD serving zero current consumers, which
  the 2026-08-16 deletion doctrine forbids.

## Collision note

**PR #593 (issue #583, open)** re-keys survivor ids from position to content and edits
`CLAUDE.md`, `docs/testing.md`, and all four mutation registers — three surfaces this diff also
touches. It does **not** touch `lean-gate.sh`. Whichever lands second rebases; if #593 lands
first, AC-7's evidence is re-derived against the content-keyed scheme rather than the positional
one.

**#566** edits the same milestone-3 block but is not in flight (see Non-goals).
