# #247 — check-model-tiers: lockstep-validate inline `model:` literals in the three MAP files

## Problem

`check-model-tiers.sh` has two parse loops. The MAP loop (`code-review.mjs`,
`intake-review.mjs`, `design-sync.mjs`) extracts `'agent': 'model'` table entries and
lockstep-checks them (`check_pair`) against agent frontmatter. The scalar loop
(`unit-tests.mjs`, `plan-review.mjs`) resolves a file scalar and ALSO lockstep-checks any
inline `model: '<tier>'` literal on an `agentType:` dispatch line, falling through to the
scalar when no inline literal is present.

All three MAP files carry exactly one such inline dispatch each — a `structured-emitter`
call with `model: 'haiku'` — and neither loop validates it: the MAP grep can't match an
inline literal (`model:` is an unquoted key, not a `'key': 'value'` pair), and the inline
handling lives inside the scalar loop's own `for spec in` list, which never iterates the
three MAP files. So an in-enum drift on one of these three literals (e.g. flipping
`code-review.mjs`'s `structured-emitter` dispatch to `model: 'opus'`) is real,
cost-increasing drift that the gate does not catch — the exact class it exists to prevent.

#245 added an `UNKNOWN-MODEL` scan that already runs over all five parsed workflow files, so
an out-of-enum token in one of these three inline literals is caught. It deliberately did
not extend *lockstep* (in-enum drift) validation to them. This spec closes that narrower,
remaining gap.

## Acceptance Criteria

- **AC-1**: An inline `model: '<in-enum tier>'` literal in a MAP file (`code-review.mjs`,
  `intake-review.mjs`, `design-sync.mjs`) that disagrees with the dispatched agent's
  frontmatter (and has no reconciling `reviewers.modelOverrides` entry) makes
  `check-model-tiers.sh` exit 1 with a `MISMATCH` line naming the agent.
- **AC-2**: The existing override precedence in `check_pair` (config
  `reviewers.modelOverrides` > table/inline literal) applies unchanged to these MAP-file
  inline literals — a `modelOverrides` entry that reconciles the literal keeps the run
  green.
- **AC-3**: `check-model-tiers.sh` still exits 0 on this repo unchanged — all three shipped
  inline literals are `haiku`, matching `structured-emitter`'s frontmatter.
- **AC-4**: `check-model-tiers-selftest.sh` gains a behavioral case whose fixture makes the
  **pre-fix** script exit 0 (an in-enum inline MAP literal that disagrees with frontmatter,
  with no `UNKNOWN-MODEL` involved), so the new guard is demonstrably non-vacuous — the case
  must go from pass to fail if the fix is reverted.
- **AC-5**: `check-model-tiers.sh`'s header comment block (the "Tables validated" /
  "Error classes" notes) is updated to record the widened contract: MAP-file inline literals
  are now lockstep-validated like their scalar-file counterparts, not just enum-checked.

## Non-goals

- No change to the MAP files' non-inline `agentType:` dispatch lines that carry no `model:`
  declaration at all (e.g. `intake-review.mjs`'s other dispatches) — nothing to lockstep,
  correctly out of scope per the issue's own notes.
- No change to `UNKNOWN-MODEL` scanning, which already covers all five files.
