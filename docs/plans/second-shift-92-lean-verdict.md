# Lean verdict — #92

verdict=needs-work
run_id: 2026-08-02T133308Z-lean-92
rounds: 1

## Summary

The gh-bot.sh resolver itself is well-built and satisfies AC-1/2/3/4/5/6/8: shellcheck-clean,
and gh-bot-selftest.sh, claim-selftest.sh, pipeline-doctor-selftest.sh, cost-block-selftest.sh
all pass with 0 failures locally. But the branch was cut before `origin/main`'s tip (missing
commit 1686280, PR #349 "promote the lean lane to default; deprecate the staged run"), and its
diff against current `origin/main` reverts that already-merged work: un-deprecates
`plugins/dev-pipeline/skills/run/SKILL.md`, and reverts `README.md`/`docs/onboarding.md`/
`docs/team-rollout.md`/`plugins/second-shift/skills/onboard/SKILL.md` from `/dev-pipeline:run-lean`
back to `/dev-pipeline:run` as the recommended default. Must rebase onto current `origin/main`
before landing. AC-7 also has residual gaps (warning): `pipeline-retro/SKILL.md` and
`tools/tracker/README.md` still instruct writes via bare `$GH_BOT` rather than the passthrough
form. A pre-existing note (not this PR's regression): a bot-disabled github+writes-true repo now
passes pre-flight/doctor cleanly per AC-4, but `claim-issue.sh` still hard-aborts on any non-`ok`
gh-bot.sh status, so the failure just moves later in the run.

## Findings

- **blocker** (confidence 95): branch based on stale main, diff reverts merged PR #349's
  lean-lane-default promotion across SKILL.md/README.md/onboarding docs. Must rebase before
  merge.
- **warning** (confidence 55): AC-7 not fully satisfied — `pipeline-retro/SKILL.md` and
  `tools/tracker/README.md` still reference bare `$GH_BOT`.
- **note** (confidence 55): `claim-issue.sh` unconditionally requires gh-bot.sh status=ok; a
  bot-disabled repo now passes pre-flight/doctor per AC-4 but still hard-aborts at claim time.
  Pre-existing behavior, out of this PR's stated scope.
