# #629 — a committed bound on the un-deferred sweep

`tools/selftest-slow-suites.tsv` keeps milestone 3's local sweep inside the harness's ~120s reap by
deferring every suite measured at or above its threshold. Membership is a measurement taken once,
and the rule that keeps it true — *re-measure when you change what a listed suite does* — is a
sentence in the file's own header. Nothing enforces it, so a new or grown untabled suite walks the
un-deferred sum back toward the reap, where milestone 3 is not slow but **unpassable**.

The table already reds in the opposite direction: a row naming no discovered suite is a hard error.
This is that guard's missing-row counterpart.

`tools/run-selftests.sh` measures and judges nothing. A new `tools/check-sweep-bound.sh` judges, on
the nightly wholesale lane alone.

## Acceptance Criteria

- **AC-1** — WHEN `tools/run-selftests.sh` runs a suite THEN its elapsed seconds appear on that
  suite's existing frame line, on every lane, and the runner's exit-code contract (it names every
  failing suite and reds on a discovered/ran mismatch) carries no behavioral change. Proven by
  selftest.
- **AC-2** — `tools/check-sweep-bound.sh` computes the un-deferred serial sum from emitted timings
  and the committed table, and reds when it exceeds the committed baseline by more than the stated
  allowance. The red names the sum, the baseline, the drift, the largest contributors, and both
  remedies. Proven by selftest against fixtures on both sides of the line.
- **AC-3** — WHEN an un-tabled suite is at or above the table's declared threshold AND the
  aggregate is within allowance THEN the checker prints a named warning and exits 0. A per-suite
  overage alone never reds.
- **AC-4** — WHEN the timing input is absent, unparseable, incomplete over the un-deferred set, or
  names a suite discovery did not produce THEN the checker reds. There is no arm on which a checker
  that cannot read its input exits 0.
- **AC-5** — The check runs in `nightly-guards.yml`'s wholesale `--full` lane and **nowhere else**;
  a repo-wide scan of `.github/workflows/` finds no other invocation. Proven by selftest.
- **AC-6** — Mutation obligations land in this diff: the new guard carries a
  `tools/mutation-catalog.tsv` row naming the regression class it alone catches, and any generic
  survivor the sweep produces is re-mutated per site before it is baselined.
- **AC-7** — `docs/testing.md`'s slow-suite table section states the bound guard: what it reads,
  where it runs, and what a re-baseline is. The membership rule stops being described as unenforced.

## Design notes

**The threshold has one home.** The table's 9s membership rule was prose. It becomes a
machine-readable `# threshold-seconds` directive in the table itself, read by the checker and
skipped by the runner's existing comment arm. The header prose points at the directive rather than
restating the number, so there is no second copy to drift.

**Top-level frames only.** `run-selftests-selftest.sh` nests runners over fixture trees, so its
captured output carries `::group::` lines naming suites that do not exist in this repo. The checker
walks the replay with a depth counter and reads only frames at depth 0. A depth that goes negative
is unparseable input, not a recoverable state.

**Elapsed sits between the status word and the suite path.** The suite stays the last
whitespace-separated token of a `pass`/`cached` frame, which is what the existing contiguity walk
in `run-selftests-selftest.sh` reads it as.

**A sub-second suite is charged one second.** The consumer is a sum over ~60 suites; rounding the
small ones to zero would let the set grow by half a minute without the total moving. Both the
baseline and the checked sum come through this emitter, so they are commensurable.

**"Largest contributors", not "largest growers".** The baseline record is the aggregate (D-3), so
no per-suite delta exists to rank. The breach message names the largest un-deferred suites in the
run — which is what the reader must act on — and says so rather than implying a delta it cannot
compute.

## Out

