# lean review verdict — #760

verdict=approve
run_id: review-760-1
session_id: 4349f17a-bc12-4d67-b590-5d5e1ec3a113
rounds: 1
pr: #764
reviewed_head: 8b2793953f8a854c15d175d9ec1d535d67c4dc77
reviewed_patch_id: d261d145d2f5e0e076b769a1d458b8cdeaf49798
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
panel: review-toolkit:scope-completeness-reviewer
model: opus
capabilities: pr-marker

## Review summary

Round 1, full range `c7abbda5..8b279395` (the branch has no prior verdict record to inherit
from). Two files, +177 lines: the committed lean spec and one case block in
`lean-evidence-selftest.sh`. `lean-evidence.sh` is not edited, so no
`tools/mutation-catalog.tsv` anchor re-derivation is owed.

**The kill was reproduced independently, not accepted from the PR body.** `mutation-sweep-pr`
computed `0 verdict(s)` on this PR — no production guard is in the diff, and the guard's paired
suite is slow-deferred anyway (26s in `tools/selftest-suite-timings.tsv`, against
`mutation-sweep.sh`'s `SLOW_THRESHOLD_S=5`) — so the round owns all mutation evidence. Probed in
an isolated `git clone --local` of the branch head, graded on the three facts this repo requires:

```
clone head 8b279395 · 12 scw hits present in the clone (not a pre-commit clone)
[0] CONTROL                            rc=0   all green
[1] MUTANT 459 `-eq 1` -> `-ne 1`      rc=6   numstat 1/1, bash -n ok
    FAIL: (scw1) (scw2) (scw3) (scw4) (scw5) (scw6)   — 6 of 6, no pre-existing case moved
    mutant STILL applied at end        yes    (numstat 1/1)
[2] RESTORED                           rc=0   all green
```

One mutant kills through both arms of the flip, which is what the two-sided defect requires:
`PRINT_SCHEMA=1` falls through and envfails `(scw1)`, and `PRINT_SCHEMA=0` prints the schema and
exits 0, which is what reds `(scw2)`–`(scw6)`.

The assertions are oracles rather than copies. `(scw1)` lifts `AC_SCORECARD_HEADING`,
`AC_SCORECARD_COLUMNS` and `AC_SCORECARD_SCORES` out of `lean-evidence.sh` at run time and refuses
an empty lift, which is the established `(dd)` shape in this same suite
(`eval "$(grep '^LEAN_OUTPUT_DISPOSITIONS=' "$TOOL")"`) — verified against the block, not taken
from the PR body's claim of precedent. `(scw3)` is the case worth having: it pins rc=0 on a
contradictory body against `(sc3)`'s rc=1 through `all`, so a caller that priced the violation off
rc instead of stdout would now red.

One warning, no blockers. `approve`.

## Findings

| # | Severity | Dimension | Location | Finding |
| --- | --- | --- | --- | --- |
| 1 | Warning | Test coverage | `plugins/dev-pipeline/skills/build-lean/lean-evidence.sh:465` | `--verdict needs-work` is never driven through the `scorecard` subcommand, so one value of the enum the block covers stays dark. MEASURED, not inferred: mutating `approve\|needs-work) : ;;` to `approve) : ;;` in the same isolated clone leaves the suite **rc=0, all green** — a survivor whose production effect is that `lean-gate.sh verdict:5482` envfails on *every* needs-work record write. Not a blocker: AC-1 enumerates six arms and all six are reached and proven killing, this is an unenumerated seventh; and the generic operator set (`tools/mutation-operators.tsv` — `fail-open`, `cmp-eq`, `cmp-z`, `logic`, `detector`, `default`) has no case-alternative class, so no sweep will ever file it. Cheap follow-up: one `(scw3b)` asserting a needs-work body with an `unsatisfied` row is silent at rc=0 — which also pins the behavioral half, that the approve-contradiction arms do not fire on needs-work, the write-time twin of `(sc12)`. |
| 2 | Suggestion | Maintainability | PR body, "The kill, demonstrated" | The deferral is cited as "above `run-selftests.sh`'s 9s threshold". The threshold that actually defers this guard is `mutation-sweep.sh`'s `SLOW_THRESHOLD_S=5`, read off `tools/selftest-suite-timings.tsv` (`tools/mutation-slow-suites.tsv` is that file's generated report, not its input). 26s clears both, so the conclusion — CI is not the oracle for this kill — is correct and the probe obligation is discharged. Prose only; the committed spec says "deferred off the PR lane" with no threshold and is not affected. |

### Merge-boundary refusals (recorded, not blocking)

`pr-gates` is red at this head on exactly one item: `✗ no committed verdict record (a file named
*-760-lean-verdict.md)`. That is the expected pre-approve state of the lean chain, not a finding —
this record is what clears it.

### Suppressed (below threshold)

