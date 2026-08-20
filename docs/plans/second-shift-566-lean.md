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
  directly from the milestone dispatch.

- **AC-2**: The supervision stratum is gone. A repo-wide grep for `m3-run`, `--m3-token`,
  `M3_RUN_TOKEN`, `m3_run_detached`, `m3_joinable`, `m3_launch_or_join`, `m3_wait`,
  `m3_marker_mine`, `m3_runner_live`, `m3_runner_pid`, `m3_read_runner`, `m3_paths`,
  `m3_replay_log`, `m3_reap_runners`, `m3_runner_records`, `m3_spawn_new_session`,
  `LEAN_GATE_M3_NEW_SESSION`, `INTERRUPTED_BUDGET_M3`, `lane-registry.sh`, `lane_register`,
  `lane_deregister`, `lane_apply_job_ceiling` and `LEAN_JOB_CEILING` matches only
  `CHANGELOG.md` and `docs/plans/**` — never live code, selftests, workflows or the register
  TSVs. `lane-registry.sh` and `lane-registry-selftest.sh` are deleted.

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
  (b) the **six** `tools/mutation-catalog.tsv` rows anchored to deleted code are **deleted**, not
  re-anchored: `lane-registry-recycled-pid`, `lane-join-entry-dropped`, `lean-gate-m3-no-join`,
  `lean-gate-m3-stale-marker`, `lean-gate-m3-death-blind`, `lean-gate-m3-samelaunch-join`;
  (c) the `LEAN_JOB_CEILING` writer↔reader row in `scripts/lockstep-manifest.tsv` is removed,
  while the `LEAN_SELFTEST_CACHE_DIR` entry survives untouched;
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

## Open Regions

Carried from the pre-flight receipt.

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | Exact membership of the slow-suite table — unmeasured at intake | reversible-default-and-flag |
| OR-2 | Whether the infra-death class still earns its keep once milestone 3 cannot outlive a turn | pause-and-ask |
| OR-3 | The deferred-suite line format on `run-selftests.sh` stdout | reversible-default-and-flag |

**OR-1.** Default: measure, then table whatever does not fit the reap. Every excluded suite still
runs in CI, so a wrong call costs signal latency and nothing else. The PR states measured
per-suite costs and the resulting membership.

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