The PR lane; the table's membership rule and its threshold; any mid-flight scheduling decision;
`tools/selftest-cache-inputs.tsv` and the pass cache.

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | What signal the bound guard reads | Per-suite wall-clock elapsed, in the nightly wholesale lane only. A central cost-declaration registry was considered and rejected: a file every PR appends to conflicts by construction and goes blind to suites nobody registered. | user-answered |
| D-2 | What happens when the guard fires | Hard red only on aggregate breach, which is the quantity that actually breaks milestone 3. A single suite over the table's threshold with the aggregate still inside allowance prints a named warning and exits 0. | user-answered |
| D-3 | What the aggregate is compared against | Drift from a committed baseline of the un-deferred serial sum (98s as measured 2026-08-20), not a fixed constant and not the reap bound. Re-baselining is an explicit reviewable commit. | user-answered |
| D-4 | Who measures and who judges | `tools/run-selftests.sh` emits elapsed on its existing per-suite frame line and judges nothing; a separate `tools/check-sweep-bound.sh` decides. CLAUDE.md pins the runner's exit-code contract (it names every failing suite and reds on a discovered/ran mismatch), and folding "a suite got slow" into that status would conflate two failure classes. | codebase-derived |
| D-5 | Serial sum rather than observed wall time | The nightly lane runs with the slow-suite table opted out, so the un-deferred subset's wall time is never observed there — only per-suite times are. A serial sum is also immune to lane-concurrency skew, which the operator measured directly: the same sweep ran at two different job counts the same night because the gate scales parallelism to live lane count. See https://github.com/manoldonev/second-shift/issues/566#issuecomment-5367888488 | codebase-derived |
| D-6 | Behavior when the checker cannot read its input | Red, never exit 0. Absent, unparseable, or naming a suite discovery did not produce all red. The repo already refuses this shape class in `scripts/check-fail-open-shapes.sh`, and "could not look" must not pass for "looked and found nothing". | codebase-derived |
| D-7 | Sequencing against #566 | Filed as a follow-up sequenced after #566, not folded into it. `tools/selftest-slow-suites.tsv` does not exist on main — it arrives with PR #621, which is in review at needs-work round 2 with two implementation blockers. Adding an AC to a mid-review PR costs rounds on work orthogonal to its own blockers. | codebase-derived |
| D-8 | Queue label withheld at intake exit | `ready-for-dev` is deliberately NOT set. The substrate this guards does not exist on main, so a queued ticket would be picked up against a tree without the table. The label is a manual operator edit at the moment PR #621 merges. | codebase-derived |
| D-9 | Build model | `sonnet`. Basis: calibrated against the nearest recent tickets of the same class — #581 (catalog anchors rot against line content) and #582 (an all-deferred PR sweep exits 0 having graded nothing), both guard-file changes carrying mutation obligations, both built on sonnet. Scope here is one emitter change, one new checker with its own selftest, and one workflow wiring; the fiddliness is procedural rather than design. | codebase-derived |
| D-10 | The drift allowance percentage | deferred under OR-1 (owner: build session, resolved when the baseline is re-taken on the implementation-time tree) | deferred |
| D-11 | OR-1 resolved — the allowance is 15 percent | The un-deferred set has changed since 2026-08-20 (67 suites discovered then, 72 now), so the seed was re-taken through the new emitter rather than inherited. Two measurements of the identical tree landed 6 percent apart — 112s on the ubuntu runner, 119s on an arm64 macOS workstation over the same 59 suites — because roughly two thirds of the set is pinned at the one-second floor and the variance lives in a short tail. 15 percent therefore sits comfortably above ordinary noise. It is also roughly two threshold-crossing suites: one alone is about 8 percent of the baseline and is already named by AC-3's warning, so the aggregate reds on a genuine drift rather than on the first arrival. A reversible default: too tight reds an honest nightly and is noticed the next morning, too loose degrades to today's unguarded state. | user-delegated |
| D-12 | Which lane the baseline is measured on | The nightly ubuntu wholesale lane, the one lane that enforces it — not this workstation. A baseline describes the lane that checks it, and seeding from a different machine class would put an unexplained constant into the first honest nightly. The seed is taken from a `workflow_dispatch` of `nightly-guards.yml` on this branch, and the record names the lane so a later reader can tell a real red from a re-measurement on other hardware. | codebase-derived |

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | The drift allowance the aggregate breach reds on | resolved by D-11 |
