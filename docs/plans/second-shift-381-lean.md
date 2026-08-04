# The mutation sweep runs an embarrassingly parallel workload on a single core

Spec of record for issue #381. The definition of done is the `AC-n` set below.

## Problem

`tools/mutation-sweep.sh --mode pr` is the slowest step in the lean build loop — ~8–10 min per
`lean-gate.sh 3`, paid once per **fix round** rather than once per PR. The cost is arithmetic and
entirely implementation-bound:

```
wall = Σ over guards ( mutants × paired-suite seconds )     [strictly serial]
     = 10×20s (lean-gate) + 12×8s (lean-reconcile) + 12×17s (check-lean-chain) ≈ 500s + setup
```

Nine of ten cores idle throughout. Three independent levers remove it: **memoize the verdict**
(the only one that reaches "instant"), **parallelize** (one shared sandbox is the only thing
forcing serialization), and **early-exit on kill** (a killed mutant's verdict is known at the
paired suite's first `FAIL:` line).

## Files in scope

`tools/mutation-sweep.sh`, `tools/mutation-sweep-selftest.sh`, `docs/testing.md`, plus this spec
and one new data file under `tools/` for AC-7's serial pins.

**Deliberately NOT `lean-gate.sh`**, so this can run concurrently with in-flight lean PRs that
edit it. `tools/mutation-baseline.tsv` also stays untouched: `mutation-sweep.sh` is self-excluded
from sweeping (recursion guard in `tools/mutation-exclusions.tsv`) and AC-4 requires identical
results, so no guard's ordinals move.

## Acceptance criteria

- **AC-1**: mutant verdicts are cached on `sha256(mutated guard) + sha256(paired suite) + K +
  environment`; a re-run over an unchanged tree performs **zero** paired-suite executions and
  reports the identical survivor set.
- **AC-2**: editing a paired selftest invalidates every cached verdict for its guard — driven by a
  fixture where an added test case turns a cached SURVIVED into KILLED, which is the failure a
  guard-only key would serve stale.
- **AC-3**: mutants run concurrently, each in its own sandbox, bounded by a configurable pool
  defaulting to `min(cores-2, …)`. No mutant observes another's mutation.
- **AC-4**: parallel and serial runs over the same diff produce **identical** survivor sets and
  `applied/killed/survived` counts — a fixture proves it, so the speedup provably costs no
  coverage.
- **AC-5**: a mutant whose paired suite emits `FAIL:` is scored KILLED without running the suite to
  completion, and the early-exit path scores identically to the full run on a fixture covering both
  a first-case kill and a last-case kill.
- **AC-6**: measured wall time is recorded for cold, partial-hit, and full-hit runs — the
  improvement is measured, never asserted from the design.
- **AC-7**: a paired suite that cannot tolerate a concurrent sibling (fixed port/path/temp name) is
  identified and either fixed or pinned serial with the reason recorded, not discovered later as
  flake.
- **AC-8**: the cache is bounded and fails safe: it lives outside the repo, is never committed,
  survives no environment change, and a corrupt or unreadable entry falls back to a real run rather
  than to a pass.
- **AC-9**: sandbox disk is bounded and reclaimed on every exit path, including the killer's
  timeout and population-bound reaps.
- **AC-10**: `docs/testing.md` states what the cache keys on, when it is invalidated, and which
  runs are authoritative (CI) versus advisory (local).
- **AC-11**: the diff stays inside `tools/` and `docs/` — see Files in scope.
- **AC-12**: the PR carries a `Changelog:` trailer.

## Design

### Phase split (what makes AC-4 provable rather than hoped for)

The loop becomes four ordered phases. Everything that decides a *verdict* moves into a pool;
everything that *emits* stays serial and index-ordered, so stdout, the report TSV, and the
survivor set are independent of the pool size by construction.

1. **Precheck pool** — per guard, run every killer against the unmutated sandbox. Produces the
   `unrunnable pair` verdict and the `MEASURED` timings the per-suite killer bound reads.
2. **Enumerate (serial, sandbox 1)** — apply each generic/catalog mutant, run the `bash -n` and
   `git diff --quiet` gates exactly as today, and write the *mutated guard bytes* to a work-item
   blob. Skips, anchor drift and invalid-sed reds are decided here, in today's order.
3. **Verdict pool** — workers pull work items by residue class, each in its own sandbox: cache
   lookup, else install the blob through the guard's inode and run the ordered kill set.
4. **Aggregate (serial)** — read verdicts in item order, emit `report_bound_hit` lines, per-guard
   counts, report rows, and the exit contract.

Sandboxes are created lazily up to the pool size and **reused** across phases: one worker owns one
sandbox for the whole run, restores its guard between items, and no two concurrently-running
mutants ever share one. That is what bounds disk at `pool × ~7 MB` (AC-9) instead of
`mutants × ~7 MB`.

### Cache (AC-1, AC-2, AC-8)

Key = `schema-version + sha256(mutated guard bytes) + sha256(each paired suite's bytes, in kill-set
order) + K + environment`, where environment is the same axis the baseline header already records
(`RUNNER_OS`/`uname -s`, `SKIP_STRESS`) plus the killer-bound knobs, since those change what a
timeout verdict is.

Including the **suite's** bytes is the correctness half, not the fast half: adding a test case can
kill a previously-surviving mutant, so a guard-only key would serve a stale SURVIVED. AC-2's
fixture drives exactly that transition.

Residual, stated rather than hidden: the key is the issue's key, so a change to a file the suite
*sources* but which is neither the guard nor the suite (a shared library) does not invalidate.
Recorded in `docs/testing.md` under AC-10, alongside the one-line escape hatch
(`MUTATION_SWEEP_CACHE=0`).

**OR-1 (cache location and lifetime), disposition `reversible-default-and-flag`.** The issue's
stated default is "a per-machine cache under the state dir, with no eviction until it is shown to
matter"; AC-8 additionally requires it to live **outside the repo**. Both readings are satisfied by
a per-machine state location outside any checkout — `${XDG_CACHE_HOME:-$HOME/.cache}/second-shift/
mutation-sweep`, overridable by `MUTATION_SWEEP_CACHE_DIR`. AC-8's "bounded" is honored with a
generous entry cap (`MUTATION_SWEEP_CACHE_MAX`, default 20000, oldest-first eviction only past the
cap), which is the flag half of the disposition and leaves OR-1's "no eviction until it matters"
true in practice.

Fail-safe is a shape check on read: an entry that is not exactly one well-formed record line is a
**miss**, never a pass. Writes are `mv`-atomic so a concurrent worker cannot read a torn file.

### Early exit (AC-5)

The killer's output is captured to a per-worker log rather than discarded, and the existing poll
loop greps it for the repo-wide `FAIL:` failure convention (38 of 63 suites; `fail() { echo "
FAIL: $1" >&2; }`). On the first match the group is reaped through the existing `reap_group`, and
the mutant scores KILLED.

Eligibility is *derived*, not assumed: the precheck already runs each suite unmutated and green, so
a suite whose **green** output contains the pattern is a false-positive source and is recorded
ineligible for early exit for the rest of the run. That closes the one way early exit could
manufacture a kill.

### Concurrency safety (AC-7)

Two hazards are real in this tree and both are addressed rather than discovered as flake:

- **Fixed temp paths.** `check-doc-routing-selftest.sh` writes `/tmp/docroute-moved.out` and
  `/tmp/docroute-deleted.out` by literal name; two concurrent instances race. Its guard is pinned
  serial in a new `tools/mutation-serial-suites.tsv` with the reason recorded, because the fix
  itself is out of scope (AC-11).
- **Temp-dir leakage from a reaped suite.** An early-exit or bound reap SIGKILLs the suite, so its
  own `trap … EXIT` cleanup never runs. Killers therefore run with `TMPDIR` pointed at a
  per-item scratch directory the harness removes unconditionally — which is also what makes AC-9's
  "reclaimed on every exit path" true for the reap paths specifically.

**OR-2 (pool default, and whether CI's 10-way sharding should shrink), disposition
`reversible-default-and-flag`.** Default applied as stated: sharding is left untouched in this
change, because shrinking shards and adding intra-shard parallelism together would make a
regression in either impossible to attribute. Pool size defaults to `min(max(cores-2,1), 8)`,
overridable by `MUTATION_SWEEP_JOBS`.

## Out of scope

Making `lean-gate.sh` milestone 3's mutation leg skippable locally — split out deliberately: it
edits `lean-gate.sh` (collides with in-flight lean PRs) and "does the default become skip" is a
`pause-and-ask` question about what a build session may truthfully claim at handoff.

## Measurements

AC-6's figures are recorded here on completion and repeated in the PR body.

| Run | Wall time |
| --- | --- |
| cold, serial (`MUTATION_SWEEP_JOBS=1`, cache off) | not yet measured |
| cold, parallel (default pool, cache off) | not yet measured |
| partial hit (one guard's suite edited) | not yet measured |
| full hit (unchanged tree, zero suite executions) | not yet measured |

Baseline of record before this change: **~500s + setup ≈ 8–10 min** for the three lean guards.
Every cell is filled from a run on this branch before the handoff; a design-derived estimate is
not an entry.
