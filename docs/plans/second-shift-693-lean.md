# second-shift #693 — an armed `fidelity: pass` must cite evidence

## Problem

The lean lane's armed design milestone checks that screenshots are _current_, never that they
match the design. Milestone 4's armed arm does four things: the verdict record's `fidelity`
header reads `pass`; a render receipt exists; the branch's render patch identity is computable;
the receipt's `rendered_from` equals that identity. Three of those are freshness or existence.
The fourth is a one-word header the reviewing model wrote about its own work, and nothing
compares anything to the design — so the gate is fully satisfied by a receipt of the wrong
screen, correctly hashed, with `pass` typed above it.

Separately, `figma-faithful/SKILL.md` step 7 asserts that "in an autonomous pipeline this artifact
is the gate `figma-faithful-plan-reviewer` reviews, and the pipeline branches on its verdict". No
lane does, and an outcome-gated harness structurally cannot branch on a process step's verdict.

## Fix shape

Two halves of one idea: make the design arm's claims match what it enforces.

1. An armed `--fidelity pass` write must carry a conforming `## Design fidelity evidence` table in
   its summary body — one or more rows per declared `RS-n`, six named columns, every cell
   populated, and a `verdict` cell that is `match` or a `deviation` citing an `AC-n` / `D-n` the
   spec declares. Refused at the WRITER (`cmd_verdict`), where the fix is one edit away, not at
   milestone 4 where it costs the round.
2. Correct step 7's claim about who dispatches the plan reviewer — do not delete the step.

**Honest scope: tamper-EVIDENT, not fidelity-proof.** This converts an unfalsifiable header into
one a human can falsify by reading the record, and raises the cost of a rubber stamp from typing a
word to fabricating node references, paired numbers, and a resolving citation. It verifies nothing
against the design.

## The grammar

```
## Design fidelity evidence

| RS-n | frame node | property | design | rendered | verdict |
| ---- | ---------- | -------- | ------ | -------- | ------- |
| RS-1 | Checkout / populated | control height | 32px | 32px | match |
| RS-1 | Checkout / populated | unit selector | number field | text input | deviation (AC-3) |
```

A table, not prose: the record body is run through prettier and `proseWrap: "always"` reflows
sentences, so a predicate over reflowed prose is fragile. Every other artifact this gate parses is
already a table.

Reading rules, each mirroring an idiom the gate already uses:

- **Section scope** mirrors `design_section()` — starts at the heading, ends at the next `#+`
  heading or EOF. A whole-body scan would read the spec's own 4-column RS table as a malformed
  evidence row.
- **Heading match** mirrors the same idiom: `tolower($0) ~ /^#+[[:space:]]+design fidelity
  evidence[[:space:]]*$/`. Any level, case-insensitive.
- **The declared set comes from `design_rs_rows()`**, the reader milestone 3 uses to build the
  receipt — not from `design_armed`'s prefix detector, which counts a row `design_rs_rows` drops.
- **The header row is the line immediately above the `| --- |` separator.** The data-row anchor
  cannot find it, and "first pipe-leading line" breaks on prose containing a `|`.
- **Columns are enforced by header row**, exactly six, in order, case-insensitively.
- **The `verdict` cell is a closed enum** parsed with `ledger-lint.sh`'s own idiom: a prefix match
  anchored on a non-word boundary (`^(match|deviation)([^A-Za-z0-9-]|$)`) plus
  `grep -oE '(AC|D)-[0-9]+'` for the reference.
- Cells other than `verdict` are checked for non-emptiness, not for a pattern — nothing in the
  repo carries per-`RS-n` node ids to cross-reference against.

## Acceptance Criteria

- **AC-1** — WHEN a verdict record is written with `--fidelity pass` against an armed spec and no
  `## Design fidelity evidence` section is present (including when `--summary-file` is omitted
  entirely), THEN the write is refused with a message naming the missing section.
- **AC-2** — WHEN that section omits any `RS-n` row the spec declares, THEN the write is refused
  naming the missing row(s); and WHEN it carries a row for an `RS-n` the spec does not declare,
  THEN the write is refused naming the undeclared row. Both directions, so a table carried over
  from a round before the spec dropped a state cannot pass silently.
- **AC-3** — WHEN the section's header row is absent, or does not name exactly the six required
  columns in order (case-insensitive), THEN the write is refused reporting the expected six and
  what was found.
- **AC-4** — WHEN a data row has any empty cell, THEN the write is refused naming the row and the
  empty column.
- **AC-5** — WHEN the section carries no data row at all, THEN the write is refused, even against
  an armed spec.
