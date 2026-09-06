# second-shift #748 — arm 2b: attributing `review-lean`'s delta to units

C2 reached `cut-to-delta` at recall 0.80. That verdict says `review-lean`'s prose does not keep its
mass; it says nothing about **which** lines carry the 0.20. #644 and #747 both stopped there
deliberately — a cut chosen by reading is the guessing the pre-registration exists to stop.

This slice runs the attribution: **leave-one-out ablation** over `review-lean`'s SKILL against the
one sample the bare arm missed, scoring whether the ground-truth blocker survives the removal. The
rubric — the 17 units and their exact line ranges, the reach prediction, the control, the void
condition, the replicate schedule, the hit rule and cut eligibility — was registered in
[`docs/skill-ablation-addendum.md`](../skill-ablation-addendum.md) §C before any run. It is executed
here, not re-derived, and it is **not edited here**: a threshold changed with a result in hand is
the post-hoc rubric §C exists to prevent.

The output is a **cut list**, never a cut. The deletion is a further successor of #671, per the
[`docs/skill-ablation.md`](../skill-ablation.md) §5 precedent separating a verdict from its
execution.

## Acceptance criteria

Derived at intake — #671 carries no numbered criteria of its own; these are the issue's AC set
verbatim in substance.

- **AC-1** — Leave-one-out ablation is run per the rubric registered in
  `docs/skill-ablation-addendum.md` §C, over `plugins/dev-pipeline/skills/review-lean/SKILL.md` **as
  it stands at `8d5d0897`**, one unit removed per run. The unit is the finest registered one — each
  of the 10 numbered checklist steps, each of the 6 non-negotiable rule bullets, and the preamble:
  17 units at the line ranges §C fixes. Ablating by `##` heading is excluded.
- **AC-2** — The ablation runs against **C2-a** — PR #654 @ `cfba102` — the sample carrying the one
  ground-truth blocker the bare arm missed: the gate-bucket enumerator's command-position class
  omitting keyword-preceded calls, so `else envfail` at `lean-gate.sh:420` sits outside the
  denominator.
- **AC-3** — Each unit is classified against the registered rubric into exactly one of: produced the
  missed finding (`carrier`); produced nothing either arm did differently (`no-effect`); or
  indeterminate — where §C's `not-reached — no basis` and `undetermined` are the registered forms
  the third takes. The classification cites the run that establishes it; no unit is classified from
  reading alone.
- **AC-4** — The localisation is made against **both** comparators: the bare arm committed under
  `docs/plans/skill-ablation/c2-review/`, and the `/code-review` arm from #747.
- **AC-5** — Every ablation transcript is committed verbatim under
  `docs/plans/skill-ablation/c2-review/`, and that directory's `README.md` describes the new family.
- **AC-6** — The result is an explicit cut list: which units of the pinned file fall inside
  `review-lean`'s delta and which do not, accompanied by an explicit statement that the list does not
  bind the lines added since `8d5d0897`.
- **AC-7** — `docs/skill-ablation.md` is reconciled: §2, §4's `dev-pipeline/review-lean` row and §5
  carry the localisation, and every stale "127 lines" claim is re-labelled as the pinned measured
  surface. No reader is left with a line count that matches no version of the file.
- **AC-8** — `plugins/dev-pipeline/skills/review-lean/SKILL.md` is not edited.

## Out of scope

- **Executing the cut.** This ticket localises it; the deletion is a successor of #671.
- **Re-measuring C2 at the current head.** The 0.80 is not refreshed; the drift is recorded, not
  repaired.
- **P10 independence** — a lane property, not prose. A `cut-to-delta` here addresses prose and says
  nothing about the separate-session boundary.
- **Editing `docs/skill-ablation-pre-registration.md`** — frozen by the ticket.
- **Editing `docs/skill-ablation-addendum.md` §C** — the registration this slice is graded by.
  Correcting the stale head line count at :532 is the one write (D-2); no threshold, unit, replicate
  count or classification is touched.
