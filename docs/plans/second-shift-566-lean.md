# #566 — milestone 3 stops running the full sweep locally

**Issue:** https://github.com/manoldonev/second-shift/issues/566
**Pre-flight receipt:** `.claude/pipeline-state/566-ledger.md` (gitignored; its amendments are
restated in https://github.com/manoldonev/second-shift/issues/566#issuecomment-5360677504)
**Base:** `main` @ 80276e7

## Design

Design: none — this is shell tooling with no rendered surface. `design.provider` is unconfigured
in this repo's `.claude/second-shift.config.json`.

## Intent

PR CI becomes the arbiter of sweep truth. Milestone 3's local job shrinks to a bounded quick
check that fits inside the harness's ~120s reap, and the entire long-sweep supervision stratum —
detached runner, marker/rejoin, `INTERRUPTED_BUDGET_M3`, lane registry — is deleted along with
its selftest and register mass.

The ticket's four spec defects, found at intake and binding here:

1. **The gate cannot build an `--exclude` list.** `cmd_3` runs the consumer's configured `test`
   string opaquely through `bash -c`; #563's `lane_apply_selftest_cache` states the constraint
   outright. The quick check is therefore **repo-side**, and `lean-gate.sh`'s diff is **pure
   deletion**.
2. **Activation is default-on**, because the config that would carry an opt-in flag is
   gitignored and no gate could verify the edit.
3. **`m3infra-v2:` is a live scheduler contract** (`orchestrate-lean.sh:680-686`) that the
   ticket's AC-5 did not cover.
4. **Six mutation-catalog rows die**, and catalog anchor drift is a hard red — unlike a stale
   baseline row, which only warns.

## Acceptance Criteria

- **AC-1**: WHEN milestone 3 is evaluated THEN it runs as a single blocking call with no detached
  runner and no rejoin. `lean-gate.sh` spawns nothing for milestone 3; `cmd_3` is reached
  directly from `run_milestone`'s dispatch. The reap fit is a measured property stated in the PR,
  not a fixture assertion: **50s** end to end on this tree (see OR-1).

- **AC-2**: The supervision stratum is gone. A repo-wide grep for `m3-run`, `--m3-token`,
  `M3_RUN_TOKEN`, `m3_run_detached`, `m3_joinable`, `m3_launch_or_join`, `m3_wait`,
  `m3_marker_mine`, `m3_runner_live`, `m3_runner_pid`, `m3_read_runner`, `m3_paths`,
  `m3_replay_log`, `m3_reap_runners`, `m3_runner_records`, `m3_spawn_new_session`,
  `LEAN_GATE_M3_NEW_SESSION`, `INTERRUPTED_BUDGET_M3`, `lane-registry.sh`, `lane_register`,
  `lane_deregister`, `lane_apply_job_ceiling` and `LEAN_JOB_CEILING` matches only
  `CHANGELOG.md` and `docs/plans/**` — never live code, selftests, workflows or the register
  TSVs. `lane-registry.sh` and `lane-registry-selftest.sh` are deleted.

  **Amended in round 3, and it STRENGTHENS the check.** The 23 identifiers above are all names of
  *code*. Round 2's B-1 was a consumer that spelled the coupling as the ARTIFACT — a
  `lean-lanes.tsv` path default in `tools/gate-ablation.sh`, arriving from the base merge, which no
  token on that list could see. The grep therefore also covers `lean-lanes.tsv` and `live_lanes`,
  and no live match may be a COUPLING. Two live matches are permitted and both are named here:
  `tools/gate-ablation-selftest.sh` case `(q)`, which writes a `lean-lanes.tsv` into a fixture
  state dir on purpose, to assert that a stale registry left over on a real machine excludes
  nothing; and `lean-gate.sh`'s D-5 paragraph, which names the retired registry in the PAST tense
  to explain why `--ticket-source lane-registry` survives as a caller-asserted label.

- **AC-3**: WHEN the bounded quick check reds THEN exactly one milestone-3 fix attempt is
  charged, and the existing budget-exhaustion behavior (`rc=4` on the 4th red) is preserved.
  Proven by selftest.

- **AC-4**: WHEN the slow-suite table defers suites THEN `tools/run-selftests.sh` names each
  deferred suite on stdout — one line per suite, carrying its path and the table's reason — and
  the gate replays that output. A run with deferrals and no red satisfies milestone 3: a
  deferral does NOT red the milestone, charge budget, or trip the runner's discovered/ran
  invariant, because the exclusion is computed before dispatch. Proven by selftest.

- **AC-5** *(amended — the ticket's original wording is narrowed to its intent)*:
  `scripts/check-lean-chain.sh`, `plugins/dev-pipeline/tools/lean-evidence.sh` and the `pr-gates`
  job carry **no diff** — the merge boundary is untouched and un-swept code still cannot merge.
  `.github/workflows/*` carries **only** the `--full` opt-out additions required by AC-10, at the
  4 `run-selftests.sh` call sites (`ci.yml` ×2, `nightly-guards.yml` ×2), and no other change.

- **AC-6**: `plugins/dev-pipeline/skills/build-lean/scenario-liveness-selftest.sh` is extended to
  compose the new milestone-3 verdict path end-to-end, and its cases that drive the detached
  runner (the kill/rejoin scenario) are removed rather than left asserting deleted machinery.

- **AC-7** *(amended — #583's content-keying voided the ordinal obligation)*: in the same diff —
  (a) every `tools/mutation-baseline.tsv` row whose guard no longer resolves is dropped;
  (b) the **seven** `tools/mutation-catalog.tsv` rows anchored to deleted code are **deleted**, not
  re-anchored: `lane-registry-recycled-pid`, `lane-join-entry-dropped`, `lean-gate-m3-no-join`,
  `lean-gate-m3-stale-marker`, `lean-gate-m3-death-blind`, `lean-gate-m3-samelaunch-join`, and
  `lean-gate-m3-pid-outlives`. The seventh was **missed at intake and found by a scoped sweep**,
  not by reading: its id carries no identifier the deletion grep matched, and its anchor is the
  runner's `rm -f "$M3_PID"`. Catalog anchor drift is a hard red, and the PR lane defers this
  guard — so leaving it would have redded nightly, not this PR;
  (c) **VOID, corrected during the build.** This clause required removing the `LEAN_JOB_CEILING`
  writer↔reader row from `scripts/lockstep-manifest.tsv`. That file does not exist: #606
  (`80276e7`, this branch's own base) deleted all 744 lines of it and made
  `check-lockstep-pairs.sh` discover pairs from their in-source `LOCKSTEP-BEGIN` markers instead.
  The clause was written from a stale reading of the shared checkout at intake. Nothing replaces
  it: `LEAN_JOB_CEILING` never carried a marker pair, so deleting the name discharges the
  coupling outright. `lean-gate.sh`'s one real marker block — `seam-scrub subset` — is untouched
  by this diff, and `bash scripts/check-lockstep-pairs.sh` stays green;
  (d) the PR body states the **net bash line delta**, which must be strongly negative.

- **AC-8**: `lean-gate.sh` does NOT read, poll, or otherwise consume CI verdicts. No new
  `gh`/network call appears on any milestone-3 path.

- **AC-9** *(new — the uncovered scheduler seam)*: `lean-gate.sh`'s `infra_token` prints
  **`m3infra-v3:<n>`** with `n` derived from `unclosed_count 3` alone, and the
  `"N runner record(s), M live"` diagnostic is gone. `orchestrate-lean.sh`'s own `infra_token()`
  function body is **unchanged** — only its `m3infra-v2:0` prose reference is corrected. Proven
  by selftest that the token's prefix is `m3infra-v3:` and is never empty.

- **AC-10** *(new — the repo-side quick check)*: `tools/selftest-slow-suites.tsv` is a committed
  table, one row per deferred suite carrying path, measured cost and reason.
  `tools/run-selftests.sh` applies it as exclusions **by default**, and `--full` opts out. A
  table row naming no discovered suite is a hard error, the same stale-row posture `--exclude`
  already carries. `--full` and an explicit `--exclude` compose without conflict. Proven by
  selftest.

- **AC-11** *(new — the doc surfaces AC-10 and AC-2 invalidate)*: in the same diff —
  `CLAUDE.md`'s mandated verification recipe gains `--full` (it is the contributor's full-sweep
  recipe, and `CLAUDE.md` states it "runs COLD, and that is deliberate");
  `docs/testing.md`'s `--exclude` caller count and its milestone-3 local-sweep description are
  re-derived; and `plugins/dev-pipeline/skills/build-lean/SKILL.md`'s claim that `bash G 3`
  "detaches the evaluation itself and BLOCKS" is rewritten, staying under the file's 60-line cap.

- **AC-12**: Behavior-preserving elsewhere. WHEN
  `SKIP_STRESS=1 bash tools/run-selftests.sh --full --exclude tools/install-topology-selftest.sh`
  runs before and after, THEN every suite's verdict is unchanged except the suites this diff
  deliberately edits or deletes.

## Decision Ledger

Carried forward from the pre-flight receipt `.claude/pipeline-state/566-ledger.md` (gitignored).
These are the rows a human ratified; they are binding and are not re-decided here.

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Where the bounded quick check lives — the ticket says "the gate builds the `--exclude` list up front", which is not reachable | REPO-SIDE. The committed slow-suite table and the exclusion logic live entirely in `tools/run-selftests.sh`; `lean-gate.sh`'s diff is PURE DELETION with no new shipped mass. AC-1 and AC-4 are amended: the `--exclude` set and the deferred-suite listing become claims about `run-selftests.sh`, whose stdout the gate replays | user-answered |
| D-2 | Deleting the stratum kills `m3_runner_records`, half of `infra_token`'s basis, which the scheduler reads | Re-version to `m3infra-v3:`, basis = `unclosed_count 3` alone; drop the `"N runner record(s), M live"` diagnostic. `orchestrate-lean.sh`'s own `infra_token()` is UNCHANGED — it only string-compares (`:785`) and never parses — so the sole scheduler diff is the stale prose at `:677`. AC-5 is amended to admit it | user-answered |
| D-3 | How far the lane-registry deletion goes, given it reverses #526's shipped outcome | FULL. `lane-registry.sh`, `lane-registry-selftest.sh`, `lane_register`, `lane_deregister`, `lane_apply_job_ceiling`, `LEAN_JOB_CEILING` **and its reading end in `tools/run-selftests.sh`** all go. Grounding: #525 and #526 are both closed, the ceiling sized a multi-minute sweep's core share, and a check bounded to a 120s reap does not meaningfully contend | user-answered |
| D-4 | What happens if the measured quick check does NOT fit the ~120s harness reap | GROW THE TABLE until it fits — whatever does not fit gets a row and defers to CI. Safe by construction: CI still sweeps everything, so a larger table costs signal latency, never soundness. AC-1's reap fit becomes an outcome the table guarantees, not a hope | user-answered |
| D-5 | What selects the quick check, given the dogfood config is gitignored | DEFAULT-ON. `run-selftests.sh` applies the table unless `--full` is passed; `ci.yml` (2 sites) and `nightly-guards.yml` (2 sites) pass `--full`. The change is atomic and reviewable in one diff with no dependency on an untracked file. AC-5 is narrowed to its intent — `check-lean-chain.sh` and `pr-gates` carry no diff, so the merge boundary is untouched | user-answered |
| D-6 | Whether `needs-spec-work` was live, and what clears it | LIVE — the in-body `spec-review: verdict=implementable blockers=0` marker over-claimed. The four amendments (D-1, D-2, D-3/D-9, D-5) are the unpaid work. This receipt plus the ticket amendments discharge it; swap `needs-spec-work` for `ready-for-dev` | user-answered |

## Open Regions

Carried from the pre-flight receipt.

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | Exact membership of the slow-suite table — unmeasured at intake | reversible-default-and-flag |
| OR-2 | Whether the infra-death class still earns its keep once milestone 3 cannot outlive a turn | pause-and-ask |
| OR-3 | The deferred-suite line format on `run-selftests.sh` stdout | reversible-default-and-flag |

**OR-1 — RESOLVED BY MEASUREMENT during the build, and the answer was larger than expected.**
Every suite was timed alone on 2026-08-20: 67 suites, **603s serial**. The membership rule is a
threshold, not a hand-picked list — **every suite at or above 9s is deferred**, which is 12 suites
plus `install-topology`. That leaves 98s serial with a longest single suite of 8s.

Measured outcome, `bash G 3 566` end to end (lint lane included):

| Table | Milestone 3 wall clock |
| --- | --- |
| 3 rows (only the suites above 40s) | 214s — **over the reap** |
| 3 rows, re-run with a warm cache | 213s — the cache served 1 of 66 |
| the same sweep at `--jobs 10` | 166s sweep alone; parallelism is saturated at 10 cores |
| **13 rows (the 9s threshold)** | **50s — fits, with margin** |

Two findings the PR must carry, because neither was visible at intake:

1. **The bound is not cosmetic.** With nothing detached, a reaped milestone-3 call leaves an
   unclosed `started` row and loses its work. Five of those exhaust the interrupted budget and
   hard-stop at `rc=4` — so an unbounded sweep would make milestone 3 *unpassable* in an
   autonomous lane, not merely slow. That is why D-4's "grow the table until it fits" was applied
   to its conclusion rather than stopped at a comfortable-looking three rows.
2. **Twelve suites carry 84% of the sweep's cost, and they are disproportionately the lane's own
   guards** — `lean-gate` (141s), `mutation-sweep` (135s), `scenario-liveness` (68s),
   `check-lean-chain` (35s), `orchestrate-lean` (28s). Their regressions now surface at PR CI
   rather than before the push. The durable fix is widening
   `tools/selftest-cache-inputs.tsv` so repeat sweeps are free, which would shrink this table;
   that is separate work and is deliberately not attempted here.

**OR-2.** `pause-and-ask`, and **not taken inside this run**. AC-9 keeps the class alive at a
narrowed basis, which is the conservative call. If `unclosed_count 3` provably can no longer move,
`m3infra-v3` measures nothing and the honest change is retiring `--infra` and the scheduler's
continuation-recovery path — a materially larger deletion that contradicts AC-9 and undoes #527,
which was built for a real incident. If the build reaches that conclusion it hands back.

**OR-3.** Default: one line per suite, path plus the table's reason column, on stdout. No machine
consumer exists.

## Out of scope

- The merge boundary (`check-lean-chain.sh`, `lean-evidence.sh`, `pr-gates`) — AC-5.
- #563's cache mechanism (a dependency, not a target); its `LEAN_SELFTEST_CACHE_DIR` lockstep
  entry survives.
- The generic `INTERRUPTED_BUDGET` (=5) for the non-detached milestones.
- Review-round accounting rules (#496); no new CI-reading bash in the gate.
- #543, whose subject is `lean-gate.sh`'s comment narrowing — it stays with #553.
- #567's remaining PR-mode audit.