- `(scw4)`'s `grep -q '\-\-spec <path> is required'` uses a stray-backslash escape to keep grep from
  parsing the pattern as an option; the repo's existing idiom for that is `grep -q -- "…"`
  (`plugins/dev-pipeline/tools/preflight-selftest.sh`, 5 sites) and this is the only `\-\-` in the
  tree. Checked for the failure mode rather than assumed: no `stray \` warning appears in the ubuntu
  `lint-and-selftests` log at this head, and both lanes are green, so it is style with no measured
  effect.

## AC scorecard

| AC-n | score | evidence |
| --- | --- | --- |
| AC-1 | satisfied | `(scw1)`–`(scw6)` invoke `bash lean-evidence.sh scorecard` directly; the six arms AC-1 enumerates are each reached. Non-vacuous by construction: under the line-459 mutant all six red and no other case moves, which is only possible if all six execute the dispatch. Premise re-verified in the source — `write_verdict()` writes the record file itself and `ev()` runs `all`, so `(sc1)`–`(sc16)` genuinely never enter at 455. Finding 1 records the one enum value left undriven. |
| AC-2 | satisfied | `lean-evidence-selftest.sh:1204-1207` lifts the three constants with `sed` + `eval` from `$TOOL` at run time; `:1209-1213` requires rc=0 **and** all three non-empty **and** three `grep -qF` hits, so an empty lift fails rather than passing vacuously. Confirmed the schema at `lean-evidence.sh:460-462` prints from those same constants (277/278/284), which is what makes it an oracle. |
| AC-3 | satisfied | `(scw3)` asserts rc=0 plus the `scored unsatisfied on a verdict=approve record` line; `(sc3)` at `:1274` asserts rc=1 for the same contradiction through `all`. Both read in the source, and the two layers' rc values confirmed distinct. |
| AC-4 | satisfied | `(scw4)/(scw5)/(scw6)` each assert `rc -eq 2` and grep the specific message — `--spec <path> is required`, `does not exist`, and `must be 'approve' or 'needs-work' (got 'merged')`, matching the three `envfail` calls at `lean-evidence.sh:466-471`. `(scw6)` quotes the offending value back, so a refusal that stopped naming it reds. |
| AC-5 | satisfied | Reproduced by this round in an isolated `git clone --local` of 8b279395, not accepted from the PR body: control green → mutant rc=6 with exactly `(scw1)`–`(scw6)` → mutant still applied at end (numstat 1/1) → restore green. The clone was verified to contain the new cases before grading (12 `scw` hits), which is the specific vacuity mode this repo has recorded for this exact ticket. Transcript is quoted in the PR body as required. |
| AC-6 | satisfied | `git diff --stat c7abbda5..HEAD` is exactly `docs/plans/second-shift-760-lean.md` and `lean-evidence-selftest.sh`. `lean-evidence.sh` unedited (so no catalog re-anchor is owed), and all five named registers confirmed unchanged: `mutation-baseline.tsv`, `mutation-pair-map.tsv` (still no row for this guard — the pairing gap the ticket documents), `mutation-catalog.tsv`, `selftest-cache-inputs.tsv`, `scenario-liveness-selftest.sh`. Fixtures reused: `$SPEC` and `$SC_HDR`, no new tree. |
| AC-7 | satisfied | Own block with its own header at `:1180`, own `(scw)` prefix, placed before `(dd)` and after the `(sc)` block's `unset VSCORECARD; write_verdict`. Prefix collision checked: `scw` appears only in the new block, and `(sc1)`-style ids cannot match it. |
| AC-8 | satisfied | Verified by citing CI at this exact head rather than re-running it: run 33509839449, headSha 8b2793953f8a854c15d175d9ec1d535d67c4dc77 — `lint-and-selftests` job 99862567017 **success** (3m47s), which runs `shellcheck -e SC1091,SC2015,SC2181` (`ci.yml:31`), `jq empty` (`:34`) and `run-selftests.sh --full --exclude tools/install-topology-selftest.sh` (`:122-126`); and `selftests (macos, bash 3.2)` job 99862567281 **success** (5m53s). The lane's extra `--cache-dir` cannot have served this suite — it has no row in `tools/selftest-cache-inputs.tsv` — and the suite is logged running for real at 11s. Independently, the suite ran green in the probe clone. The PR body's own 4 sweep failures are the recorded `LEAN_ATTEND_MODE`/`LEAN_RUN_MODEL`/`CLAUDE_CODE_SESSION_ID` env leak from sweeping inside a spawned session, not this branch: the probe ran under `env -u` and was green. |
| AC-9 | satisfied | PR body's "Flagged, not done" section states OR-1's gap in the terms the ledger records — that `tools/mutation-pair-map.tsv` enforces that *a* killer exists and never that it reaches every subcommand — names the operator as owner, and states why reversing stays cheap. Matches the spec's Open Regions row at its `reversible-default-and-flag` default. |

## Panel

`review-toolkit:scope-completeness-reviewer` — approve, 0 findings (returned; the only reviewer
whose trigger fired). Its one suppressed note is that it did not inspect the PR body for AC-5's
transcript, being outside its domain; this round covered that directly and by re-probing.

The remaining dimensions were the lead pass's, per the collapsed-panel routing: performance,
maintainability, complexity and test coverage, plus security — its conditional did not fire (no
auth/tenancy/session/upload/query surface in a bash selftest diff, and the repo carries no
`.claude/second-shift/review-context/security-reviewer.md`), so the lead pass owned it. The one
thing it had to weigh is the `eval "$(sed … "$TOOL")"` lift, which executes bytes from a
repo-local sibling under a path the harness controls, in the shape `(dd)` already established in
this file — consistent, not a new gap. a11y and design-fidelity were not routed: no changed path
matches `stageParams.webComponentGlobs` (unset, resolving to `apps/web/**/*.{tsx,jsx}`), and the
spec declares no `## Design` section, so the run is unarmed and `fidelity` is `not-applicable`.
