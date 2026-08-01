# Lean verdict — #247

verdict=approve
run_id: 247-20260801T110329Z
rounds: 1

## Summary

The 3-file diff (spec doc, `check-model-tiers.sh`, `check-model-tiers-selftest.sh`) closes
exactly the gap the spec describes: an in-enum inline `model:` literal on the three MAP
files' `structured-emitter` dispatch now lockstep-checks against frontmatter via a new
`inline_pairs` pass that reuses `check_pair`. Verified directly: the real script exits 0 on
this repo (AC-3); the new selftest case fails specifically (and only that case) when run
against the pre-fix script body while all 14 other cases still pass (AC-4, confirmed
empirically); the header comment records the widened contract (AC-5); AC-1's
MISMATCH-with-agent-name behavior is confirmed via selftest and a manual run; AC-2's
override precedence generalizes to MAP-inline literals (confirmed via a manual
override-reconciliation probe — the new loop reuses the already-tested `check_pair`
codepath verbatim, so there is no MAP-inline-specific branching to regress independently).
shellcheck is clean on both changed scripts. The diff-scoped mutation sweep for
`check-model-tiers.sh` produced a survivor set identical to the 8 rows already in
`tools/mutation-baseline.tsv` — no baseline update owed.

## Findings

- note (confidence 55) — AC-2 (override precedence for MAP-inline literals) has no
  dedicated selftest fixture; only proven by manual probe. Non-blocking: the new loop calls
  `check_pair` unchanged, so the existing override coverage on the scalar/table paths
  already exercises the only branching that matters. Not required to merge.
