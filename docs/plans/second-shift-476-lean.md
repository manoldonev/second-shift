# #476 — a staged-lane capability cannot be deleted without a recorded disposition

## Problem

`#348` deletes the staged lane. Its parity story is **per-artifact** (an orphan check keyed on
deleted paths, plus a stage-only config-key enumeration) and carries no concept of a *capability*.
So a behavior whose only implementation lives inside a stage doc — a produced artifact, a gate
verdict, a review dimension — can be deleted with nothing red, and nothing anywhere records that
the deletion was a decision rather than an oversight.

This ticket builds the machine-readable register of those capabilities and the guard that makes
`#348`'s deletions answerable to it. The blocking edge on `#348` was recorded at ticket creation
(a tracker mutation, not part of this diff — pre-flight D-19).

## Design

Design: none — this ticket ships a TSV register, a shell guard, its selftest, and one CI step. No
rendered surface, and the repo configures no `design.provider`.

## Binding pre-flight input

`.claude/pipeline-state/476-ledger.md` (from the `#465` intake). Every `D-n` below is transcribed
from it; none of them overrides the issue as filed — the receipt and the issue agree.

| ID | What it binds here |
| --- | --- |
| D-1 | Mutation row's disposition is `ported` to the repo-carried `tools/mutation-sweep.sh` seam; `lean-gate.sh`'s D-18 block is the executor. Starter recipe out of scope (OR-1), flagged in the row note. |
| D-2 | Visual-capture row is `dropped`; `extraLanes` is the documented consumer home; key retirement is `#348`'s. |
| D-3 | Doc-update row is `dropped`; `doc-updater` stays an on-demand review-toolkit agent. |
| D-4 | This ticket lands first; the `#348` blocking edge is already on `#348`'s body and is not part of this diff. |
| D-7 | TSV register + paired guard + same-named selftest in `tools/`, modeled on `tools/mutation-exclusions.tsv`; columns `capability \| staged implementation path(s) \| disposition \| lean home / decision note`. |
| D-14 | Rows are behavior/capability-level; the guard's coverage check is **file-level**; no stage doc is edited. |
| D-15 | Disposition enum is `ported \| dropped \| already-covered \| choreography`. |
| D-16 | Guard is a transitional deletion gate **and** a permanent register lint; every row is enum-validated unconditionally; post-`#348` the coverage clause is vacuous by design (documented in the guard header); rows are permanent record. |
| D-17 | Path cells enumerate every implementing artifact of a behavior (stage doc + `skills/run/**` tools + workflow `.mjs`); the guard's file universe stays `stages/*.md`. |
| D-18 | Explicit `ci.yml` step in the same job as the `check-lockstep-pairs.sh` contract step. |
| D-19 | No AC for the `#348` blocking edge — a tracker mutation is not diff-verifiable. |
| D-30 | Walk-surfaced (non-seeded) rows are proposals, listed under a **Proposed dispositions** heading in the PR body; landing after review ratifies them (OR-3). |

OR-1 and OR-3 are both `reversible-default-and-flag` — neither blocks milestone 1.

## What ships

### 1. `tools/capability-parity.tsv`

One row per capability, TAB-separated, four columns. **Register-worthy** iff removing the behavior
changes what a consumer run *produces or verifies* (an artifact, a gate verdict, a review
dimension) — as opposed to how the run choreographs itself.

Enumerated by walking `plugins/dev-pipeline/skills/run/stages/1-intake.md` … `10-cleanup.md` in
full. The four seeded dispositions (mutation → `ported`, visual capture → `dropped`, doc update →
`dropped`, design-fidelity + a11y → `already-covered`) are settled intent and appear with those
values. Every other row is a proposal derived from the precedents: pure choreography →
`choreography`; a demonstrated lean-native home → `already-covered` naming it; anything else →
`dropped`.

`choreography` is a first-class value, not a synonym for `dropped`: it records a death that is
*by nature* (the stage machine's own bookkeeping cannot outlive the stages), where `dropped` is a
real consumer-visible capability deliberately given no lean home.

Rows also carry the **config-key consequences** (`unitTestScope`, `gates.mutation`, `testFile`,
`stageParams.visualCapture`, `stageParams.inertPattern`, `planGates`, `implementDelegates`) so
`#348`'s config-schema assessment can execute retirement under the dead-key pattern. No config key
is touched here.

### 2. `tools/capability-parity-check.sh` + `tools/capability-parity-check-selftest.sh`

Four unconditional red conditions:

1. a malformed row (not exactly four fields, or an empty capability / path / note cell);
2. a duplicate capability name;
3. a disposition cell that is empty or outside the enum — **always**, not only when its paths are gone;
4. an existing `stages/*.md` file named by no row's path cell.

Condition 4 is file-level by design (D-14): behavior-level completeness *within* a covered file is
the enumeration PR's ratification obligation, and a doc-anchor check would buy integrity without
completeness while adding a prose-presence guard the repo's testing rules forbid.

Lifetime is documented in the guard header: it gates `#348`'s deletions, then remains as the
register's shape/enum lint. Once the stage docs are gone the coverage clause is vacuous **by
design** — rows are permanent record and are never removed when their staged paths die.

The guard takes the register path and the stages dir as optional positional arguments so the
selftest can drive it over fixtures; both default to the real repo paths.

### 3. CI wiring

One explicit step in the same `ci.yml` job that runs `bash scripts/check-lockstep-pairs.sh` — the
precedent for this guard class. The selftest needs no registration (glob-discovered).

## Acceptance criteria

- **AC-2** (oracle) — every staged-lane capability carries an explicit recorded disposition in
  `tools/capability-parity.tsv`, and `#348` cannot land a deletion whose capability has none:
  removing a `stages/*.md` file that no row names reds `tools/capability-parity-check.sh`.
- **AC-5** — the register has one row per capability (behavior-level, per the register-worthiness
  rule above) covering all of stages 1–10; every disposition is from the closed four-value enum;
  the four seeded rows appear with their settled dispositions; every proposed (non-seeded) row is
  listed in the PR body for ratification.
- **AC-6** — the guard runs as an explicit CI step in the `check-lockstep-pairs.sh` job, and its
  same-named selftest proves the red paths: a disposition outside the enum reds; an uncovered
  `stages/*.md` file reds; a malformed row reds. (The duplicate-row red is proved alongside them.)

## Out of scope

- Any edit to `config-grill.sh` or onboard prose (sibling ticket `#477` under the same parent).
- Any edit to the stage docs themselves.
- Any config-key retirement — owned by `#348`, informed by this register.
- A starter/reference `tools/mutation-sweep.sh` recipe for co-located-unit-test consumers
  (OR-1 — follow-up candidate, flagged in the mutation row's note).

## Verification

```bash
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
bash tools/capability-parity-check.sh
bash tools/capability-parity-check-selftest.sh
bash tools/run-selftests.sh --exclude tools/install-topology-selftest.sh
```
