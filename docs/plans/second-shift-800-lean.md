# second-shift #800 — execute arm 2b's cut list for `review-lean`

Successor to #671 arm 2b (#748), whose leave-one-out ablation over the 17 units of
`review-lean/SKILL.md` at `8d5d0897` found that **no unit carries the 0.20** and returned three
cut-eligible units — U-5, R-3, R-4 — per the §5 precedent separating a verdict from its execution.
The list binds the pinned file only; every line added since `8d5d0897` is unmeasured.

Re-anchored on the current head (191 lines, pre-flight receipt `.claude/pipeline-state/800-ledger.md`):

- **U-5** pin 48–55 → head 48–63. Partly superseded: four measured sentences survive verbatim, the
  measured "score each `AC-n` as satisfied / unsatisfied / undeterminable" sentence was replaced by
  #755's `## AC scorecard` block, and #683 added the CI-citation rule.
- **R-3** pin 110–114 → head 163–167. Byte-identical.
- **R-4** pin 115–116 → head 168. Already half-cut: `d8ea88aa` (#753 / PR #776) deleted the second
  clause on independent grounds; the surviving one-line bullet is what this ticket cuts.

## Acceptance criteria

- AC-1: `plugins/dev-pipeline/skills/review-lean/SKILL.md` head line 168 — the
  `- **Approve on the diff, not on the spec's promises.**` bullet (R-4) — is deleted. No other line
  in that file changes.
- AC-2: U-5 (head 48–63) and R-3 (head 163–167) are **not** cut. `docs/skill-ablation.md` §2 gains a
  new subsection, immediately after *The cut list (AC-6)* and before *What bounds this arm*,
  recording: the pin→head line ranges for all three units, which survived verbatim versus was
  superseded, and the keep rationale for U-5 and R-3 (D-1, D-2 below).
- AC-3: `docs/skill-ablation.md` §2's *What bounds this arm* `review-lead`-absence bullet is
  extended to name R-3 alongside U-5, citing `plugins/review-toolkit/skills/review-lead/SKILL.md:533`
  ("the caller's inheritance contract").
- AC-4: `docs/skill-ablation.md` §5's C2 bullet ("C2's cut is localised, and is still not executed
  here") gains its own settled-by line recording that #800 executed the cut: R-4 deleted, U-5 and
  R-3 kept with reasons on file per AC-2.
- AC-5: `docs/prose-blocker-triage.tsv`'s `pb-85e129b1` row's `sites` cell is regenerated (`bash
  tools/prose-blockers.sh census`) to reflect the post-deletion line number. No other row changes —
  AC-1's deletion is the last line among the file's censused constructs, so it shifts that one row
  only.
- AC-6: `tools/capability-parity.tsv`'s `plan-vs-diff scope-drift gate` and `scope-completeness
  gate` NOTE cells are reconciled against the current `review-lean/SKILL.md` text (post-AC-1): the
  first stops citing the amended-spec clause #753/PR #776 already deleted, the second describes
  the four-score `## AC scorecard` (#755) rather than the retired three-way scoring. The
  `already-covered` / `dropped` dispositions themselves are unchanged — only the NOTE prose.
- AC-7: `bash tools/prose-blockers.sh check` and the standard selftest sweep stay green. No new
  guard, no new selftest case — a prose-only deletion gets no presence assertion (`writing-tests`
  skill).

## Out of scope

The fourteen `not-reached` units (owed a different metric per the arm-2b addendum's §C), every
line added to `review-lean/SKILL.md` since `8d5d0897`, and P10 independence. The re-measurement of
U-5 and R-3 with `review-lead` loaded (stays on #803). Any change to `capability-parity-check.sh`
itself — the NOTE cell is never parsed for claims, so this is register integrity, not a gate fix.
Checklist step renumbering (U-5 stands, so none is needed).

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | U-5 (checklist step 5) disposition | Not cut, with a reason on file. Bound (a) — `review-lead` absent from every arm — is exactly what U-5's opening sentence routes to, so its `no-effect` scores the apparatus rather than the unit. Re-anchored, the surviving measured text is interleaved with #755's scorecard block and #683's CI rule; deleting it leaves a step carrying a schema with no instruction to review and no reviewer named. Head line 48 also carries live census construct pb-dd909897, dispositioned promoted / guard-added at #622. | user-answered |
| D-2 | R-3 (inheritance bullet) disposition | Not cut, with a reason on file. Byte-identical to the pin, but `plugins/review-toolkit/skills/review-lead/SKILL.md:533` defers to it by name as "the caller's inheritance contract" (wired at #730), so bound (a) reaches R-3 too — §2 names only U-5 as exposed. No LOCKSTEP marker pairs the two sites, so deleting the referent would silently strand review-lead's rule 5. | user-answered |
| D-3 | R-4 (approve-on-the-diff bullet) disposition | Cut. Head line 168, one line. Zero live references anywhere in the tree; absent from the default-tier prose census; its operative clause was already deleted at #753 / PR #776, and the residue is carried by the gated AC scorecard. | user-answered |
| D-4 | Where the not-cut record and the re-anchoring evidence live | A new subsection of `docs/skill-ablation.md` §2, after *The cut list (AC-6)*: per-unit head ranges, what survived verbatim, what was superseded, and the keep rationale for U-5 and R-3. §5's C2 bullet gains its own settled-by line. `ablation-units.tsv` stays frozen at the pin. | user-answered |
| D-5 | Two stale `capability-parity.tsv` note cells | **Amended 2026-09-07, pre-build, by the operator: folded INTO this ticket.** Originally filed out-of-scope as #802; re-decided because a full lane run costs roughly 7 to 70 USD and two sessions against a two-line edit. #802 is closed as folded and the scope now sits in this ticket's body. `plan-vs-diff scope-drift gate` cites the clause #776 deleted; `scope-completeness gate` predates #755's four-score change. Neither reds — the NOTE cell is never parsed for claims. Rows for `run-authoritative acceptance-criteria snapshot` and `code-review fan-out panel` keep their basis now that U-5 and R-3 stand. | user-answered |
| D-6 | Successor for a `review-lead`-loaded re-measurement | Filed as #803, then **split 2026-09-07**: its measurement half stays on #803, and its two-line §2 bounds-statement correction is folded into this ticket, being the same fact D-2's keep rationale establishes and three lines from the subsection D-4 already adds. | user-answered |
| D-13 | §2's *What bounds this arm* names only U-5 as exposed to the `review-lead`-absence bound | Extend the bullet to name R-3, citing `review-lead/SKILL.md:533`. In scope here per D-6's split. Distinct from D-4's new subsection: D-4 records the execution, this corrects the report's own statement of what bounded it. | user-answered |
| D-7 | Verification for a prose-only deletion | No new guard. The `writing-tests` skill forbids prose-presence guards, so R-4's absence gets no assertion. Verification is the standard sweep plus `bash tools/prose-blockers.sh check` staying green. | codebase-derived |
| D-8 | pb-85e129b1's sites cell in `docs/prose-blocker-triage.tsv` | Regenerate 169 to 168 in the same commit. Deleting head line 168 shifts that one row and no other; the record's cell is hand-maintained, and #776 set the precedent of regenerating a stale sites cell in the commit that moves it. | codebase-derived |
| D-9 | Checklist renumbering | None. `lean-gate.sh` cites "step 5b" at three sites, one of them a runtime message, and `docs/testing.md:965` cites "step 5c". U-5 stands in any case, so the numbering is untouched. | codebase-derived |
| D-10 | Commit verb and changelog trailer | `fix(dev-pipeline):` with `Changelog: none` — the shape #776 used for this bullet's other half. Patch bump per CLAUDE.md; the rule's substance survives in the gated scorecard, so no consumer-visible behavior change. | codebase-derived |
| D-11 | Whether the re-measurement successor also covers the fourteen `not-reached` units | Parked under OR-1 (owner: operator, at the successor's intake). | deferred |
| D-12 | Whether `tools/prose-blockers.sh check` gets wired into CI | Parked under OR-2 (owner: operator, out of band). | deferred |

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | Whether the filed re-measurement successor (#803) also covers the fourteen `not-reached` units, or leaves them routed to their own metric | reversible-default-and-flag |
| OR-2 | `tools/prose-blockers.sh check` is wired into no CI workflow, so a triage row stranded by a prose deletion rots silently | reversible-default-and-flag |

**OR-1** takes the default that #803 covers U-5 and R-3 only, and the fourteen stay routed to a
different metric per the arm-2b addendum's §C. Reversing it costs an issue-body edit before #803
is picked up, so the default is cheap to undo and the flag is on that issue itself.

**OR-2** takes the default of changing nothing: `ci.yml:171` records that #610 D-9 left this
unwired deliberately, because the gate-bucket register was designated the living coverage guard.
Flagged because this ticket is the first to discover the consequence — a unit cut can strand its
triage row with nothing to catch it — not because BUILD should wire it mid-slice. Wiring it later
is a one-line CI step, so nothing here forecloses it.
