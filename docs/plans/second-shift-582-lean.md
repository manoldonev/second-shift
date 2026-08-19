# second-shift #582 — an all-deferred PR mutation sweep stops reading as green (lean spec)

Issue: https://github.com/manoldonev/second-shift/issues/582
Parent context: filed off the #567 intake audit (2026-08-18); not one of #567's four reshapes,
and explicitly not a re-tuning of `SLOW_THRESHOLD_S` / `PR_FAST_GUARD_CAP` / which guards defer.
No pre-flight ledger filed for #582.

## Problem

`tools/mutation-sweep.sh --mode pr` defers a guard wholesale (multi-suite union, a slow-list
killer, or the `PR_FAST_GUARD_CAP=6` cap) rather than sweeping it under a weaker criterion. That
is correct policy — this ticket does not touch it. But when **every** in-scope guard defers, the
job still exits 0 having graded nothing, and nothing on the PR's check surface distinguishes that
from "swept your guards, found no new survivors". The audit measured this at 23% of
guard-touching PR runs (5/22, all touching `lean-gate.sh`), concentrated on exactly the guards
that change most.

## The fix

In the existing PR-deferral loop (`tools/mutation-sweep.sh`, the block starting
`if [[ "$MODE" == "pr" ]]; then` around the "PR deferral" comment): track the pre-deferral
in-scope count and a per-reason-category count (multi-suite union / slow suite / PR-lane cap)
alongside the existing per-guard `defer` accounting. After the loop, when `PR_SWEPT` is empty and
the in-scope count was nonzero (the empty-diff case already exits earlier, at the existing
"nothing to sweep" branch, so this is genuinely "in scope but every one deferred", not "nothing
touched"):

- Emit one `warn` line (the existing `warn()` helper — WARN-prefixed, counted, distinct from the
  per-guard `info "defer $g -> nightly: ..."` lines already printed) naming the deferred count and
  a reason-category breakdown.
- In enforcing runs (`GITHUB_ACTIONS` set — i.e. real CI, not a local advisory run), additionally
  print a GitHub Actions `::warning::` annotation, and, when `$GITHUB_STEP_SUMMARY` is set, append
  a short block to the job summary. Either is visible on the PR's checks surface without opening
  the raw log; the job conclusion itself stays `success` (this ticket does not attempt a neutral
  conclusion — see "implementer's call" in the AC).

No change to `SLOW_THRESHOLD_S`, `PR_FAST_GUARD_CAP`, deferral eligibility, or the reporting path
when at least one guard sweeps.

## Acceptance criteria

- **AC-1** — when a `--mode pr` run defers every in-scope guard, its terminal output contains one
  unmissable line (the new `warn` call) naming the deferred count and the reason(s), and that line
  is textually distinct from anything a run that swept guards and found no new survivors prints.
- **AC-2** — when a `--mode pr` run defers every in-scope guard under `GITHUB_ACTIONS` (real CI),
  it additionally emits a `::warning::` Actions annotation, and, when `GITHUB_STEP_SUMMARY` is
  set, a job-summary block — both visible on the PR's check surface, so the run is not reported as
  an ordinary silent pass. The job's exit code stays 0 (a red build here would fail runs for
  correctly-deferring guards, which is not the defect).
- **AC-3** — when a `--mode pr` run sweeps at least one guard (the deferred-but-not-all case
  included), its reporting is byte-for-byte unchanged from before this change: no new warn line,
  no annotation, no summary block.
- **AC-4** — `tools/mutation-sweep-selftest.sh` gains falsifiable coverage: a case constructs an
  all-deferred PR run and asserts the AC-1 line is present, and a control case (a mixed
  swept+deferred run) asserts it is absent. Both fail if the line is removed or the gating
  condition is loosened to fire on a partial defer.
- **AC-5 (doc)** — `docs/testing.md`'s "A green PR does not mean a green nightly" passage (the
  paragraph already describing per-guard deferral) gets one added sentence stating that an
  all-deferred run now warns visibly instead of reading as silently green, so the doc does not go
  stale relative to the new behavior.

## Non-goals

- Deleting or weakening `--mode pr`.
- Changing `SLOW_THRESHOLD_S`, `PR_FAST_GUARD_CAP`, or which guards defer.
- Artifact upload for the PR job.
- A neutral/non-success job conclusion — the AC explicitly leaves the mechanism to the
  implementer, and a plain warn/annotation/summary is the smallest change that makes the state
  legible without turning a correctly-deferring run red.
