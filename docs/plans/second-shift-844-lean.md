# #844 — The retired `LEAN_` spellings and the `lean-overrides` path are removed at the next major

Removes the `LANE_`/`LEAN_` environment compatibility layer #833 shipped, the retired
`.claude/lean-overrides.tsv` register path, and the `SECOND_SHIFT_LEAN_EVIDENCE` seam — then, in a
second commit, retires the lowercase `lean_` identifier spelling the #833 rename left behind.

The removal is what takes the major bump. The rename is cosmetic and consumer-invisible, and rides
along because a major is the cheapest moment to churn names.

## Measured surface

Re-measured in this worktree at `1b0bb02a` (the head after #852). Counts are `git grep -F` line
counts, excluding `docs/plans/` and `CHANGELOG.md` — the two paths AC-4 exempts.

| Population | Measured |
| --- | --- |
| `LEAN_` lines in scope | **90**, across 24 files |
| `lean_` lines in scope | **336**, across 5 files (**48** distinct identifiers, 387 occurrences) |
| `lean-overrides` lines in scope | **3**, across 2 files |
| `lean-*` LOCKSTEP block ids | **11** — 10 renamed, `lean-pr-marker` frozen by AC-8 |

**One rename target collides.** Projecting all 48 identifiers through `lean_` → `lane_` and
intersecting with the 25 `lane_` identifiers already in the tree yields exactly one hit:
`lane_count`, a local at `milestone-gate.sh:5016`. Every other target is free. This is the
collision AC-12 names and the only one that exists.

**The `\b` trap is real here, and was re-confirmed.** `git grep -oE '\b[A-Za-z0-9_]*lane_…'` over
this tree returned **zero** matches while the same expression without `\b` returned 25 — `git grep
-E` does not honor `\b`. AC-4's two greps are therefore fixed-string (`-F`), never word-boundary.

### Removal sites

| Site | What it is |
| --- | --- |
| `plugins/dev-pipeline/skills/build/lane-env.sh` | the shared reader — `lane_env`, `lane_env_promote`, `LANE_ENV_WARNED`, `LOCKSTEP-BEGIN lane-env-fallback` |
| `boundary-evidence.sh:153-182`, `tools/run-selftests.sh:93-122` | the two INLINE LOCKSTEP twins (each has nothing to source from) plus their own `lane_env_promote` call |
| 8 `. lane-env.sh` load sites | `milestone-gate.sh:304`, `reconcile.sh:96`, `orchestrate.sh:233`, `operator-override.sh:69`, `pipeline-cost-block.sh:114`, `check-lane-chain.sh:197`, `lane-bench-arm.sh:43`, `lane-bench.sh:85` — each with the `exit 2` load-failure branch #852 added |
| `lane-bench.sh:91-92` | the two explicit non-prefix mappings (`LEAN_BENCH_SS_ROOT`, `LEAN_BENCH_LANE_BIN`) |
| `operator-override.sh:306-325` | `OVERRIDE_REGISTER_REL_RETIRED` and `override_register_path`'s fallback arm — outside the `override-record-reader` LOCKSTEP block, which ends at `:304` |
| `second-shift-ci-check.sh:39,162-168` | the `SECOND_SHIFT_LEAN_EVIDENCE` seam |
| 6 suite-scope retired-half scrubs | `milestone-gate-selftest.sh`, `scenario-liveness-selftest.sh`, `orchestrate-selftest.sh`, `operator-override-selftest.sh`, `lane-bench-arm-selftest.sh`, `run-selftests-selftest.sh` |
| 3 NON-suite retired-half scrubs | `LEAN_ATTEND_MODE` in `SEAM_SCRUB` at `milestone-gate.sh:3829` **and** `preflight.sh:60` — a `LOCKSTEP-BEGIN seam-scrub subset` pair, so both move or `check-lockstep-pairs.sh` reds — and `-u LEAN_SELFTEST_CACHE_DIR` at `run-selftests.sh:188` |
| `lane-env-selftest.sh` | the layer's own suite, 29 `LEAN_` lines, cases (a)–(o) |
| `tools/mutation-catalog.tsv:157-158` | `lane-env-precedence`, `lane-env-warn-every-read` |
| `tools/mutation-pair-map.tsv:36-43` | 8 rows pairing each load site with `lane-env-selftest.sh` as killer |
| `tools/mutation-baseline.tsv:53,145` | two rows whose **note prose** carries a `LEAN_` token — reworded, not excluded |
| `tools/selftest-cache-inputs.tsv:82,144,163` + the `:165-171` comment block | `lane-env.sh` declared on three closures |
| `docs/config-schema.md:22-33` | the `LANE_*`/`LEAN_*` note and its `lean-overrides` sentence |
| `reconcile-selftest.sh:164` | a comment describing the load line this ticket deletes |

**The removal is subtractive, not a rewrite.** `lane_env_promote` exists only to resolve the retired
half; with that half gone it is a no-op, and every `${LANE_X:-<default>}` read site keeps its own
default and needs no edit. Same for `lane-bench.sh`'s two explicit pairs — the variables are
assigned in place. The load-failure branches go with the `source` lines that need them.

## Acceptance criteria

- **AC-1** — `lane-env.sh` and both inline LOCKSTEP twins are deleted, along with all 8
  `. lane-env.sh` load sites and their `exit 2` branches, all 10 `lane_env_promote` call sites, and
  `lane-bench.sh`'s two explicit `lane_env` mappings. No read site changes: each
  `${LANE_X:-<default>}` already carries its own default.
- **AC-2** — `operator-override.sh` reads `.claude/lane-overrides.tsv` only. The
  `override-record-reader` LOCKSTEP block is byte-identical or moves in lockstep.
- **AC-3** — `second-shift-ci-check.sh` reads `SECOND_SHIFT_BOUNDARY_EVIDENCE` only, and its
  selftest's asserted strings move with it.
- **AC-4** — No tracked file carries a `LEAN_` token, a lowercase `lean_` identifier, or a
  `lean-overrides` path outside `docs/plans/` and `CHANGELOG.md`. Verified with two **fixed-string**
  greps: `git grep -F 'LEAN_'` and `git grep -F 'lean_'`. The `\b` idiom returns zero here having
  matched nothing. Nothing ends in `lean` before `_`, so the second grep has no false positives, and
  it catches the underscore-prefixed locals (`lr_lean_out`, `mk_lean_repo`, `_lean_gate_test_stall`)
  a word-boundary census misses. The exclusion list stays exactly those two paths:
  `mutation-baseline.tsv:53,145` are **reworded** to name the #833 rename without spelling the
  retired token, not excluded — the baseline is a live register the sweep reads on every merge, so
  excluding it would blind the guard in a file that changes.
- **AC-5** — `lane-env-selftest.sh` is **deleted, not preserved**. Cases (l), (m), (n) and (o) all
  derive over the fallback: (l) asserts every knob is promoted, (m) that no reader distinguishes a
  set-but-empty knob from an unset one, (n) that a file scrubbing `LANE_X` also scrubs `LEAN_X`, (o)
  that a guard refuses when the lib is absent. All are moot once there is no lib and an ambient
  retired export is inert, and a guard kept past its subject is guard mass that greens vacuously.
  The 6 suite-scope retired-half scrubs and the 3 non-suite ones go with it — a `LEAN_X` export can
  no longer reach a read site.
- **AC-6** — Every register drops the rows whose subject is gone: `tools/mutation-catalog.tsv` rows
  `lane-env-precedence` and `lane-env-warn-every-read`; `tools/mutation-pair-map.tsv` rows 36-43,
  all 8 naming `lane-env-selftest.sh` as killer; `tools/selftest-cache-inputs.tsv`'s three
  `lane-env.sh` input rows and their comment block. Any `tools/mutation-baseline.tsv` row left stale
  by the deletions is retired. Re-anchoring only — no register keeps a row whose subject is gone.
- **AC-7** — Prose drops the compatibility layer rather than describing it in the past tense:
  `docs/config-schema.md:22-33` (the `LANE_*`/`LEAN_*` note and its `lean-overrides` sentence,
  keeping the current-naming statement), the `WHY THIS EXISTS` headers at each deleted site, and
  `reconcile-selftest.sh:164`.
- **AC-8** — **Untouched**, per #833 AC-9: every on-the-wire marker value and the LOCKSTEP ids that
  equal one (`LANE_PR_MARKER_TAG='lean-pr-marker'`), the artifact families (`-lean.md`,
  `-lean-verdict.md`, `{issue}-lean-progress`), the `lean chain reconciliation` step name, the
  `01-lean-spec-*` eval fixtures, historical records under `docs/plans/`, and `CHANGELOG.md`.
- **AC-9** — One PR, two commits. The removal commit is `feat!` with a `BREAKING CHANGE:` footer and
  a `Changelog:` trailer carrying real migration steps: export `LANE_*`, rename
  `.claude/lean-overrides.tsv`, export `SECOND_SHIFT_BOUNDARY_EVIDENCE`, and re-copy
  `second-shift-ci-check.sh`. The rename commit is separate so review and the verdict record can
  read the removal on its own, and carries `Changelog: none`.
- **AC-10** — The full sweep is green: `SKIP_STRESS=1 bash tools/run-selftests.sh --full --exclude
  tools/install-topology-selftest.sh`, run cold. **And** `bash tools/install-topology-selftest.sh`
  directly — this deletes a file eight shipped scripts source at run time, and its push trigger is
  too narrow to catch that class.
- **AC-11** — `bash tools/mutation-sweep.sh --emit-site-keys` lists no site for any deleted
  `lane-env.sh` line, and the sweep reports no stale `mutation-pair-map.tsv` or
  `mutation-baseline.tsv` row for the 8 former load sites.
- **AC-12** — All 48 lowercase `lean_` identifiers are renamed to the `lane_` spelling, mirroring
  #833's `LEAN_`→`LANE_` mapping. One exception: `lean_count`
  (`scenario-liveness-selftest.sh:197`) takes a name other than `lane_count`, which is already a
  local at `milestone-gate.sh:5016`. String literals are not touched.
- **AC-13** — The 10 LOCKSTEP block ids spelled `lean-*` are renamed to `lane-*`. `lean-pr-marker`
  is **not** — its id equals `LANE_PR_MARKER_TAG`'s on-the-wire value, which AC-8 freezes.
  `check-lockstep-pairs.sh` stays green, which is what proves each pair's two sites moved together.

## Open Regions

| ID | Region | Disposition | State |
| --- | --- | --- | --- |
| OR-1 | The delta #843 leaves in `lane-env-selftest.sh`, `mutation-pair-map.tsv` and `mutation-baseline.tsv` | pause-and-ask | **RESOLVED** before this run — #843 merged as PR #852 (`1b0bb02a`); the delta is measured in D-15, D-16 and D-17 and carried into AC-6 and AC-4 |
| OR-2 | Whether any consumer still exports a `LEAN_*` spelling or carries `.claude/lane-overrides.tsv`'s retired path | reversible-default-and-flag | Takes the default — remove — flagged in the `BREAKING CHANGE:` footer and AC-9's migration steps |

**The removal is silent by choice.** After it lands, a stale `LEAN_*` export is simply ignored, and
a surviving `.claude/lean-overrides.tsv` is not found, so a run proceeds unoverridden without saying
so. That is the same false-green shape #833 rejected for the rename itself, accepted here because
the alternative — a detection pass, or a refusal — has to carry the retired names somewhere,
re-creating a smaller compatibility layer with no removal date of its own. The asymmetry worth
naming is the register: a file on disk is cheaper to detect than an absent environment variable
(`[ -f .claude/lean-overrides.tsv ]` is one line), and the silent-removal choice costs more there
than it does for an export. D-2 took it anyway.

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Sequencing against #843, which was in flight on this same subject | #843 lands first — **done**, merged as PR #852 (`1b0bb02a`) on 2026-09-18. #844 absorbs its measured delta: the 8 new `tools/mutation-pair-map.tsv` rows (36–43), that suite's new case (o), and the re-keyed `tools/mutation-baseline.tsv` rows. Detail in D-15. | user-answered |
| D-2 | What an operator still on a retired spelling gets after removal | Silent removal as specced. A stale `LEAN_*` export, and a surviving `.claude/lean-overrides.tsv`, are simply inert — no detection, no refusal, no residual retired-name list anywhere. | user-answered |
| D-3 | Release window and eligibility | Eligible once #843 merges. This PR's own `feat!` + `BREAKING CHANGE:` footer declares v14.0.0 — there is no separate major to wait for, and no hold for a batch or for consumer-migration evidence. | user-answered |
| D-4 | The 48 lowercase `lean_*` shell identifiers (387 occurrences across 5 files; 303 in `scenario-liveness-selftest.sh`, 26 in `milestone-gate.sh`, 7 elsewhere, 1 in `docs/testing.md`) | In scope — renamed in this PR. **Identifiers only, never string literals**: the suites assert on wire values (`lean-progress`, `lean-claimed`, `\| milestone-4 \| absent \|`) that AC-8 protects, so a blanket `s/lean_/lane_/g` over the file is wrong. | user-answered |
| D-5 | The 11 LOCKSTEP block ids spelled `lean-*` | 10 renamed. `lean-pr-marker` is kept, per AC-8 — its id equals `LANE_PR_MARKER_TAG`'s on-the-wire value. `check-lockstep-pairs.sh` is discovery-based with no registry and reds when a pair's two sites disagree, so a half-done rename cannot pass. | user-answered |
| D-6 | PR shape, now that the ticket carries a removal plus a rename | One PR, with the rename isolated in its own commit so review and the verdict record can read the removal on its own. | user-answered |
| D-7 | Guarding the lowercase spelling against reintroduction | AC-4 gains a second fixed-string grep for `lean_` — **underscore only**. A bare `lean` or `lean-` grep would hit the 344 `lean-progress` / 87 `lean-verdict` / 67 `lean-claimed` wire values AC-8 protects and red on its first run. | user-answered |
| D-8 | How the AC delta reaches BUILD | Amend #844's body after #843 merges, re-measured at that head: AC-6 gains `mutation-pair-map.tsv` and the baseline rows; the surface table gains `preflight.sh` and the three non-suite scrub sites (D-10); new ACs cover the rename (D-4, D-5) and its guard (D-7). #844 is unclaimed, so no lane races the edit. | user-answered |
| D-9 | Rename target spelling | Mechanical `lean_` → `lane_`, mirroring #833's `LEAN_`→`LANE_` mapping and the repo's settled prefix (`lane-env.sh`, `lane-bench.sh`, `check-lane-chain.sh`). One exception: `lean_count` (`scenario-liveness-selftest.sh:197`) — `lane_count` is already a local at `milestone-gate.sh:5016`. Separate processes, so no shadowing, but the target must differ. | codebase-derived |
| D-10 | Three retired-half scrub sites the issue's surface table omits, none of them suites | All removed, forced by AC-4's zero-token grep. `LEAN_ATTEND_MODE` leaves `SEAM_SCRUB` in **both** `milestone-gate.sh:3829` and `preflight.sh:60` — a `LOCKSTEP-BEGIN seam-scrub subset` pair, so both or `check-lockstep-pairs.sh` reds. `-u LEAN_SELFTEST_CACHE_DIR` leaves `run-selftests.sh:188`. `preflight.sh` appears nowhere in the issue's table. | codebase-derived |
| D-11 | `lane-env-selftest.sh` case (m), which AC-5 does not name | Deleted with the suite. (m) pins the promote-in-place assumption — that no reader tests `${LANE_X+…}`. Once `lane_env_promote` no longer defines absent knobs as the empty string, the assumption it protects is moot, the same ground AC-5 gives for (l) and (n). | codebase-derived |
| D-12 | `docs/config-schema.md:22-33` | The `LANE_*` naming statement survives, trimmed of every compatibility clause and the `lean-overrides` sentence. Nothing describes the layer in the past tense, per AC-7. | codebase-derived |
| D-13 | Changelog trailers across the two commits | The removal commit carries AC-9's `Changelog:` with its four migration steps; the rename commit carries `Changelog: none`. CLAUDE.md extracts trailers grep-anywhere, so one in any commit survives the squash. | codebase-derived |
| D-14 | Mutation-catalog re-anchoring beyond AC-6's two rows | None. Re-confirmed at `1b0bb02a`: no catalog `sed` pattern references `lane_env`, `SEAM_SCRUB`, or any lowercase `lean_` identifier, so the rows targeting files this PR edits do not re-anchor. #843 did not touch `mutation-catalog.tsv`. | codebase-derived |
| D-15 | The #843 delta #844 must now unwind (resolves OR-1) | Three items, measured at `1b0bb02a`. (a) `tools/mutation-pair-map.tsv` rows **36–43** each pair a guard with `lane-env-selftest.sh` as killer — all 8 deleted, since both the suite and the load-failure branches they score disappear. (b) `lane-env-selftest.sh` case **(o)** (+50 lines) goes with the suite per AC-5. (c) The 8 guards' `lane-env.sh` load-failure branches, which #843 normalized to `exit 2`, are deleted outright with the `source` lines — AC-1 already covers them, but the issue's table calls these sites "10 `lane_env_promote` call sites" and never names the branch. | codebase-derived |
| D-16 | Two `LEAN_` tokens #843 left in `tools/mutation-baseline.tsv` note prose (rows 53 and 145), which make AC-4 fail at the current head | Rewrite both notes to name the #833 rename without spelling the retired token. AC-4's exclusion list stays exactly `docs/plans/` and `CHANGELOG.md`: the baseline is a live register the sweep reads on every merge, not frozen historical record, so excluding it would blind the guard in a file that actually changes. | user-answered |
| D-17 | `reconcile-selftest.sh:164`, a comment #843 added referencing "the lane-env load line" | The comment goes stale when the line is deleted; it is rewritten or dropped with the branch it describes. New site, absent from the issue's table. | codebase-derived |
