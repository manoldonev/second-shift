# lean review verdict — #298

verdict=approve
run_id: review-298-1
session_id: c120001d-4626-44f9-81dc-e3e6c1a43630
rounds: 1
pr: #487
reviewed_head: 428a167c2ff61cc6dc71d95a3ce903b4ae7a6866
reviewed_patch_id: e81ec080441601ebfe718a7ecd3faf3ea27e5752
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown
capabilities: pr-marker

Round 1, full branch diff (`aed5e96..428a167`) — nothing to inherit. Verdict: **approve**, no blockers.

Panel: security, performance, maintainability, complexity, test-coverage, scope-completeness. Six selected, six returned, none dark; all six approve with zero findings. a11y + design-fidelity not routed — no changed path matched `stageParams.webComponentGlobs` (default `apps/web/**/*.{tsx,jsx}`); this repo declares no `design.provider`.

## Per-AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 — cost comment re-derivable | satisfied | `.github/workflows/mutation-sweep.yml` replaces `~4-9 min each` with worst 12.7-16.1 / median 3.8-5.6 min, the window `2026-08-06..2026-08-10`, and the `gh run list` + `gh api .../jobs` pair that re-derives them. Re-derived independently from the five nightly runs: worst-shard figures reproduce exactly (15.2 / 12.7 / 16.0 / 13.8 / 16.1). See finding 1 on the median. |
| AC-2 — `--report` is the streaming sink | satisfied | `REPORT_SINK="$REPORT_OUT"` when set, `mktemp` only as the no-`--report` fallback; header + every `emit_row` land on the artifact path; `finish()` no longer copies and `cat`s+removes only the fallback buffer. Merge-mode content unchanged — case `(w)` still green. Probed: restoring the pre-fix shape (sink always `mktemp`, `cp` in `finish()`) fails `(w2)` with `report-absent` and nothing else. |
| AC-3 — step-level time bound | satisfied | `timeout-minutes: 45` sits on the `sweep shard` step (job-level 60 unchanged as backstop); `publish shard artifact` keeps `if: always()` + `if-no-files-found: error`. The comment states the step-vs-job cancellation reason and the do-not-simplify instruction. |
| AC-4 — truncated shard distinguishable | satisfied | `finish()` writes non-dotted `<report-dir>/mutation-complete` carrying `mode=/shard=/rc=/wall_s=`, and only there — it is not on the `cleanup` EXIT/INT/TERM trap, so a killed shard cannot write it. Merge reds `merge truncated` naming each marker-less shard, and keys the seed arity check on `SHARD_COMPLETE`. Probed both halves: inverting the truncation guard fails `(w3)` case 1; re-keying the arity check to `SHARD_REPORTS` fails `(w3)` case 2 — each kills exactly its target. |
| AC-5 — residual gap stated at the mechanism | satisfied | The workflow's `AND WHAT IT STILL DOES NOT COVER` block names the 83-84 min lost-communication class, says no step executes at all there, and states that partial-evidence coverage is not total coverage. |
| AC-6 — cases in the paired suite | satisfied | `(w2)` 4 assertions + `(w3)` 3 assertions. Four probes run by hand, each killing exactly the case it targets (one also trips an adjacent case, noted below). `tools/mutation-sweep.sh` is a `mutation-exclusions.tsv` row, so no generic ordinals re-key and `mutation-baseline.tsv` is correctly untouched; `mutation-sweep-pr` on the PR is green in 10s, consistent with zero in-universe guards. |
| AC-7 — docs | satisfied | `docs/testing.md` records what a bound-blowing shard now leaves behind, that neither mechanism alone is the fix, and the class still uncovered. |

Design: `not-applicable` — the spec's `## Design` section is the disarmed `Design: none` form, and the disarm is justified: the repo's config declares no `design.provider` and the diff has no rendered surface.

## Independent verification run

- `shellcheck -e SC1091,SC2015,SC2181` on both changed shell files — clean.
- `tools/mutation-sweep-selftest.sh` under **stock bash 3.2** (PATH-shimmed `/bin/bash`, `SKIP_STRESS=1`, `env -u CLAUDE_CODE_SESSION_ID`) — all cases pass. The new array idiom `SHARD_COMPLETE[${#SHARD_COMPLETE[@]}]=` and `${#arr[@]}` on an empty array were checked separately under 3.2 and are safe under `set -u`.
- Probe matrix (each run is the whole suite in an isolated detached worktree, with the applied diff printed before scoring):

  | Probe | Cases failed |
  | --- | --- |
  | sink reverted to `mktemp` + `cp` in `finish()` | `(w2)` mid-run report — `report-absent`. 1 case. |
  | arity check re-keyed to `${#SHARD_REPORTS[@]}` | `(w3)` truncation misread as mode mismatch. 1 case. |
  | truncation guard inverted so `merge truncated` never fires | `(w3)` named truncation red; also `(w)` merge output, an expected side effect of firing the red on a complete merge. 2 cases. |
  | `COMPLETE_MARKER` set even without `--report` | `(w2)` stray-marker, and the pre-existing `(af)` left-files-in-checkout case. 2 cases. |

- `bash tools/mutation-sweep.sh --help` — the `sed -n '2,52p'` range was re-pinned with the header growth and still ends on a paragraph boundary.
- CI on `428a167`: `lint-and-selftests` pass, `selftests (macos, bash 3.2)` pass, `mutation-sweep-pr` pass. `pr-gates` fails on `[lean-evidence] ✗ no committed verdict record` alone — the by-design pre-handoff state this record resolves.

## Findings (none blocking)

1. **`median shard 3.8-5.6 min` is the upper median, not the median.** Recomputing per-shard durations from the exact command the comment supplies gives medians of 3.1 / 3.4 / 3.8 / 4.1 / 5.3 min across the five nightlies — i.e. `3.1-5.3`. The stated figures are the 6th of 10 sorted durations rather than the mean of the 5th and 6th. The worst-shard figures, which the 45-minute bound is actually sized against, reproduce exactly, and the direction of the error is conservative. AC-1's letter is met; but the criterion's whole point is that a reader can re-derive the number, and a reader who does gets a different one. Worth either saying "upper median" or restating the true median.
2. **Merge mode writes a `mutation-complete` marker into its own output directory too.** `COMPLETE_MARKER` is derived from `REPORT_OUT` regardless of `MODE`, so the operator-facing `mutation-sweep` artifact now carries a marker alongside the merged report. Nothing reads a marker outside `$SHARDS_DIR/*/`, so this is inert today, and it is arguably the right signal for a merge that completed. Flagged only because it is undocumented: a merged output directory now looks exactly like a completed shard directory, which matters the day someone re-feeds one as `--shards-dir`.
3. **Housekeeping, not a code defect:** an untracked `mutation-complete` (`mode=pr shard=1/1 rc=0 wall_s=1`) is sitting in the build worktree from a local `--mode pr` run pointed at a repo-root `--report`. The sweep as CI and `lean-gate.sh` milestone 3 invoke it leaves nothing behind — `lean-gate.sh` passes no `--report`, and probe 4 shows `(w2)`'s stray-marker case plus the pre-existing `(af)` case both catch a marker escaping into a checkout. Just delete the file.
