# second-shift #431 — the nightly sweep reports survivors its own selftests kill

## Problem

`tools/mutation-sweep.sh`'s parallel verdict pool can score a mutant `SURVIVED` that the
mutant's own paired selftest demonstrably kills. A baseline-absent survivor is the only
thing that reds the lane, so a fabricated one reds the nightly and accuses an innocent
guard. Two such verdicts landed in one nightly (`lean-reconcile.sh::cmp-z::1`,
`check-lean-chain.sh::cmp-z::2`) on the same idiom a third guard killed in the same run —
which is what proves the verdict is not a property of the mutated construct.

The false-`SURVIVED` path inside the pool is **not** isolated, and isolating it is a
separate ticket. This one ships the oracle: before a survivor is allowed to red the lane,
re-derive it serially, outside the pool.

## Scope

Binding input: `.claude/pipeline-state/431-ledger.md` (D-1 … D-13, OR-1, OR-2).

**Not in scope** (D-1): isolating the pool race. **Not in scope** (D-12/OR-1): the
false-KILL direction — this gate re-verifies survivors only, because survivors are the only
class that reds. A mutant the pool wrongly scores KILLED reports coverage that does not
exist and no lane complains; closing that symmetrically means re-verifying every kill,
roughly doubling the sweep, and is not worth paying before the race is isolated. The
asymmetry is a known open flank, stated in the PR and inherited by the isolation ticket.

**Cache hits are out of the re-verify set**, and the reason is not only cost. A cached
verdict was not produced by this run's pool, so attributing a `pool disagreement` to it
would name a path the pool never touched; the cache is inert in every enforcing lane
(`GITHUB_ACTIONS`) and in seed mode, so the nightly this ticket exists for is fully
covered either way; and a pool-scored survivor is exactly the set whose kill suites this
run *prechecked green*, since a guard with no uncached mutant is never prechecked. Feeding
an unprechecked suite to the oracle would let a broken suite fabricate the correction.
`MUTATION_SWEEP_CACHE=0` remains the documented escape for a locally-doubted survivor.

## Acceptance criteria

**AC-1 — Serial re-verify of a survivor that would red the lane.** In the sweeping modes
(`--mode full` and `--mode pr`; merge mode never sweeps and never reads the baseline, D-4),
phase 5 re-verifies each survivor this run's pool scored that is absent from the committed
baseline — and, in seed mode, every pool-scored survivor (D-3). The re-verify re-installs
the mutant blob and re-runs the guard's **full ordered kill set**, because a survivor means
no suite in the set killed and re-running one is not equivalent (D-5). It runs **serially,
exactly once, on a sandbox created for it and never used by a pool worker** — the pool is
the suspect, so the oracle must not use it (D-6).

**AC-2 — Disagreement is a named infra red.** When the re-verify kills a mutant the pool
scored `survived`, the run reds with a `pool disagreement` line naming the mutant and
stating that the harness, not the guard, is at fault, and records the corrected `killed`
verdict. The mutant does **not** also produce a `baseline-absent survivor` red (D-2).

**AC-3 — Agreement changes nothing.** When the re-verify also survives, the mutant's
verdict, its report row, its `baseline-absent survivor` red and the run's exit status are
byte-for-byte what they are without this change.

**AC-4 — Zero cost on a green run.** A non-seed run with no baseline-absent survivor
executes no additional paired suite; the run's own timing line reports the same
verdict-computed count as the same run before this change (D-3).

**AC-5 — Seed mode is gated before the baseline write.** In seed mode the re-verify runs
before the baseline is emitted, so a corrected verdict never reaches the file `--seed`
writes (`--baseline-out` or `tools/mutation-baseline.tsv`) (D-7).

**AC-6 — Report coherence.** A corrected verdict moves the guard's `killed` and `survived`
counts in the report TSV and drops the mutant from that row's `survivor_ids`, so the
operator-facing report does not contradict the red it ships beside (D-8).

**AC-7 — Cache coherence.** A corrected verdict overwrites the pool's `cache_put` record
for that mutant, so a later advisory run is served `killed` rather than replaying the lie
(D-9). Scope: advisory lane only, since the cache self-disables when enforcing and in seed.

**AC-8 — A regression guard that fails on the pooled path.** `tools/mutation-sweep-selftest.sh`
gains a case whose fixture killer is **deterministically flaky against the mutated guard** —
a marker file makes its first run against the mutant exit 0 and its second exit 1 — so the
pool scores `survived` and the serial oracle scores `killed` with no timing dependence. The
case asserts the flip and the named red (AC-2), the corrected report row (AC-6), the
zero-extra-suite-run property on a green run (AC-4), and the seed-before-write ordering
(AC-5). The race itself is un-isolated and therefore not directly testable; the guard covers
the mechanism (D-10).

**AC-9 — The exit contract says so in both copies.** `pool disagreement` is added to the
"Red only for:" list in `tools/mutation-sweep.sh`'s header **and** to the named-infra list
in `docs/testing.md`, in this diff; the runbook gains an entry telling the operator that the
fix is the harness, never a baseline row. No new `scripts/lockstep-manifest.tsv` row — the
pair is a shell comment against a prose paragraph, not byte-anchorable, and the manifest
carries no row for it today (D-11).

## Design

Design: none — this is a shell test-harness change with no rendered surface; the repo
configures no `design.provider`.

## Notes

- `tools/mutation-sweep.sh` carries a `tools/mutation-exclusions.tsv` row (self-sweep
  recursion guard), so editing it re-keys no survivor ordinals and obliges no re-baseline.
- OR-2 (post-landing red rate) stays open: three data points against an un-isolated race is
  not a rate. If the disagreement red fires most nights the pressure lands on the isolation
  ticket, which is the intended outcome; downgrading it to a warn would be the disposition
  D-2 rejected and must be a recorded decision, not a quiet edit.
