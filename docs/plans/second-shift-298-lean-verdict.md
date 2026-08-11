# lean review verdict — #298

verdict=approve
run_id: review-298-2
session_id: bb45bbef-6945-44fd-937d-90d7e411b7d2
rounds: 2
pr: #487
reviewed_head: 2f7a578b7875b9305d9126506e7c9f3a3abd76d7
reviewed_patch_id: 991ac2af1b10f6a120c57ea185051420b8c25982
inherited_patch_id: e81ec080441601ebfe718a7ecd3faf3ea27e5752
inherited_from_verdict: 2f7a578b7875b9305d9126506e7c9f3a3abd76d7
fidelity: not-applicable
model: unknown
capabilities: pr-marker

Round 2, full branch diff (`bedf9c8..HEAD`) — nothing inheritable. Verdict: **approve**, no blockers.

**Why a round rather than a re-stamp.** Round 1 approved at `428a167`; the branch was then rebased onto `main` (which had gained #486). The rebase **resolved a conflict** in `tools/mutation-sweep.sh`: main appended an 8th report column `sites_beyond_budget` to the header printf and to `emit_row`, and this branch rewrites those same two lines from `$REPORT_TMP` to `$REPORT_SINK`. Measured rather than reasoned — the merge-base-anchored contribution diff carries real `+`/`-` deltas (not only blob/`@@`/context lines), so this is a genuine round, not a mechanical re-stamp. `pr-gates` reaches the same conclusion independently: `reviewed patch e81ec0804416` vs the branch's current `991ac2af1b10`, with the gate's own instruction "Run another review round."

Panel: security, performance, maintainability, complexity, test-coverage, scope-completeness. Six selected, six returned, none dark; all six approve with zero findings (security carried two suppressed items at confidence 40 and 35). a11y + design-fidelity not routed — no changed path matched `stageParams.webComponentGlobs` (default `apps/web/**/*.{tsx,jsx}`); this repo declares no `design.provider`.

## The conflict resolution — correct and complete

Verified directly, since it is the whole reason this round exists:

- **Zero `REPORT_TMP` references remain** in `tools/mutation-sweep.sh`. The rename is total, not partial — a half-converted resolution would have left a write going to a buffer nothing publishes.
- **Header arity 8**, carrying `sites_beyond_budget` last, written to `$REPORT_SINK`; `emit_row` takes and prints 8 fields to the same sink.
- **All four `emit_row` call sites pass 8 arguments** (`deferred-to-nightly`, `excluded`, and the two `swept` sites), so main's column and this branch's sink change compose rather than collide.
- **Merge mode is consistent**: `MERGE_HDR` is read from `$REPORT_SINK`'s own 8-column header and compared byte-wise against each shard's, so a shard running the older 7-column harness still reds.
- **The suite passes at the rebased head** — `tools/mutation-sweep-selftest.sh` re-run in this checkout: 108 `ok`, 0 `bad`, including all 7 new `(w2)`/`(w3)` assertions. This is the check the rebase actually put at risk: main's comment declares the 8th column load-bearing for `report_row()`'s positional `$5/$6/$7` parsing and for the byte-wise header compare, and round 1's green was measured pre-rebase.
- `shellcheck -e SC1091,SC2015,SC2181` clean on both changed shell files.

## Per-AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 — cost comment re-derivable | satisfied | `.github/workflows/mutation-sweep.yml` replaces `~4-9 min each` with worst/median shard ranges, the window `2026-08-06..2026-08-10`, and the `gh run list` + `gh api .../jobs` pair that re-derives them. Re-derived independently this round from the five nightlies: worst shard `15.2 / 12.7 / 16.0 / 13.8 / 16.1` → `12.7-16.1`, reproducing the stated range exactly. See finding 1 on the median. |
| AC-2 — `--report` is the streaming sink | satisfied | `REPORT_SINK="$REPORT_OUT"` when set, `mktemp` only as the no-`--report` fallback. The header printf sits in the reporting section (~line 685), well before PHASE 1 (line 1454) and the worker pool, so the artifact path is headed from the sweep's first moment; `finish()` no longer copies and `cat`s+removes only the fallback buffer. The comment's precision claim checks out: swept rows are emitted in PHASE 5 (lines 1739/1779), and the pre-pool rows are the excluded/deferred bookkeeping ones. |
| AC-3 — step-level time bound | satisfied | `timeout-minutes: 45` on the `sweep shard` step (job-level 60 unchanged as backstop); `publish shard artifact` keeps `if: always()` + `if-no-files-found: error`. The comment states the step-vs-job cancellation reason and the do-not-simplify instruction. |
| AC-4 — truncated shard distinguishable | satisfied | `finish()` writes non-dotted `<report-dir>/mutation-complete` carrying `mode=/shard=/rc=/wall_s=`, and only there — not on the `cleanup` EXIT/INT/TERM trap, so a killed shard cannot write it. Merge reds `merge truncated` naming each marker-less shard, and keys the seed arity check on `SHARD_COMPLETE`. `(w3)` covers both halves plus the control that a real mode mismatch still reds. |
| AC-5 — residual gap stated at the mechanism | satisfied | The workflow's `AND WHAT IT STILL DOES NOT COVER` block names the 83-84 min lost-communication class, says no step executes at all there, and states that partial-evidence coverage is not total coverage. |
| AC-6 — cases in the paired suite | satisfied | `(w2)` 4 assertions + `(w3)` 3 assertions, all green at the rebased head. Streaming is observed by a fixture **killer** reading the artifact path mid-sweep, so the case is deterministic rather than racing the sweep. `tools/mutation-sweep.sh` is a `mutation-exclusions.tsv` row, so no generic ordinals re-key and `mutation-baseline.tsv` is correctly untouched; `mutation-sweep-pr` is green on the head. |
| AC-7 — docs | satisfied | `docs/testing.md` records what a bound-blowing shard now leaves behind, that neither mechanism alone is the fix, and the class still uncovered. |

Design: `not-applicable` — the spec's `## Design` section is the disarmed `Design: none` form, and the disarm is justified: the repo's config declares no `design.provider` and the diff has no rendered surface.

## CI on the reviewed head (`2f7a578`)

`lint-and-selftests` pass · `selftests (macos, bash 3.2)` pass · `mutation-sweep-pr` pass · `release-pr-gates` skipped · `pr-gates` **fail**, on the stale-patch-id arm alone (`[lean-evidence] ✗ verdict record ... reviewed patch e81ec0804416, but this branch's diff ... now hashes to 991ac2af1b10`). That is precisely the condition this round's record resolves; no other arm reds.

## Findings (none blocking)

1. **`median shard 3.8-5.6 min` is the upper median, not the median.** Carried from round 1 and re-derived independently here from the exact command the comment supplies: the true per-nightly medians are `3.1 / 3.4 / 3.8 / 4.1 / 5.3` → `3.1-5.3`. The stated figures are the 6th of 10 sorted durations rather than the mean of the 5th and 6th. AC-1's mechanism — measured figures, the date window, and the re-derivation command — all ship, and the worst-shard range the 45-minute bound is actually sized against reproduces exactly, so the AC is satisfied by its letter. The error is conservative (it overstates cost), and the comment's own "RE-DERIVE rather than trust that" instruction is what surfaces it. Left a warning rather than escalated to a blocker: it was a round-1 warning and nothing about the rebase changed it.

2. **Merge mode writes a `mutation-complete` marker into its own output directory too.** `COMPLETE_MARKER` derives from `REPORT_OUT` regardless of `MODE`, so the operator-facing `mutation-sweep` artifact carries a marker beside the merged report. Confirmed inert: nothing reads a marker outside `$SHARDS_DIR/*/`, and the workflow's merge job writes to `sweep-out/` while reading shards from `shards/`, so the two never alias. Flagged only because it is undocumented — a merged output dir now looks exactly like a completed shard's.

Round 1's finding 3 (a stray untracked `mutation-complete` left in the build worktree by a local `--mode pr` run) is **resolved** — the worktree is clean at this head.

## Independent verification run

- `tools/mutation-sweep-selftest.sh` in this checkout at `2f7a578`, `env -u CLAUDE_CODE_SESSION_ID` — 108 `ok` / 0 `bad`, `(w2)` and `(w3)` all green.
- `shellcheck -e SC1091,SC2015,SC2181 tools/mutation-sweep.sh tools/mutation-sweep-selftest.sh` — clean.
- Per-shard durations re-derived from `gh api repos/manoldonev/second-shift/actions/runs/<id>/jobs` for runs `31076085278 / 31149305749 / 31239507134 / 31294927884 / 31356918992` (n=10 each).
- `set -uo pipefail` confirmed (no `-e`), so the `[[ -n "$REPORT_OUT" ]] && COMPLETE_MARKER=...` idiom cannot abort the run when `--report` is unset; tested the idiom under `set -euo pipefail` as well and it survives there too.
- `sed -n '2,52p'` help range re-checked against the grown header — still ends on a paragraph boundary.
- `SHARD_I -eq 1` confirmed as the guard on the excluded-guard rows, so the code comment's "shard 1's excluded-guard rows" is exact rather than approximate.
