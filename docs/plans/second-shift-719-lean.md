# second-shift #719 — `check-guard-budget.sh` and the `Guard-mass:` trailer are deleted

*Re-cut 2026-08-30 after operator objection. The rev-4 draft replaced the budget with a ratchet
script; this version replaces it with **nothing**.*

`scripts/check-guard-budget.sh` waives growth on a trailer (`scripts/check-guard-budget.sh:83`).
#645 raised its own ceiling twice; #637's only blocker was a budget red fixed by an *empty* trailer
commit that cost a full re-review round (58% of that run). It is a symptom treated as a control,
and P5 says a reminder is not a control. The stopping rule is the operator's judgment plus the
`harness-internal` filing rule on #717 — not another script.

Both issue comments ratify this deletion (2026-08-30, operator, original cut and the re-cut).

## Acceptance Criteria

- **AC-1** `git grep -nE 'Guard-mass|check-guard-budget' -- . ':!docs/plans' ':!CHANGELOG.md'`
  prints nothing [base: 29 hits / 11 files].
- **AC-2** `test ! -e scripts/check-guard-budget.sh -a ! -e scripts/check-guard-budget-selftest.sh`.
- **AC-3** `awk -v j='  pr-gates:' '$0==j{f=1;next} /^  [a-z-]+:$/{f=0} f' .github/workflows/ci.yml
  | grep -cE '^\s*run:.*check-guard-(budget|ratchet)'` → 0 [base: 1].
- **AC-4** Net diff of the PR is negative: `git diff --shortstat origin/main` shows deletions >
  insertions by ≥ 200.
- **AC-5** Full sweep green; `check-workflows-selftest.sh` green (it parses `ci.yml`).

## Scope boundary

No replacement mechanism of any kind (no ratchet, no smaller budget, no register) — the ticket's
"Delete" section names the entire change. Every reference site is prose-only edits, none of them
behavior changes beyond removing the deleted script's mention.

## Adversarial pass (from the issue)

| Botch | Closed by |
| --- | --- |
| Replace with a smaller budget/ratchet | AC-3's `(budget\|ratchet)` alternation; AC-4 |
| Leave prose describing the deleted script | AC-1 |

Changelog: none (repo CI only). Migration: drop `Guard-mass:` trailers.
