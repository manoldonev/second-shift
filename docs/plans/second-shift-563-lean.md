# second-shift #563 — lean spec

**Issue:** run-lean close-out re-sweeps an unchanged head — the milestone-3 recipe ignores the CI-proven cache.

**Build model:** sonnet (recipe/flag wiring plus fixtures).

**Design:** none — this is a build-harness / test-runner wiring change (`lean-gate.sh`
milestone-3 lane environment + `tools/run-selftests.sh` env intake). No route, UI, or
rendered surface. `design.provider` is unset in this repo's config.

## Problem

The `run-lean` close-out session re-runs a full milestone-3 selftest sweep on a head that has
not moved since the build session already swept it green — measured at ~9:47 (~12% of an
82-minute run) in #549's 2026-08-16 record, and up to ~14:47 across the reap-restart
triplication of that same run.

`tools/run-selftests.sh` already carries a CI-proven, content-addressed pass cache
(`--cache-dir` + `tools/selftest-cache-inputs.tsv`, #448): a suite with a declared-inputs row
is skipped when the git blob id of every declared input — including the suite's own bytes and
the runner's — is unchanged from a recorded pass, under a key that also pins OS, bash major
and `SKIP_STRESS`. The lean milestone-3 lane never activates it, so an unchanged head pays
for every rowed suite again.

This wires the existing mechanism into the lean milestone-3 lane. It adds **no new cache
mechanism** — key derivation, the declared-inputs table, its validation, and the
served/recorded accounting are all #448's and unchanged. It adds only the *seam* by which the
lean gate hands the runner a store to read from and record into.

**What that is worth today, stated honestly.** `tools/selftest-cache-inputs.tsv` currently
rows exactly one suite — `cost-block-selftest.sh`, 30s — so an unchanged-head close-out sweep
saves ~30s of its ~9:47, not the ~9:47 the issue's framing invites. The seam is what makes
every *future* row pay in the lean lane as well as in CI; widening the table (the standing
candidate is `lean-gate-selftest.sh`, 147s and the sweep's largest single suite) is a
separate, riskier edit — the table's own header calls adding a row the risky change, and
`docs/testing.md` requires deriving the transitive closure from the suite — and is
deliberately **out of scope here**. This ticket delivers the wiring; the table stays as CI
left it. See Notes.

## Approach

The dogfood milestone-3 `test` lane command lives in the **gitignored**
`.claude/second-shift.config.json` — not a committed, reviewable surface — so the flag cannot
be added there. The gate already owns the precedent for handing an env value to an arbitrary
lane command it cannot rewrite: `LEAN_JOB_CEILING` (#526), appended to `SEAM_SCRUB_ENV` and
read by `run-selftests.sh`. This ticket adds a sibling coupling.

1. **`tools/run-selftests.sh` — env intake for the cache store.** After the argv parse (beside
   the existing `LEAN_JOB_CEILING` block): when `--cache-dir` was **not** given on argv and
   `LEAN_SELFTEST_CACHE_DIR` is a non-empty env value, use it as `CACHE_DIR`, set
   `CACHE_WRITE=1`, and announce the activation path. Argv always wins, so CI's explicit
   `--cache-dir [--cache-write]` path is byte-for-byte unchanged; unset env is a no-op, so
   every non-gate invocation (the CLAUDE.md local recipe, both CI lanes, the nightly wholesale
   leg) is unchanged.

   `--cache-write` is on for the env path for two reasons. The lane must *populate* the store
   on the first sweep for a later unchanged-head sweep to serve from it — a read-only lean
   cache can never hit. And the trust argument CI's split exists for does not apply here:
   CI withholds recording because a PR lane runs untrusted content into a store other runs
   read, whereas this store is machine-local and records the operator's own tree — the same
   posture `tools/mutation-sweep.sh`'s local cache already takes, and the same side of
   `docs/testing.md`'s "which side holds the authority" line.

2. **`tools/run-selftests.sh` — an unusable env store disables the cache instead of dying.**
   `--cache-dir` that is not creatable is a usage error and still `die`s (rc=2): an operator
   who typed a flag that cannot work is told so. An *injected* store that is not creatable is
   not the tree's fault and must not red an unrelated milestone, so the env path prints a
   named notice and runs cold. This asymmetry is the only behavioral difference between the
   two activation paths.

3. **`tools/run-selftests.sh` — scrub it from the worker dispatch.** The `--run-one` worker
   already strips the parent's test-only seams (`RUN_SELFTESTS_DROP_LAST/RC`) so a nested
   runner cannot inherit an instruction meant for the parent. `LEAN_SELFTEST_CACHE_DIR` joins
   that `env -u` list: the cache is decided in the parent (workers never touch the store), and
   an inherited store would silently activate caching inside a suite that nests its own runner
   (`run-selftests-selftest.sh`), breaking that suite's "no `--cache-dir` ⇒ nothing served"
   fixtures under the dogfood sweep.

4. **`plugins/dev-pipeline/skills/build-lean/lean-gate.sh` — export the store.** In `cmd_3`,
   immediately after `lane_apply_job_ceiling`, append `LEAN_SELFTEST_CACHE_DIR=<store>` to
   `SEAM_SCRUB_ENV` so every milestone-3 lane command inherits it (advertised, not enforced —
   a `test` command that does not read it runs exactly as before). The store defaults to
   `${XDG_CACHE_HOME:-$HOME/.cache}/second-shift/lean-selftest`, honoring an operator-set
   `LEAN_SELFTEST_CACHE_DIR` — the idiom `tools/mutation-sweep.sh` uses for
   `MUTATION_SWEEP_CACHE_DIR` (outside every checkout, so a worktree teardown never loses it;
   per-machine, matching the key's OS/bash-major scoping).

5. **An off switch, because a cache you cannot turn off is a survivor you cannot re-check.**
   `LEAN_SELFTEST_CACHE=0` runs the lane cold, announced — the same escape hatch and the same
   name shape as `MUTATION_SWEEP_CACHE=0`, which exists in this repo for exactly the "is this
   green real?" moment. It is the one new knob; `LEAN_SELFTEST_CACHE_DIR` is not new to an
   operator, it is the runner-side name the gate defaults.

   **It scrubs rather than merely declining to export**, and that distinction is load-bearing:
   an operator who already carries `LEAN_SELFTEST_CACHE_DIR` hands it to every lane child by
   ordinary inheritance, so a gate that only skipped its own export would announce a cold sweep
   and run a cached one. The disarm therefore appends an EMPTY assignment, which the reader
   treats as absent. `-u` is not available at that point — `SEAM_SCRUB_ENV` already carries an
   assignment, and `env` stops reading options at the first `NAME=VALUE`.

**No head-diff branch in the gate.** The AC-1 (unchanged head ⇒ serve) / AC-2 (moved head ⇒
cold) distinction is realized entirely by the runner's content-addressed key, which is exactly
CI's proven contract: a suite serves iff every declared input's blob id is unchanged,
regardless of whether HEAD moved. Exporting the store on every milestone-3 sweep is therefore
a superset that necessarily covers the close-out path, while a first sweep still runs cold
(empty store) and any input change still re-runs — without the gate inventing a new
head-based trust shortcut it would then have to be trusted about.

## Acceptance criteria

- **AC-1**: the milestone-3 close-out path — a re-evaluation of an already-satisfied milestone
  on an unmoved head — runs with the cache active, so every rowed suite whose declared inputs
  are unchanged is served from the store instead of re-run. Delivered by the
  `LEAN_SELFTEST_CACHE_DIR` export (gate) + env intake (runner).

- **AC-2**: a first evaluation runs cold and the cache participates only where #448's contract
  already sanctions it — a suite with a declared-inputs row whose inputs are byte-identical to
  a recorded pass under the same key axes. No suite without a row is ever skipped; no
  head-based skip is introduced; argv `--cache-dir` (CI) semantics are unchanged; unset env is
  a no-op; and `tools/selftest-cache-inputs.tsv` is not widened by this change.

- **AC-3**: the coupling is guarded behaviorally on both sides.
  - Runner (`tools/run-selftests-selftest.sh`): via the `LEAN_SELFTEST_CACHE_DIR` env path,
    **not** the argv flag — an unchanged re-run is served from cache, editing a declared input
    re-runs the suite, an argv `--cache-dir` still wins over the env value, and a suite
    dispatched by the runner does not see `LEAN_SELFTEST_CACHE_DIR` in its environment
    (the worker scrub). An uncreatable env store runs cold with a notice rather than `die`ing,
    while an uncreatable argv `--cache-dir` still exits 2.
  - Gate (`plugins/dev-pipeline/skills/build-lean/lean-gate-selftest.sh`): a real milestone-3
    lane child echoes `${LEAN_SELFTEST_CACHE_DIR:-unset}` and its value must equal the store
    the gate announced — the `jc1` idiom #526 established for `LEAN_JOB_CEILING`, and the
    reason `scripts/lockstep-manifest.tsv` records that writer↔reader coupling as a **DROPPED**
    row rather than a presence check. A second case pins the override on the ANNOUNCEMENT, since
    an operator-set variable reaches a child by inheritance and so cannot discriminate the
    export. A third runs the off switch in an environment that ALREADY carries a store and
    demands the child see none — the only environment in which a disarm can fail.

- **AC-4** (doc): `docs/testing.md` — the cache contract of record — documents the lean
  milestone-3 lane as a third cache participant alongside the two CI lanes, naming the
  `LEAN_SELFTEST_CACHE_DIR` env seam, its recording policy and the trust argument for it, and
  the `LEAN_SELFTEST_CACHE=0` escape hatch; its property-1 sentence ("the cache as a whole is
  off unless `--cache-dir` is passed") is corrected to account for the env path, as is the
  CLAUDE.md sentence asserting the runner "never participates without that flag". Wiring that
  left these standing would make the two documents of record misdescribe when the runner
  caches.

## Notes

Net bash delta: a small positive (~20 lines of wiring across two scripts, plus fixtures) —
honest for "wires an existing mechanism", and paid back on the first close-out sweep. No
mechanism is added; #448's cache is unchanged.

**Follow-up, not silently absorbed:** the realized saving is bounded by the one rowed suite
until the table is widened. `lean-gate-selftest.sh` (147s) is the candidate worth the
declaration burden; deriving its transitive closure — the gate resolves `gh-bot.sh`,
`lane-registry.sh` and `ledger-lint.sh` at run time — is its own reviewable edit with its own
under-declaration risk, and belongs in its own ticket rather than riding along here.

Provenance: #549 transport-probe record (PR #560) + 2026-08-16 backlog recalibration.