- **AC-6** — WHEN every declared `RS-n` has at least one fully populated row, no undeclared row is
  present, and every `verdict` cell is `match` or a `deviation` whose citation resolves, THEN the
  write is accepted. More than one row per `RS-n` is legal.
- **AC-7** — WHEN `--fidelity` is `not-applicable` or `fail`, or the spec is unarmed, THEN no
  evidence section is required and behavior is unchanged from today.
- **AC-8** — WHEN `design_state` returns `disarmed` or `error:<message>` and `--fidelity pass` is
  written, THEN the write is refused at the writer. The same refusal applies when the spec file
  itself cannot be read from the review checkout while a `design.provider` is configured: an armed
  ticket reviewed from a checkout missing its spec must not bank a `pass`. `cmd_verdict` does not
  call `design_state` today, so this read at the writer is new.
- **AC-9** — milestone 4's armed arm is unchanged; no already-committed verdict record is
  retroactively failed by this change.
- **AC-10** — stated as an end state, not a line range. After the edit: `figma-faithful/SKILL.md`
  step 7 no longer claims that an autonomous pipeline dispatches the plan reviewer or branches on
  its verdict, and it still carries the `block` / `fix-and-go` / `pass` enum. The
  `figma-faithful-plan-reviewer.md` `review-lead-skip` marker states who does invoke it — the
  operator, at figma-faithful step 7 — rather than asserting bare "invoked directly"; it must not
  say "dispatched by review-lead". For that citation to be true, corrected step 7 must retain an
  explicit _dispatch this agent manually_ instruction.
- **AC-11** — `review-lean/SKILL.md` step 5b carries the exact evidence-table grammar a reviewer
  must emit.
- **AC-12** — `lean-gate-selftest.sh` covers AC-1 through AC-9, and the new verdict path extends
  `scenario-liveness-selftest.sh`.
- **AC-13** — every existing armed `--fidelity pass` write that carries no summary is repaired by
  adding a minimal conforming evidence body, **not** by re-pointing it to `not-applicable` — the
  prettier verify-and-revert cases assert precisely that `fidelity: pass` survives a
  header-flattening formatter, so re-pointing would delete what they measure. Each repaired
  fixture must still measure what it measured before. The set is re-derived at this head, not
  taken from the ticket's line numbers.
- **AC-14** — the evidence table does not disturb `record_key`, an unanchored whole-file scan that
  milestone 4 uses for `rounds` and `reviewed_patch_id`. A selftest pins that a record whose
  evidence table contains `key: value`-shaped text still yields the header's values for both keys.
- **AC-15** — `tools/mutation-catalog.tsv` gains rows for the new guard, per CLAUDE.md's rule that
  editing or adding a guard's CODE re-anchors its catalog rows.
- **AC-16** — WHEN a `verdict` cell reads `deviation` with no `AC-n` / `D-n` reference, THEN the
  write is refused naming the row. A free-text reason is not a citation.
- **AC-17** — WHEN a `verdict` cell cites an `AC-n` or `D-n` the spec does not declare, THEN the
  write is refused as a dangling citation, naming the row and the unresolved reference.
- **AC-18** — WHEN a `verdict` cell cites an `AC-n` or `D-n` the spec does declare, THEN the row is
  accepted and `fidelity: pass` remains available. A cited deviation does not force `fail`, and no
  new `fidelity` value is introduced.
- **AC-19** — added mid-run, after the implementation surfaced the staleness: `docs/live-render.md`
  is the design lane's doc of record and its closing paragraph enumerates what the gate owns about
  the fidelity judgment. It must state what the gate now enforces about the record's shape, that
  this is tamper-evidence and not fidelity, and that there is no milestone-4 backstop.

## Explicitly out of scope

- Making the translation plan a lane-asserted artifact (a design-plan milestone) — deferred to
  #694.
- Broadening the plan reviewer's sizing check, and giving component-resolution suitability an
  owner — both edit an agent no lean-lane path dispatches. Same follow-up.
- Building the deferred pixel-diff gate — filed separately.
- The `design-faithful` (non-figma) family — no translation-plan step and no plan-reviewer agent.
- The merge-boundary readers (`lean-evidence.sh`, `scripts/check-lean-chain.sh`). A known partial
  fix, stated rather than skipped: `lean-evidence.sh` is the consumer-portable half and reads
  records this repo does not control, so extending it lands the legacy-record problem on consumers.

## Stated limit

The check verifies a citation _resolves_, not that it is _about_ that render state. A reviewer can
still cite a real but irrelevant `AC-n`. That is not statically decidable and this change does not
claim otherwise.
