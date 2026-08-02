# Lean verdict — #92

verdict=approve
run_id: 2026-08-02T133308Z-lean-92
rounds: 2 (+ post-approval AC-7 completion commit `90fcbe3`, no re-review needed — mechanical, non-blocking)

## Summary

Round 1 flagged one blocker (confidence 95): the branch was cut before `origin/main`'s tip
(missing commit 1686280, PR #349 "promote the lean lane to default; deprecate the staged run"),
and its diff reverted that already-merged work across `SKILL.md`/`README.md`/onboarding docs.
Fixed by merging `origin/main` into the branch (merge commit `01c2845`, pushed) — the diff
against those four files is now empty and 1686280 is an ancestor of HEAD. Round 2 re-verified
independently: gh-bot.sh's three-rung ladder and five-token `--status` contract (AC-1);
unset-env + resolvable wrapper → `ok`, no empty-path message in any branch (AC-2); distinct
remediation per status in both the pre-flight gate and `pipeline-doctor.sh` (AC-3); `enabled`
false/absent skips both checks without failing (AC-4); every resolution site honors
`tracker.bot.envVar` (AC-5); `claim-issue.sh`/`pipeline-cost-block.sh`/`install-gh-bot.sh`
delegate to `gh-bot.sh` with no private ladder and the lockstep row is retired (AC-6); SKILL.md,
pr-revision/SKILL.md, and stages 1/3/4/6/7/8/9 convert their prose write sites to the passthrough
(AC-7, with a residual gap noted below); `gh-bot-selftest.sh` covers every case in scope and
`pipeline-doctor-selftest.sh` carries the `(d7)` group (AC-8). shellcheck, `jq empty`, and the
full `*-selftest.sh` sweep (269 passed/0 failed) are clean; `tools/mutation-sweep.sh --mode pr`
shows no baseline-absent survivor; `check-lockstep-pairs.sh` and `check-frozen-files.sh` both
pass; commits carry the correct `feat(dev-pipeline):` verb and `Changelog:` trailers.

## Findings

- **warning, RESOLVED** (confidence 70, carried from round 1): AC-7 was not fully satisfied
  repo-wide — `plugins/dev-pipeline/skills/pipeline-retro/SKILL.md` and
  `plugins/dev-pipeline/skills/run/tools/tracker/README.md` still instructed writes via bare
  `$GH_BOT` rather than the passthrough form (neither file was in the original changed-file
  list). Fixed in commit `90fcbe3`: both sites now read
  `bash "${CLAUDE_PLUGIN_ROOT}/skills/run/tools/gh-bot.sh"`; `grep -rn '\$GH_BOT'` over both
  files now returns nothing. Mechanical, no behavior change — no re-review round needed.
- **note** (confidence 55): `claim-issue.sh` still hard-aborts on any non-`ok` gh-bot.sh status.
  A bot-disabled repo now passes pre-flight/doctor cleanly per AC-4 but still fails later at
  claim time — pre-existing behavior, unchanged by this PR, out of its stated scope.
- **note** (confidence 45): `pipeline-doctor-selftest.sh`'s `(d7)` group has no explicit case for
  the `status=ok` branch (all five tokens named in AC-8 are covered elsewhere by
  `gh-bot-selftest.sh`'s own repro case). Low risk; not blocking.
- **note** (confidence 40): a couple of mechanically-converted prose sites (e.g.
  `stages/9-open-pr.md:9`) read awkwardly after the `$GH_BOT` → passthrough substitution.
  Cosmetic only.
