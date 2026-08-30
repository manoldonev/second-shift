# lean review verdict — #663

verdict=approve
run_id: review-663-1
session_id: 31b492be-e05c-4c66-8fb6-b0f5ae6f8bc2
rounds: 1
pr: #715
reviewed_head: a0d7980d68c2dd4f657b2e1bfa45058e754f9b29
reviewed_patch_id: 182244dec435ea798fc664f637e68b414be3ed05
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown
capabilities: pr-marker

# Review round 1 — PR #715 (#663)

**Verdict: approve.** 0 blockers, 3 warnings. All six ACs satisfied. Range read: `808aa29..HEAD`
(root round, full branch diff — no prior record to inherit). Panel of six, none dark.

## Per-AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 — an `unrunnable pair` red's CI log names the paired suite's failing case(s), matches **in addition to** the tail under one framed block, and a no-match failure says so | **satisfied** | Verified live, not inferred: run [`33315253887`](https://github.com/manoldonev/second-shift/actions/runs/33315253887) job `99267356422` (shard 6, head `3aa08a6`) emits `---- …lean-gate-selftest.sh: the failing case(s), then the tail ----`, then `(2 line(s) matching FAIL: — the failing case(s))`, then both `FAIL:` lines with the matching path, then the tail, then `---- end … ----`. The no-match arm is code-read at `tools/mutation-sweep.sh:1305` and exercised by `(g4c)`. |
| AC-2 — the exit-2 root cause identified with its failing cases cited by name in the spec, and fixed | **satisfied** | `(i-580a)`/`(i-580b)` are named in `docs/plans/second-shift-663-lean.md` and match the CI log above verbatim. The mechanism re-derived independently: the log's config path is `/tmp/mutation-sweep-work.lws3HK/tmp.0/leangate.8410.…/config.json`, and `FIXTURE_ROOT=$(dirname "$WORK")` resolves to exactly `/tmp/mutation-sweep-work.lws3HK/tmp.0` on that lane, so the offending token is dropped. Fixed: run [`33318103376`](https://github.com/manoldonev/second-shift/actions/runs/33318103376) shard 6 runs the pair. |
| AC-3 — a full-mode sweep covering `lean-gate.sh` completes green, dispatch cited in the spec and the PR body | **satisfied** | Re-derived from the API, not from the PR body: [`33319110925`](https://github.com/manoldonev/second-shift/actions/runs/33319110925) is `workflow_dispatch` on `claude/second-shift-663` at `015e359`, conclusion `success`, all ten `sweep (n)` jobs + `merge` green. Shard 6 log: `swept …/lean-gate.sh — applied=36 killed=34 survived=2`. Cited in both places. `git diff 015e359..HEAD` = 34 lines in `docs/plans/` alone — the citation does not precede its run. |
| AC-4 — a `Changelog:` trailer per repo convention | **satisfied** | All four commits carry one (`3aa08a6` prose, `385ccfb` `none.`, `015e359` prose, `a0d7980` `none`). CI `changelog trailer guard` green. No `Changelog: none` followed by indented prose in the same block, so nothing renders as a stray bullet at squash. |
| AC-5 — the AC-1 behaviour guarded by a selftest case that **fails on the pre-fix code**; the fixture buries its `FAIL:` line under more than `PRE_LOG_LINES` of chatter; the no-match arm guarded separately; the tail arm asserted alongside the match arm | **satisfied** | Re-derived by probe rather than accepted: a detached worktree at the reviewed head with `tools/mutation-sweep.sh` reverted to `808aa29` and the new suite kept gives **rc=2 — exactly `(g4)` and `(g4c)`, and no other case**. The fixture prints 60 `PASS: filler` lines after the `FAIL:` line against a 40-line tail, so a tail-only diagnostic structurally cannot show it. No-match arm is `(g4c)`; the tail arm is `grep -q 'PASS: filler 59'` inside `(g4)`'s conjunction. |
| AC-6 — the survivor the restored coverage uncovered is **killed, not baselined** | **satisfied** | `tools/mutation-baseline.tsv` is untouched (diff is four files). Before/after on the same lane: `catalog::lean-gate-settings-clobber-dangling` SURVIVED at `33316017803` and shard 6 of `33319110925` logs `early exit (first 'FAIL:' line, scored as KILLED): catalog::lean-gate-settings-clobber-dangling`. |

`## Design` — the spec declares no Design section and the repo configures no `design.provider`;
`fidelity: not-applicable`.

## Verification this round ran itself

- **Probe A (AC-5, the pre-fix oracle).** Detached worktree at `a0d7980`, `git checkout 808aa29 -- tools/mutation-sweep.sh`, full `tools/mutation-sweep-selftest.sh`: **rc=2, `(g4)` + `(g4c)` only**. The claim that the new cases fail on the pre-fix code is re-derived, and the fact that *nothing else* moves is what makes them a clean pin rather than a fixture that happens to red.
- **Probe B (AC-2, the regression guard).** Second detached worktree, `scrub_fixture_paths` replaced by the identity: **rc=1, `(i-580d)` alone**, failing on `[lean-gate] config: …/mutation-sweep-work.probe/tmp.0/config.json`. Reproduces the spec's probe C independently.
- **The two edited suites really ran in this PR's CI.** Neither carries a `tools/selftest-cache-inputs.tsv` row, so neither could be cache-skipped: `lint-and-selftests` shows `pass 132s …lean-gate-selftest.sh` / `pass 104s tools/mutation-sweep-selftest.sh`, and `selftests (macos, bash 3.2)` shows `pass 444s` / `pass 200s`. Both CI selftest jobs pass `--full` (`ci.yml:121`, `:414`), which is what reaches these two slow-listed suites at all.
- **The scrub does not reach a resurrected D-18 line.** Read at `0d8d09b^`: the deleted stdout lines were `milestone-3: mutation sweep (diff-scoped) » origin/$BASE_BRANCH` and `milestone-3: tools/mutation-sweep.sh absent — …` — no absolute path in either, so no token of either is dropped. The spec's claim holds at source.
- Oracle ACs proved by CI runs whose command and head match this review are cited, not re-run.

## Strengths

- **The sequencing is the finding.** AC-1 was shipped and dispatched before the root cause was
  known, and shard 6 named both cases *and the path that matched them* on the first run. The
  diagnosis is CI evidence rather than reasoning about a condition macOS cannot produce — and it
  turned a five-night undiagnosable red into a five-minute answer.
- **`(g4)` is a separation test, not a presence guard.** Its fixture is built so that the thing it
  asserts is structurally unreachable by the old implementation; probe A confirms the old
  implementation fails it and passes everything else.
- **`(ws7)` now asserts the gate's DECISION, not the harm.** `[ ! -e <target> ]` asked whether the
  write happened, which GNU `cp` prevents on its own — so the arm was inert on precisely the lane
  that scores it. `settings: … is already present` is what the `-L` conjunct actually controls and
  is `cp`-independent. This is the generalisable lesson in the PR.
- **`awk index()` rather than a regex.** Escaping a path into a pattern is the second half of the
  same bug class; keying the scrub on a substring test avoids it by construction.

## Warnings (not blocking)

- **W1 — the cap/overflow branch of `save_pre_log` is unguarded.**
  `tools/mutation-sweep.sh:1301–1303` slices with `head -n "$PRE_FAIL_LINES"` and emits
  `(N further match(es) not shown)`. All three new fixtures drive `n = 1` or `n = 0`, so neither the
  slice nor the `n - PRE_FAIL_LINES` arithmetic nor the `n > PRE_FAIL_LINES` boundary is exercised
  by anything. AC-1's own text does not mention the cap, which is why this is a warning and not an
  unsatisfied AC — but the spec's derivation does ("capped, and the overflow counted out loud"),
  and a suite emitting >20 `FAIL:` lines would be the case where the diagnostic matters most. A
  fixture looping the trigger past `PRE_FAIL_LINES` would pin it.
- **W2 — the scrub is keyed one directory wider than the fixture.** `FIXTURE_ROOT="$(dirname
  "$WORK")"` (`lean-gate-selftest.sh:180`) names the *containing* temp directory. This suite has a
  single `mktemp` (`:91`/`:93`) and every fixture path — `TREE`, `CFG`, `M580_TREE`, `M663_DIR` —
  hangs off `$WORK`, so `$WORK` alone would have covered both the CI failure (the offending token
  contains the full `$WORK`) and `(i-580d)`. As written, on a lane where the scratch lands directly
  in the system temp dir — ubuntu with no `TMPDIR`, where `FIXTURE_ROOT` is `/tmp` — the net drops
  *every* absolute token under the system temp directory, which is broader than the comment's "keyed
  on the fixture root" claims. The residual blind spot is narrow and I could not make it bite: a
  resurrected D-18 line naming the sweep by an absolute path inside the fixture tree would be
  invisible to `(i-580a)`/`(i-580b)`, but the historical lines name it relatively (checked at
  source, above), `(i-580b)`'s marker file and `(i-580c)`'s progress-record arm are oracles no scrub
  can reach, and `(i-580d)` carries a positive arm against an emptied output. Worth narrowing to
  `$WORK` next time this file is opened; not worth a round.
- **W3 — extrinsic, policy: `pr-gates` is red on `check-guard-budget.sh`** (+142 guard lines, base
  54189 → HEAD 54331, no `Guard-mass:` trailer). Recorded, not a blocker, per the merge-boundary
  rule — the boundary already blocks on it, and the fix is a trailer. Two consequences to carry
  forward: (a) that job's shell is `-e`, so **`pipeline chain reconciliation` and `lean chain
  reconciliation` never ran** — their state is unknown, not green; (b) if the trailer is added as an
  empty commit no line of the reviewed patch moves and this record stands, but amending `015e359`
  or `a0d7980` would rewrite reviewed lines and void it.

## Nit

- The spec lists `AC-6` before `AC-5`. Both are present and both are scored; the ordering is
  cosmetic.

## Panel

Six reviewers dispatched, six returned, none dark: security, performance, maintainability,
complexity, test-coverage, scope-completeness. Five returned zero findings. Test-coverage returned
one minor at confidence 85 — W1 above, which I confirmed by reading all three new fixtures rather
than relaying it. Suppressed (below threshold, recorded not acted on): a security note that the
snapshot now echoes more of the killer log into CI output (conf. 40 — the tail already emitted that
log, and these are selftest fixtures); two complexity notes that `MUTATION_SWEEP_PRE_FAIL_LINES`
follows the existing `PRE_LOG_LINES` tunable convention and that `scrub_fixture_paths` clears the
premature-abstraction bar at three call sites (conf. 60/65). `a11y-reviewer` and the design-fidelity
dimension were **not routed** — no changed path matches `stageParams.webComponentGlobs`
(unset; default `apps/web/**/*.{tsx,jsx}`). That is a note, not a coverage gap.

**Ready to merge?** With the `Guard-mass:` trailer. Nothing in the diff blocks.
