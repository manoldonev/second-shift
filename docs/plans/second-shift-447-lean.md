# second-shift #447 — CI runs the serial selftest sweep the repo's own recipe forbids

## Problem

Both CI selftest jobs run the `*-selftest.sh` set through an inline `while read` loop, serially,
while `CLAUDE.md`'s Verification section mandates `xargs -0 -P 4` and records it as the difference
between a 13:12 and a 5:22 sweep. Measured on run 31307491709: `selftests (macos, bash 3.2)` at
17:50, `lint-and-selftests` at 12:51 (709s of which is the one selftest step).

Six suites are ~83% of the cost. No suite is deleted — the lever is scheduling.
`install-topology-selftest.sh` compounds it: it re-runs every shipped suite from a staged install
cache, and being discovered by the same glob it runs concurrently with the outer sweep it
duplicates.

## Approach

A new runner, `tools/run-selftests.sh`, replaces both inline loops. Concurrency comes from
`SELFTEST_JOBS` (default 4). Per-suite output is captured to a file and replayed inside
`::group::`/`::endgroup::` framing in worklist order, which is why this is a script rather than a
`-P` flag bolted onto the loop: at `-P 4` the raw streams interleave and the log stops being
readable. `--exclude <path>` lifts `install-topology-selftest.sh` into its own job while leaving it
*discovered*; an exclusion matching no discovered suite is a hard error, the same stale-row posture
`install-topology-known-red.tsv` and `mutation-baseline.tsv` already carry.

The parallel-dispatch idiom is lifted from `tools/install-topology-selftest.sh`: `xargs -P` over
zero-padded indices into a worklist file, each worker writing `<idx>.rc` and `<idx>.log`, the parent
scoring from those. It is bash 3.2 compatible (no `wait -n`, no associative arrays on the hot path),
which the macos lane requires. A worker that dies without writing an `.rc` scores as a named infra
failure, never as a green suite.

Discovery stays `*-selftest.sh` only. The three `*-selftest.mjs` files are executed by
`workflows-mjs-selftest.sh`, which is itself in the glob — so the executed set is unchanged.

Job topology in `.github/workflows/ci.yml`: both selftest jobs call the runner with
`--exclude tools/install-topology-selftest.sh`; macos keeps `SKIP_STRESS: '1'` and ubuntu keeps not
setting it, preserving today's deliberate asymmetry. `install-topology-selftest.sh` gets its own job
on both lanes. The PR-scoped mutation sweep moves to its own job. A per-ref `concurrency` group with
`cancel-in-progress` is declared.

`INSTALL_TOPOLOGY_TIMEOUT`'s 1200s default is deliberately not touched — it is sized for contention
this change removes, but re-tightening it needs the uncontended measurement this change is what
produces (D-6, deferred).

## Acceptance criteria

- **AC-1** `tools/run-selftests.sh` exists and both selftest jobs in `.github/workflows/ci.yml`
  invoke it; neither job retains an inline suite loop.
- **AC-2** The runner exits non-zero when any suite fails, and names every failing suite.
- **AC-3** The runner fails when its discovered-suite count and run count disagree, and when an
  `--exclude` path matches no discovered suite.
- **AC-4** `SELFTEST_JOBS=1` and `SELFTEST_JOBS=4` produce the same verdict over the same suite set.
- **AC-5** Each suite's output is emitted as one contiguous group, not interleaved with others'.
- **AC-6** `install-topology-selftest.sh` runs in its own job on both the ubuntu and macos lanes,
  and is excluded from the sweep on both.
- **AC-7** The PR mutation sweep runs as its own job; `ci.yml` declares a per-ref `concurrency`
  group with `cancel-in-progress`.
- **AC-8** `tools/run-selftests-selftest.sh` covers AC-2 through AC-5 with executable assertions —
  no prose-presence guards.
- **AC-9** The set of suites executed across the whole CI run is unchanged from run 31307491709 —
  every `*-selftest.sh` still runs on both lanes, `install-topology-selftest.sh` included.
- **AC-10** `CLAUDE.md` and `docs/testing.md` state the runner as the verification recipe.

## Decision Ledger

| ID  | Decision | Resolution | Provenance |
| --- | -------- | ---------- | ---------- |
| D-1 | Delete slow or low-value suites | No — no suite is removed. 6 suites are ~83% of the cost; the other 61 are ~3 min across both lanes | user-delegated |
| D-2 | How parallelism is introduced | A shared runner script, not an inline `-P` per job — parallel output needs per-suite framing, and the every-script-is-covered rule binds any checked-in script to a selftest anyway | codebase-derived |
| D-3 | Concurrency level | `SELFTEST_JOBS` default 4, the recipe `CLAUDE.md` already measured at 13:12 serial → 5:22 parallel | codebase-derived |
| D-4 | Where the install-topology guard runs | Own job on both lanes, not dropped from macos — several known-red rows are explicitly environment-dependent, so the bash-3.2 copy carries signal ubuntu does not | user-delegated |
| D-5 | Conventional dependency/build caching | Not applicable and not attempted — no deps, no build; the only fetches total 7.5s against a 709s step | codebase-derived |
| D-6 | Re-tightening `INSTALL_TOPOLOGY_TIMEOUT` | deferred — owner: follow-up to this issue, once it produces the first uncontended measurement to size the bound against | deferred |
| D-7 | How the count-reconciliation arm is proven able to red | A narrow documented seam (`RUN_SELFTESTS_DROP_LAST`) drops one worklist entry after the counts are taken, so `run-selftests-selftest.sh` can assert the reconciliation fires. Same rejection-assertion posture `ci.yml`'s issue-forms step already carries against a checked-in bad fixture | codebase-derived |
| D-8 | Whether discovery widens to `*-selftest.mjs` | No — the three `.mjs` suites are executed by `workflows-mjs-selftest.sh`, which is in the `.sh` glob. Widening would double-run them and break AC-9 | codebase-derived |

## Design

Design: none — no user-facing surface; this is CI job topology and a shell runner.
