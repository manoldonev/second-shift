# Lean verdict — #237

verdict=approve
run_id: run237-1785579516
rounds: 1

## Summary

Round 1 of `workflows/lean-review.mjs` returned `verdict=approve`. (A first dispatch,
against the pre-rebase two-dot range, hit the review's 15-minute wall-clock ceiling —
the branch was 4 commits behind `origin/main` at that point, and the reviewer's own text
flagged the literal `base..head` diff as noise from that staleness. The branch was
rebased onto current `origin/main`, milestones 1-3 were re-verified green, and the
review was re-dispatched against the resulting clean diff, which completed well inside
the ceiling.)

The reviewer verified `tools/resolve-worktrees-dir.sh` directly (shellcheck, jq
validation, the 9-case selftest, a manual end-to-end run against `preflight.sh`),
confirmed all six named call sites (be-fe-pair loop, Stage-1 pin, Stage-2 single-repo
add, Stage-2 statectl-persist, Stage-10 cleanup, `preflight.sh` advisory) route through
it with no retained inline derivation, confirmed the full 58-suite `*-selftest.sh` sweep
is green, and confirmed commit hygiene (honest `fix:` verb, `Changelog:` trailer
present, no frozen release files touched). All five spec ACs were assessed as met.

Two non-blocking findings were raised (see below). The `warning` — Stage 1/Stage 2's
resolution-failure paths discarding the resolver's specific stderr reason for a generic
placeholder, unlike Stage 10 — was addressed in a follow-up commit
(`bb2a284`) after the verdict landed: all four resolve-worktrees-dir.sh call sites in
Stage 1/2 now capture and surface the resolver's actual stderr text in the persisted
`failureContext`, matching Stage 10's existing pattern. Milestones 2 and 3 were
re-verified green after that commit. The `note` (no direct `preflight-selftest.sh`
assertion on the advisory report's worktree-path line) was left as the reviewer
characterized it: a pre-existing, low-risk gap, not a regression, out of scope for this
fix.

## Findings

- **warning** (addressed post-verdict, commit `bb2a284`): Stage 1's and Stage 2's
  (single-repo + be-fe-pair) resolution-failure paths lost the resolver's specific
  stderr reason in favor of a hardcoded placeholder string in `failureContext`, unlike
  Stage 10's cleanup and the original be-fe-pair loop. Fixed by capturing
  `resolve-worktrees-dir.sh`'s stderr (`2>&1`) and passing it through as
  `pinError`/`gitError` instead of a fixed literal.
- **note** (left as pre-existing, out of scope): `preflight.sh`'s rewired worktree-path
  advisory line has no direct `preflight-selftest.sh` assertion. Pre-existing gap (the
  line was equally unasserted before this diff), manually verified correct
  (`../acme-worktrees/acme-EXAMPLE-KEY` default rendered correctly for a config with no
  `worktreesDir` key). Not fixed here.
