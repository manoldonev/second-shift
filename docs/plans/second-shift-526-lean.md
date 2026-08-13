# second-shift #526 — a lean lane sizes its sweep to its share of the machine

Issue: [#526](https://github.com/manoldonev/second-shift/issues/526) (part of #525).

## Problem

`tools/run-selftests.sh` defaults to `SELFTEST_JOBS:-4` and the dogfood config asks for
`--jobs 10`. Nothing counts lanes, so N concurrent lean lanes each request the whole machine.
Measured on 10 cores with five lanes: load 16.9 / 21.2 / 26.8, peak demand ~34 workers, one lane
at **1h46m wall for 4m07s of its own CPU** against `CLAUDE.md`'s documented 5:22 uncontended sweep.

The fix is a *ceiling*, not a semaphore. The suites are independent and safe to interleave; they
are starving each other, not racing. A wait-your-turn lock would convert a slow lane into a hung
one.

## Design

Two halves, in two places, plus a registry that makes the lane count knowable.

**`plugins/dev-pipeline/skills/build-lean/lane-registry.sh`** (new, ships with the gate) —
a lane-liveness registry over a TSV whose rows are `pid<TAB>start<TAB>issue<TAB>registered`.
Subcommands: `register`, `deregister`, `ceiling`, `lane-pid`, `list`. Every reader reaps rows
whose `pid` is gone or whose recorded start time no longer matches that pid's, so a killed lane
does not accumulate. `ceiling` prints `<ceiling><TAB><lanes><TAB><cores><TAB><basis>`.

**The lane pid.** The gate's own pid, and its `$PPID`, are both short-lived — an agent harness
spawns a fresh shell per tool call (measured: two consecutive calls in one session reported pids
73779 and 67698 under a stable `claude` parent). The registry therefore resolves the lane's owning
process as **the nearest ancestor that is not a shell** (`bash`/`sh`/`zsh`/`dash`/`ksh`, basename,
leading `-` stripped), capped at 8 hops, falling back to `$PPID`. `LEAN_LANE_PID` overrides.
Under-counting degrades toward today's behavior (a higher ceiling); it never returns zero.

**The gate** derives `max(1, cores / live_lanes)` and exports it to every milestone-3 lane child as
`LEAN_JOB_CEILING` — a variable *distinct* from `SELFTEST_JOBS`, which cannot carry this:
`run-selftests.sh` reads `SELFTEST_JOBS` before argument parsing and `--jobs` overwrites it
unconditionally, so an injected value is discarded exactly when the dogfood config passes
`--jobs 10`.

**The runner** applies `min(resolved_jobs, ceiling)` after the parse loop. Absent, it is a no-op.

Registry path: `${LEAN_LANE_REGISTRY:-<pipelineStateDir>/lean-lanes.tsv}` in the main checkout,
which every worktree on the machine already shares. Scope is therefore this repo's lanes, not the
machine's — stated as a limit, not papered over.

## Acceptance criteria

- **AC-1** A lane registers liveness at `entry` and deregisters at `teardown`, keyed on **pid plus
  that pid's start time** so a recycled pid cannot impersonate a dead lane. A stale row is reaped
  by the next reader rather than accumulating.

- **AC-2** The gate resolves a job ceiling from `max(1, cores / live_lanes)` and exports it as
  `LEAN_JOB_CEILING`. `run-selftests.sh` applies `min(resolved_jobs, ceiling)` between its parse
  loop and its `--root` validation. With no ceiling set the application is a no-op and behavior is
  byte-identical to today, **including with an explicit `--jobs 10`**.

  A ceiling that is not a positive integer is rejected the way `--jobs` is, at the same validation
  site and through the same `die`. Left unvalidated, `min()` is undefined and the naive shell form
  yields `0` or an empty `JOBS` — a silent drop to serial, which is the fail-open shape AC-4
  forbids.

  Both halves of the core-count precedent at `tools/mutation-sweep.sh` are reused verbatim: the
  `getconf _NPROCESSORS_ONLN` read *and* its `case "${CORES:-}" in ''|*[!0-9]*) CORES=2 ;;`
  fallback. No hand-rolled `nproc`/`sysctl` dual form.

- **AC-3** The ceiling and the lane count it came from are announced on the gate's milestone-3
  output, so a slow sweep is attributable without reading `ps`. The announcement states that the
  value is **advertised, not enforced** — the gate cannot know whether a consumer's command reads
  it.

- **AC-4** A registry that is unreadable, empty, or holds only stale rows degrades to the
  single-lane answer **and names which of the three**. It never returns a confident zero.

- **AC-5** CI is unaffected. `ci.yml` and `nightly-guards.yml` never invoke the gate and never pass
  `--jobs`, so no ceiling is set and `JOBS` stays at today's default of `4`. Asserted by a runner
  case, not assumed. `--cache-dir` / `--cache-write` semantics are untouched.

- **AC-6** The ceiling reaches **every** milestone-3 execution site: the render pre-command,
  `lanes[]`, the fixed `lint`/`typecheck`/`test` keys, and `extraLanes`. All four share one
  `env ${SEAM_SCRUB_ENV[@]…}` idiom; the injection is made there, at the array's construction —
  outside the `LOCKSTEP-BEGIN/END seam-scrub` markers that `scripts/lockstep-manifest.tsv` pins.

- **AC-7** Consumer generality. `run-selftests.sh` is repo-local; the gate ships to consumers whose
  `test` command is `vitest` / `pytest` / `cargo test`. `LEAN_JOB_CEILING` is a documented
  convention a consumer *may* honor, never a requirement, and a command that ignores it behaves
  exactly as today.

- **AC-8** Docs. `docs/testing.md` documents the ceiling convention (what sets it, what reads it,
  what a consumer does with it) beside the existing runner contract, and the runner's own `USAGE`
  header names it. No other doc is made stale by this change.

## Tests

- `lane-registry-selftest.sh` (new, beside the helper): 0 / 1 / 3 / N live lanes → derived ceiling;
  a stale row (dead pid; recycled pid whose start time differs); unreadable registry → announced
  degradation; the lane-pid walk (shell chain → non-shell ancestor, all-shells → fallback, missing
  `ps` → fallback, cycle guard).
- `run-selftests-selftest.sh`: ceiling absent (identical to today, including with `--jobs 10`),
  ceiling below the flag, ceiling above the flag, ceiling non-numeric → `die` rc=2.
- `lean-gate-selftest.sh`: milestone 3 announces the ceiling and exports it to a lane child.
- **No concurrency in any suite.** The registry is the seam; every case stages rows deterministically.

**bash 3.2 is acceptance evidence, not a footnote.** A lane registry is exactly the shape that
invites `declare -A`, which fails *open* on stock macOS bash 3.2 — a green local sweep and a green
ubuntu lane are no evidence. The suite is run under the PATH-shimmed 3.2 lane before the handoff.

Per `CLAUDE.md`'s Test-the-tests contract this edit re-keys generic survivor ordinals on the guards
it touches and re-anchors any affected `tools/mutation-catalog.tsv` row in the same diff.

## Note for the PR

`run-selftests.sh` puts its own bytes on the pass-cache key, so any edit here invalidates every
cached marker once, forcing one cold CI sweep per lane. Expected, not a regression.
