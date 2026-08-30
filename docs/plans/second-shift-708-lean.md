# #708 — the provider's fidelity reviewer is mandatory on an armed run, and the verdict names who reviewed

Slice 1 of 4 of #705 (sequential; successor #709). Closes the two halves of one hole: on an
armed design run the provider's fidelity reviewer is routed by model judgment over a glob, so a
round can proceed with the design dimension silently unrun — and nothing in the verdict record
says which reviewers ran, so no gate can ask.

## Decision Ledger

Carried from the #705 intake receipt (`.claude/pipeline-state/705-ledger.md`), which is the
binding pre-flight input for this slice; ids and Resolutions are its own.

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Is the provider's fidelity reviewer mandatory on an armed run, or opt-out? | Mandatory, unconditionally: not glob-gated, not judgment-gated. | user-answered |
| D-2 | What does "armed" mean to a gate, and where does the provider come from? | `design_armed()` (the shared LOCKSTEP `lean-design-armed`); the provider FAMILY is derived from the handoff link's host, never from config, because the config is gitignored and no CI checkout can see it. | codebase-derived |
| D-5 | What is the reviewer-dispatch attestation? | A `panel:` verdict header key — the reviewer agent types review-lead actually dispatched, comma-separated, from `code-review.mjs`'s structured result. Tamper-EVIDENCE at the same altitude as arms 1–8. | user-answered |
| D-6 | Non-selection and went-dark. | Two failures, two criteria: (a) routing on an armed spec always selects the reviewer; (b) if that one reviewer goes dark, 5c voids the round even when every other reviewer returned. | codebase-derived |
| D-11 | Does `panel:` list dispatched or RETURNED reviewers? | Returned only — `code-review.mjs` marks a dark one `failed: true` and it is excluded. Arm 8 therefore also catches went-dark; 5c's widening is still needed so no record is written at all. | codebase-derived |
| D-12 | Name form and match rule. | QUALIFIED names (`design-toolkit:figma-faithful-reviewer`), as review-lead's own panel enumerates them. Exact comma-separated token match, never a substring. | codebase-derived |
| D-13 | Which URL is the handoff, and at what host granularity? | The FIRST recognised host in the `## Design` section: any `*.figma.com` host → `figma`; host `claude.ai` with a `/design` path prefix → `claude-design`. No recognised host → violation. Other URLs in the section are ignored. Gate and boundary share the derivation as a LOCKSTEP pair. | user-delegated |
| D-14 | Host-derived family vs config `design.provider` disagree. | The HOST wins on an armed spec; the disagreement is a milestone-1 red at the gate, which is the only side that sees both. Config selects only for UNARMED diffs, via the existing glob trigger. | user-delegated |
| D-15 | Grandfather armed records written before `panel:` existed? | No. Nothing armed is in flight in this repo, and consumers fetch the boundary at their pinned ref. | user-delegated |
| D-16 | Toolkit-absent on an armed spec. | review-lead refuses the round outright and emits its "review did not run" report naming the missing reviewer; review-lean hands back per 5c. Not a note. | user-delegated |
| D-17 | What the writer refuses. | A `--panel` that is missing, empty, or lacking the host-implied reviewer — a writer-side copy of arm 8, in the same LOCKSTEP pair as D-13. | user-delegated |
| D-18 | Always-spawn on trailer-only armed rounds? | Yes, every armed round. An armed round is rare; the cost is accepted. | user-delegated |

## Design

Design: none — this slice changes gate/boundary shell and two skill contracts. It ships no web
component and this repo configures no `design.provider`, so there is no render state to declare.

## Acceptance criteria

- AC-1: with an armed spec, `review-lead`'s routing table makes the provider's design-fidelity
  reviewer an **always-spawn** row — independent of `stageParams.webComponentGlobs`, never
  depth-suppressed, and selected by the handoff family rather than by model judgment. The glob
  trigger is retained for unarmed diffs. Toolkit-absent on an armed spec is a VOID of the round
  (the "review did not run" report naming the missing reviewer), not a summary note.
  `plugins/review-toolkit/scripts/check-reviewer-references.sh` stays green — the three
  sub-registries it diffs still agree.
- AC-2: `review-lean` 5c voids a round when the mandatory fidelity reviewer went dark on an armed
  spec, even when every other selected reviewer returned; the hand-back comment names which
  reviewer. No verdict record is written for such a round.
- AC-3: `bash G verdict` on an armed spec refuses a missing or empty `--panel`, and refuses one
  whose comma-separated tokens do not contain the reviewer the handoff host implies; the record
  it does write carries `panel:` in the header, and the reader both the gate and the boundary use
  (`panel_key`) reads the whole comma-separated value back unchanged after the format step —
  `header_key`'s charset truncates a qualified list to its leading token, which is why the key gets
  a reader of its own rather than a widening of the shared one.
- AC-4: `scripts/check-lean-chain.sh` evidence arm 8 reds an armed PR whose `panel:` is absent or
  lacks the host-implied reviewer, and greens one that carries it. A `claude.ai/design` handoff
  requires `design-toolkit:design-faithful-reviewer`; a `*.figma.com` handoff requires
  `design-toolkit:figma-faithful-reviewer`; an unrecognised host is a violation, not a pass.
  `lean-evidence.sh` is deliberately NOT extended — its OR-1 note excludes the design arms.
- AC-5: the host→family derivation and the panel token match are ONE block held in lockstep
  between `lean-gate.sh` and `scripts/check-lean-chain.sh`; `check-lockstep-pairs.sh` stays green.
  Gate-side, `design_state()` reds milestone 1 on an armed section whose first handoff link names
  no recognised provider host, and on a host/`design.provider` family disagreement.
- AC-6: `scenario-liveness-selftest.sh`'s design legs gain (a) an armed run whose `panel:` lacks
  the host-implied reviewer — milestone 4 reds and the boundary reds; (b) an armed round whose
  mandatory reviewer went dark — the writer refuses and no verdict record is written.
  `check-lean-chain-selftest.sh` gains the host-derivation legs (figma, claude-design,
  unrecognised).
- AC-7: every new guard has a `tools/mutation-catalog.tsv` row, and every existing row this diff
  re-anchors is updated in the same diff. Every new refusal site carries a
  `scripts/gate-buckets.tsv` row, and an existing anchor this diff makes ambiguous is tightened to
  its own site.
- AC-8 (docs): `docs/live-render.md` states that the provider's fidelity reviewer is mandatory on an
  armed spec, that `panel:` is the attestation, and that the family is host-derived;
  `docs/testing.md`'s "lean verdict-record key schema" duplication-register entry names `panel:` and
  says why it has a reader of its own.
- AC-9: `feat(dev-pipeline):` with a `Changelog:` trailer; no `version` or `CHANGELOG.md` edits.

## Out of scope

The disarm override (#709 / S-2), the plan-review record (#710 / S-3), rects (#711 / S-4).
