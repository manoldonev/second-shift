# Lean verdict — #113

verdict=approve
run_id: lean113-ef8e0597
rounds: 1

## Summary

Reviewed diff `0f62506..eece7de` (retire dead `commands.<repo>.build`, route onboarding
through an `ext:build` extraLane) against `docs/plans/second-shift-113-lean.md`. All 13
acceptance criteria verified against the diff, not just prose: AC-1 (onboard SKILL.md
Step 3 drops `build` from the fixed key list and adds the drafted-`extraLanes` paragraph
with `failureClass: "TYPE_ERROR"`, editable/removable on the review screen, plus a
RE-onboard migration note), AC-2 (`schema/second-shift.config.schema.json`'s
`commands.<repo>.build` property removed), AC-3 (`config-lint.sh`'s accepted-keys diff
list and string/null type-check list both drop `build`; the unknown-keys note text now
names `commands.<repo>.build` as removed), AC-4 (`valid-monorepo-github.json` and
`valid-be-fe-pair-jira.json` (both `be`/`fe` occurrences) drop their `build` lines; new
`invalid-removed-commands-build.json` fixture + matching `expect_violation` line added —
`config-lint-selftest.sh` run directly, all green including the new case), AC-5 (the
other fixtures carrying a stale `build` key — `preflight-selftest.sh` ×2,
`scenario-liveness-selftest.sh` ×1, `lean-gate-selftest.sh` ×1 — all cleaned), AC-5b
(discovered mid-implementation and folded into the spec: `preflight.sh`'s own Section-5
lane loop probed a `build` lane as a fifth trio member — dead code once the key no
longer exists in any valid config; removed along with its comments and the one selftest
assertion that exercised it), AC-6 (`docs/migrations/v1-to-v2.md` gets a new "Dead-key
removal" entry for `commands.<repo>.build`, phrased like the existing
`integrationTest`/`apiTest` entry), AC-7 (`docs/config-schema.md`'s `commands` row drops
`build`), AC-8 (`docs/extending.md` §3.2 gets the build/compile-step sentence with the
AOT-escape motivation), AC-9 (confirmed via `git diff --stat` that `verifyctl.sh` is
untouched, and `verifyctl-selftest.sh` re-run directly stays 32/32 green unmodified),
AC-10 (`mutation-sweep.sh --mode pr --base origin/main` run directly from the worktree:
`config-lint.sh` swept, survivor IDs `plugins/dev-pipeline/skills/run/tools/config-lint.sh::fail-open::1`
and `catalog::config-lint-lanes-name` — both byte-identical to the existing
`tools/mutation-baseline.tsv` rows, confirming no re-anchoring was needed; `preflight.sh`
deferred to nightly as a slow suite), AC-11 (repo-wide `shellcheck -e
SC1091,SC2015,SC2181` clean, `jq empty` clean on every changed `.json`, and the full
49-suite `*-selftest.sh` sweep, `-P 4 SKIP_STRESS=1`, run directly from the worktree:
269/269 green, 0 failures).

Scope correctly followed the maintainer's redirect in the issue's comment thread rather
than the original issue text: no new verifyctl failure class, no fourth SUITE lane —
`ext:build` rides the existing `extraLanes` (EP-2) mechanism, which is already covered by
`verifyctl-selftest.sh`'s extraLanes cases. Commit verb is the honest `fix:` (a dead
config field is a bug; this repo dogfoods second-shift, so AI-tooling changes are
`feat`/`fix`, never `chore`), with a substantive `Changelog:` trailer. No frozen release
artifacts touched.

## Findings

None.
