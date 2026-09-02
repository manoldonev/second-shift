# second-shift #753 — delete the second clause of the amended-spec blocker

Re-cut 2026-09-02 at ratification (https://github.com/manoldonev/second-shift/issues/753#issuecomment-5506836099).
The gate, its zero-deletion proxy, its override carve-out and their obligations are dropped.
What remains is the deletion #622's ratification carried forward to this ticket: the second
clause of `plugins/dev-pipeline/skills/review-lean/SKILL.md`'s "Approve on the diff, not on the
spec's promises" bullet is deleted, not gated, and its triage row is reconciled.

## Acceptance Criteria

- AC-1: The second clause of the blocker sentence at
  `plugins/dev-pipeline/skills/review-lean/SKILL.md:168-169` — "A spec amended after the fact to
  match the diff is a blocker." — is deleted, leaving the surrounding bullet ("**Approve on the
  diff, not on the spec's promises.**") coherent. No gate, no override channel, and no selftest
  arm is added in its place.
- AC-2: `pb-b703544b` in `docs/prose-blocker-triage.tsv` is reconciled to its terminal
  disposition (`deleted` / `prose-deleted`), and its stale `sites` cell (currently `:164`) is
  regenerated to the construct's actual last site before deletion. `bash tools/prose-blockers.sh
  census` is re-run and `bash tools/prose-blockers.sh check` reports no construct with no row and
  no surviving-action row whose construct is gone.

## Design

Design: none — this repo's `second-shift.config.json` configures no `design.provider`; this
ticket touches only a skill's prose and a triage record.