- **`docs/plans/skill-ablation/c2-review/scoring.tsv`** — keyed per blocker; the ablation result is
  keyed per unit and lands in its own sibling (D-4).

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Which comparator makes AC-6's cut list binding, given AC-4 mandates both and they disagree on C2-a (`scoring.tsv` records bare MISS, `/code-review` HIT) | Cut list carries a disposition column per comparator. The **delta-vs-bare** column binds any successor deletion — §2 states the 0.80 is a bare-vs-kit recall and §4 titles it that way, so bare is the comparator the frozen `cut-to-delta` verdict was taken against. The delta-vs-`/code-review` column is recorded beside it with an explicit statement that on this sample the named comparator shows no delta at all, and that the column licenses no cut on one sample. Operationally identical to an outside-under-both rule, since no unit is inside `/code-review`'s delta here | user-answered |
| D-2 | AC-7's binary — correct the stale `127 lines` to the current count, or re-label it as the pinned measured surface | Re-label. Every line-count claim becomes "127 lines at `8d5d0897`, the measured surface"; no head count is written anywhere. The same treatment is applied to the addendum's own stale "188 lines" at `docs/skill-ablation-addendum.md`:532. Grounding: §C already says the head count moves with every merge and is why the subject is pinned by commit; three artifacts already carry three different current counts — ticket 176, addendum 188, `origin/main` 191 — so a corrected count guarantees a fourth. Correcting a stale head count is not a rubric change, so the addendum's never-post-hoc rule at :33 is not engaged | user-answered |
| D-3 | Shape of the committed ablation transcripts (AC-5), given the registered schedule is 26 runs before escalation | One file per **arm**, replicates as `## r<n>` sections inside it: `ablated-control-654-review.md` plus `ablated-<unit>-654-review.md` for each of the 17 units — 18 files, flat in `docs/plans/skill-ablation/c2-review/`. Each records the realised invocation and apparatus, then every replicate's output verbatim. Matches the flat prefix-keyed family convention of both existing comparison dirs, preserves the `../../../` link depth every transcript uses, and absorbs an n=5 escalation by growing a file rather than by changing the file count. The README gains one `ablated-<unit>-<pr>-review.md` family line | user-answered |
| D-4 | Where the per-unit machine-readable result lives, given `scoring.tsv` is keyed per-blocker and the ablation result is keyed per-unit | A new sibling `docs/plans/skill-ablation/c2-review/ablation-units.tsv`, 17 rows keyed by unit, carrying unit id, line range at `8d5d0897`, registered reach, valid and indeterminate run counts, control majority, arm majority, score, and the two comparator dispositions D-1 settled. `scoring.tsv` is left untouched so the existing bare and challenger adjudications stay stable | user-answered |
| D-5 | How `review-lead` reaches the fallback control if the void condition fires — §C says "the kit arm as it actually runs", which collides with the same section's plugin-free harness and would load `review-lean` from the cache, defeating line-range ablation | Keep the registered harness verbatim and concatenate `review-lead`'s SKILL text into the prompt, the same mechanism that already supplies `review-lean`'s text. Only the prompt assembly changes. The departure from "as it actually runs" is flagged in the transcript and restated on the cut list. Falls under OR-1 | user-answered |
| D-6 | Which `127` occurrences in `docs/skill-ablation.md` are line-count claims, given AC-7's named anchors no longer resolve | Line-count claims live at `:31`, `:334`, `:338`, `:430`, `:457` and take D-2's treatment. `:202` and `:210` read "127 committed lean specs" — a corpus size, correctly 127 — and are left alone; editing them would introduce an error. AC-7's anchors `:188`, `:192`, `:275`, `:299` have drifted: `:188` and `:299` are blank lines today and `:192` / `:275` are unrelated prose, so the reconciliation is done by content, not by AC-7's line numbers | codebase-derived |
| D-7 | How AC-6's mandated unmeasured-region statement describes the lines added since the pin | As "every line added to `review-lean/SKILL.md` since `8d5d0897`" — no count. Follows D-2: the ticket's "63" is itself stale, net +49 at intake and +64 at `origin/main`, so writing it would add the fourth stale number to the very deliverable AC-6 mandates | codebase-derived |
| D-8 | Base for the build branch | `origin/main` at or after `bcedb2a1`. AC-4's second comparator exists only there — `codereview-654-review.md` and the `codereview_result` / `codereview_adjudication` columns of `scoring.tsv` landed with PR #787. The checkout's current local branch predates that merge and carries none of it | codebase-derived |
| D-9 | Harness recipe and model tier for every run | Frozen at `docs/skill-ablation-pre-registration.md`:22-28 — `claude -p --model opus --setting-sources ''` under the registered `env -u` list, `--allowedTools "Read,Grep,Glob"`. §C adds one-shot piped prompt, read-only, throwaway clone at `cfba102`, nothing committed and no gate called. Not re-decided here | codebase-derived |
| D-10 | Whether any part of the registered rubric is re-opened at build time | No. Method, the 17 units with exact line ranges, the reach classification as a registered prediction, control n=3, the void condition, the frozen C2 hit rule, the replicate schedule of 26 runs, escalation to n=5 on a split, indeterminate handling, the `no-effect` set-comparison threshold, cut-eligibility, and the non-descent of the frozen decision rule to units are all fixed at `docs/skill-ablation-addendum.md`:516-703. The build executes them; it does not re-derive them | codebase-derived |
| D-11 | Whether the cut list restates the study's registered confound | Yes, mandated by §C:613-617 — the study attributes within `review-lean`'s prose while holding `review-lead` absent in every arm including the control, so a unit that matters only by routing to `review-lead` reads as `no-effect` here. Any cut list this arm emits inherits that limitation and must say so | codebase-derived |
| D-12 | Scope boundary — what this PR must not touch | `plugins/dev-pipeline/skills/review-lean/SKILL.md` per AC-8; `docs/skill-ablation-pre-registration.md`, frozen by the ticket's Out of scope block; plugin manifest `version` fields, `CHANGELOG.md` and marketplace `metadata.version`, which `scripts/check-frozen-files.sh` rejects on a feature PR. The deletion itself is a successor of #671, not this ticket | codebase-derived |

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | The void-condition fallback harness — whether `review-lead` reaches the fallback control as concatenated prompt text or as a loaded plugin, and whether the ablation of the other 17 units survives that choice | reversible-default-and-flag |

OR-1 takes D-5's default: the registered harness is kept verbatim and `review-lead`'s SKILL text is
concatenated into the prompt, the same mechanism that already supplies `review-lean`'s. Reversible
because the region fires only if the control fails to reproduce the C2-a blocker in at least 2 of 3
runs, and reversing the default costs one re-run of the control — the transcript records the
realised invocation verbatim, so a reader can repudiate the reading rather than take it on trust.
Flagged in the PR body rather than pausing the build; paying a pause here would spend it on a branch
that may never be taken, and could only be reached after the three control runs are already spent.
