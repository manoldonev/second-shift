# 637 — Widen the prose census to agent contract files; discharge the #610 out-of-census residual

Part of #605. Discharges the named out-of-census residual #610 left behind.

`tools/prose-blockers.sh:80-83` (pre-#637) said agent contract files under `plugins/*/agents/`
"carry the same construct class and are a named out-of-census residual, routed to the
classification register rather than silently swept in or dropped." The register is #636's
`scripts/gate-buckets.tsv` — ratified to key on enforced gates in code, and an agent contract is
prose, so the residual was routed to a home constitutionally forbidden to house it.

The fix widens `corpus_files()` to also match `plugins/*/agents/*.md`, folding the 25 agent
contract files into the census/triage machinery that already handles this exact construct class
for `SKILL.md`.

## Acceptance Criteria

- **AC-1**: `corpus_files()` in `tools/prose-blockers.sh` matches agent contract files under
  `plugins/*/agents/` in addition to `SKILL.md`, with fixture copies still excluded by path
  exactly as today. `bash tools/prose-blockers.sh corpus` lists both kinds and no fixture.
  — Done: `find` now matches `-name 'SKILL.md' -o -path '*/agents/*.md'`, still piped through the
  same `grep -v '/fixtures/'`. `corpus` returns 51 files (26 `SKILL.md` + 25 agent contracts, 0
  fixtures) against the pre-widening 26.
- **AC-2**: Every construct the widened census reports carries a row in
  `docs/prose-blocker-triage.tsv` over the existing disposition/action enums, and
  `bash tools/prose-blockers.sh check` reports zero undispositioned constructs. The existing rows
  are unchanged except where the widening genuinely re-keys one.
  — Done: at the default (`stop`) tier — the tier `check` actually gates on — the widened corpus
  adds exactly **one** new construct, `pb-820b5ac8` (`plugins/design-toolkit/agents/`
  `figma-faithful-spec-reviewer.md:98`). A rough grep against the stop-tier vocabulary hits far
  more agent files (12 by a loose match), but the real predicate — clause-initial position,
  action-binding, no exclusion list — narrows that to one, which is the whole reason the census
  command is what counts rather than the rough pass (see the issue's own caveat: the parent
  epic's "80 constructs" grep figure did not reproduce either). No existing row's id changed.
  `bash tools/prose-blockers.sh check` exits 0.
- **AC-3**: Each new row's disposition is reached on its merits under #610's rules — `gate-backed`
  prose defaults to deletion with a pointer surviving only where the reader's flow would dangle;
  `promoted` requires that an enforcing mechanism **exists**; `deleted` states in one line why it
  was never a control.
  — Done: `pb-820b5ac8` is dispositioned `deleted`/`pointer-kept`. The construct cross-references
  the agent's own Severity Levels table (grading a missing Element Inventory `Blocker` rather than
  `Warning`); nothing checks an agent-emitted finding's severity — this agent dispatches
  schema-free (the gate engine that once could was retired in #574) — so it was never a control.
  Kept whole (not pruned) because the Scene-inventory-completeness section it points at would
  dangle without the cross-reference.
- **AC-4**: **No promotion is filed without checking the generator.** #623 and #624 both closed at
  pre-flight because a rule triaged `promoted` had no reachable enforcer. A `promoted` row here
  names the surface that would run the check and the path that reaches it, or it is not
  `promoted`.
  — N/A by construction: the one new row is `deleted`, not `promoted` (see AC-3) — no promotion is
  filed, so there is nothing for this AC to police on this pass. `check`'s malformed-record rule
  (a non-`deleted` row naming no enforcer is rejected) is what would catch a violation if one were
  attempted.
- **AC-5**: An agent contract has no run to stop and no milestone ladder, so a construct whose
  "stop" is the sub-agent declining to answer is triaged on that basis rather than by analogy to a
  lane gate. The header records the distinction so a later reader does not re-derive it.
  — Done: `tools/prose-blockers.sh`'s `## Corpus` section and `docs/prose-blocker-triage.tsv`'s
  header both state the distinction — an agent's only outcome states are "answer" and "decline to
  answer", so a stop marker is triaged against that narrower outcome, not against a checklist step
  a session refuses to pass. The one construct this pass found is a worked example of the
  distinction actually mattering: it carries a stop word (`is a Blocker`) but does not command a
  decline, so it triages `deleted` rather than being read as an abort/refusal.
- **AC-6**: The census tool's selftest covers the widened corpus: a fixture agent file with a
  blocking construct is censused, and a fixture under an excluded path is not.
  — Done: `tools/prose-blockers-selftest.sh` gains an `agent()` fixture helper (mirroring
  `skill()`), a real fixture agent contract (`plugins/core/agents/delta.md`, carries a commanded
  refuse-and-hand-back construct) and an excluded one under `scripts/fixtures/`
  (`copied-reviewer.md`). New assertions: the corpus lists the real one and not the excluded one,
  and the stop-tier census picks up the real one's construct text and not the excluded one's.

## Settled at intake — do not re-litigate

- Widening the census is the disposition. Dropping the residual, or filing it as a third ticket,
  were considered and rejected: the machinery exists and the class demonstrably transfers.
- This is a census, not the register. Nothing here enters the classification register
  (`scripts/gate-buckets.tsv`), and the register does not read this record.
- The `stop` tier stays the default predicate. #610 D-6 chose it deliberately; re-opening the tier
  question re-litigates it.

## Open regions

- OR-1: whether any construct in an agent contract warrants promotion at all, given AC-5. Resolved
  by measurement, not by assumption: the widened corpus's one live stop-tier construct triages
  `deleted`, not `promoted` — the expectation the issue itself states as the default outcome.

## Out of scope

- The classification register and its coverage guard.
- Re-keying the enforcer column.
- The `bold` and `all` tiers.
- Wiring `prose-blockers.sh check` into CI.
