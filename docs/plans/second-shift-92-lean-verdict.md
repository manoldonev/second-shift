# Lean verdict — #92

verdict=approve
run_id: 2026-08-02T133308Z-lean-92
rounds: 3

## Summary

Round 1 flagged one blocker (confidence 95): the branch was cut before `origin/main`'s tip
(missing commit 1686280, PR #349 "promote the lean lane to default; deprecate the staged run"),
and its diff reverted that already-merged work across `SKILL.md`/`README.md`/onboarding docs.
Fixed by merging `origin/main` into the branch (merge commit `01c2845`, pushed) — the diff
against those four files is now empty and 1686280 is an ancestor of HEAD.

Round 2 re-verified independently and approved with three residual findings (one warning, two
notes) and a post-approval mechanical AC-7 completion (commit `90fcbe3`, dev-pipeline files
only).

A separate, independent multi-reviewer review (outside this lean run) then surfaced two further
items round 2 missed: **AC-7 was still not repo-wide** — `plugins/intake-toolkit/skills/
intake-orchestrator/SKILL.md` (a different plugin) had five bare-`$GH_BOT` write sites round 2's
dev-pipeline-only sweep never reached — and a **security finding**: `gh-bot.sh`'s config-supplied
`tracker.bot.envVar` reached an `eval`, an injection sink. Both were fixed (commits `6651b29`,
`c018e68`, `c047b9f`): the eval is replaced by bash's `${!name}` indirect expansion gated by an
identifier-format regex; intake-orchestrator's five sites now resolve dev-pipeline's `gh-bot.sh`
via the plugin-install-path convention (`${CLAUDE_PLUGIN_ROOT}` there resolves to intake-toolkit,
not dev-pipeline, so the direct passthrough shorthand doesn't transfer). Additional test coverage
closed real gaps that review also named: `gh-bot.sh`'s real (non-mocked) `git rev-parse
--git-common-dir` root derivation (main checkout, subdirectory, and linked worktree — previously
every case injected `SECOND_SHIFT_REPO_ROOT`, so the branch every real invocation actually takes
was untested), a doctor `(d7-bot)` case for the `ok` status, a `claim-issue.sh` disabled-resolver
case (aborts before the mock wrapper is ever invoked), `rc` assertions on all five `--path`
statuses, and the `claim-issue.sh` parity guard now anchors on the actual invocation instead of a
comment-matchable substring. `mutation-baseline.tsv` was re-baselined to drop two rows the new
coverage now genuinely kills.

Round 3 independently re-verified all of it end to end: shellcheck (0.11.0, project's exact
exclusion set) clean on every changed `.sh` file; `gh-bot-selftest.sh` (16/16), `claim-selftest.sh`
(12/12), `pipeline-doctor-selftest.sh` (20/20), `e2e-replay-selftest.sh` (31/31) green; the full
49-suite `*-selftest.sh` sweep (`SKIP_STRESS=1`, `-P4`) clean; `check-lockstep-pairs.sh`,
`check-frozen-files.sh`, `check-changelog-trailer.sh` all pass; `tools/mutation-sweep.sh --mode pr`
shows `gh-bot.sh` survivors `{fail-open::2, cmp-z::1, logic::1}` and `pipeline-doctor.sh`'s 8
pre-existing survivors matching the baseline exactly — no baseline-absent survivor. Every
remaining bare `$GH_BOT` mention repo-wide was cross-checked and confirmed descriptive prose, not
an unconverted write site. All AC-1 through AC-8 satisfied; no blockers.

CI also caught a shellcheck-version gap (SC2119/SC2120 on `run_claim_disabled`'s optional-default
`$1`, flagged by CI's older shellcheck but silent on the local 0.11.0) — fixed with standard
disable comments in commit `c047b9f`, included in round 3's re-verification.

## Findings

None outstanding. Round 2's three residual findings are all resolved (see above); round 3
returned zero new findings.
