# #695 — the pixel-diff gate: decide, then stop deferring

**Issue:** https://github.com/manoldonev/second-shift/issues/695 (part of #692, predecessor #694)

## Goal

#695 exists to force one decision and record it: whether the rendered-vs-design pixel-diff gate
that four documents deferred to gets **built**, **scoped down**, or **retired**. The ticket names
the three directions and chooses none — "Undecided by design … to force the decision, not to
presume it."

## What changed between filing and build

The ticket's evidence is **stale**, and re-measuring it at `6dd9f70` is the first obligation
(the ticket anticipated this: "#694's outcome changes how much of this ticket's AC-2 is already
done").

All three line citations in the Problem section describe pre-#694 text. At head, every one of
AC-2's five named documents already states that no such gate exists and forbids deferring to one:

| AC-2 target | text at `6dd9f70` | verdict |
| --- | --- | --- |
| `figma-faithful-spec-reviewer.md:33` | "…it is not a pixel-diff gate, and no such gate exists in this repo." | already compliant |
| `figma-faithful-plan-reviewer.md:59-60`, `:64` | "It is **not** a pixel-diff — no such gate exists in this repo — so do not defer to one." / "— not a pixel-diff gate, which this repo does not have." | already compliant |
| `figma-faithful-reviewer.md:39` | "…it is not a pixel-diff gate, and no such gate exists in this repo." | already compliant |
| `figma-faithful-spec/SKILL.md:219-220` | "No pixel-diff or screenshot-diff gate exists in this repo; do not defer to one." | already compliant |
| `design-faithful/SKILL.md:59` | "There is **no pixel-diff tool in-repo — do not invent one**" | already compliant |

`git grep -i -e 'pixel-diff' -e 'pixel diff' -e 'screenshot-diff'` over `plugins/ docs/`, excluding
`docs/plans/` (the historical record), leaves exactly **one live deferral** — `docs/live-render.md:178`,
"the pixel-diff gate is still deferred". #694's own verdict record flagged it as W1 and left it.

**A second, unfiled defect in the same file.** `docs/live-render.md:5` says milestone 3 "reads the
emitted PNG, and semantically compares it against the cached design frame". The gate does neither:
it caches no design frame, and it performs no comparison — `git grep -i 'design frame' plugins/dev-pipeline/`
returns only the fidelity-evidence column header and a prose reference. Line 162 of the same file
states the opposite correctly ("Nothing here diffs a screenshot against a design frame"). This is
the ticket's own defect class in its sharpest form — a document crediting a component with
fidelity work it does not do — sitting two paragraphs from the line AC-2 requires fixing. It is
carried as AC-5 rather than folded in silently.

## Decision (AC-1)

**Direction 3 — retire the deferral. Fidelity remains attested, permanently, not pending.**

The reasoning, against each rejected direction:

**Direction 1 (build a pixel differ) is not buildable against this design side.** The comparison
would be a Figma frame export against a Playwright screenshot: different rasterizer, different
DPR, different font stack, different viewport. The tolerance model reconciling those two is either
loose enough to catch nothing or tight enough to red on a second machine, and nothing distinguishes
the two settings from inside the repo. The dependency also lands in the wrong place — this repo is
bash and markdown (no `package.json` anywhere, no image tooling), so the differ would be a
requirement imposed on every *consumer's* render harness, added to a `design.liveRender` contract
whose whole design is that the harness owns boot/auth/screenshot and the lane owns nothing that
needs installing.

**Direction 2 (measured properties) is the strongest of the three and is still not this ticket's.**
It would have caught the observed failure — a control at ~2.2× the design's width — and #701
(merged today, closing #694) just made it materially cheaper by turning the translation plan into
a committed artifact with an asserted `dimensions` table, which is a real design-side number the
lane can read. Two things stop it here:

1. **Its ground truth is one step short of the design.** The `dimensions` table records the Figma
   value *as the build agent transcribed it*, and the build agent also wrote the code. A gate
   comparing rendered-against-transcribed catches plan→code drift and is structurally blind to
   design→plan drift — which is precisely the gap all three reviewers disclaim ("if the table wrote
   down the wrong Figma value…"). It is a real check, but it is not the check the deferral promised.
2. **It is a breaking consumer-contract change, not a documentation fix.** The rendered side has
   to come from somewhere: `{out}` is a PNG, and bash cannot measure a DOM. Every consumer harness
   would have to emit a second, newly specified measurements artifact, and the `dimensions` table
   would need a per-row selector column — a schema change to a table that shipped hours ago. That
   is a program, and AC-3's single sentence ("asserted by the lane rather than reported, and
   covered by a selftest") is standing in for all of it.

Direction 2 is therefore **recommended for a follow-up ticket**, carrying the precondition #701
created. It is not filed from this lane: build-lean's tracker budget is two writes (claim, close-out),
and filing is the operator's. See "Follow-up owed" below.

**Direction 3 is honest now in a way it was not when this ticket was filed**, because #693 and
#694 raised the floor underneath it. `fidelity: pass` is no longer a one-word header: the writer
refuses an armed pass without a `## Design fidelity evidence` table — six named columns, paired
design-vs-rendered numbers per declared `RS-n`, every cell populated, a verdict citing a criterion
the patch-bound spec actually carries. That is tamper-evidence, not fidelity, and `docs/live-render.md`
already says so plainly. An attested-and-auditable posture stated as settled is strictly better
than a deferral to a gate nobody is building.

## Scope

In scope: the recorded decision; re-measurement of AC-2's five documents at head; retirement of the
one surviving live deferral; correction of the false capability claim in the same file.

Non-goals:

- Building any fidelity gate (direction 1 or 2) — this is the decision *not* to, recorded.
- Re-editing the five AC-2 documents that already comply. They are re-measured and recorded, not
  churned; a no-op edit to satisfy a diff would manufacture a diff rather than close a gap.
- A regression guard on the retired deferral. `writing-tests` is explicit — "prose in a markdown
  file → **nothing**"; grepping a literal out of markdown "asserts only that prose contains words
  — it cannot fail for a reason a reader of the diff would not already see." No lockstep anchor
  fits either: the six statements are independent prose, not two copies of one contract. AC-5 of
  #694 already covers the family by review.

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Build the gate, scope it to measured properties, or retire the deferral? | Direction 3 — retire it; fidelity remains attested, permanently, and the documents say so. Reasoning recorded above and in `docs/live-render.md`. | user-delegated |
| D-2 | Is direction 2 refuted, or deferred? | Deferred with its precondition named: #701's committed `dimensions` table is the design-side artifact it needs. Recommended for a follow-up ticket; not filed from this lane. | user-delegated |
| D-3 | Re-edit the five AC-2 documents that already satisfy the AC? | No. Re-measure at head and record the measurement; #694 satisfied them. | codebase-derived |
| D-4 | Write a guard so the deferral cannot return? | No. `writing-tests` tier map routes prose-in-markdown to "nothing", and no lockstep anchor fits six independent statements. Recorded here so the absence is a decision, not an oversight. | codebase-derived |
| D-5 | Fix `docs/live-render.md:5`'s false "the gate semantically compares" claim, found in the file AC-2 requires editing? | Yes, under its own AC-5 rather than folded into AC-4 — it is the ticket's defect class, two paragraphs away, and shipping AC-4 without it leaves the file self-contradictory. | codebase-derived |
| D-6 | Round 1 found the same false-capability claim at `docs/live-render.md:34`, which AC-6's grep passed. Widen the criterion, or just fix the line? | Both. The line is fixed, and AC-6 gains a second arm over the defect SHAPE — a capability claim, not the deferral vocabulary. Source: the round-1 verdict record `docs/plans/second-shift-695-lean-verdict.md`, finding B1(3). | codebase-derived |

## Acceptance Criteria

- **AC-1** — the decision (direction 3) is recorded with its reasoning, including why directions 1
  and 2 were rejected, in a location that outlives this run: this plan file, and operatively in
  `docs/live-render.md`.
- **AC-2** — each of the five documents the issue names is re-measured at the branch head and
  either points at a component that exists or makes no deferral claim:
  `figma-faithful-spec-reviewer.md`, `figma-faithful-plan-reviewer.md`, `figma-faithful-reviewer.md`,
  `figma-faithful-spec/SKILL.md`, `design-faithful/SKILL.md`. The measurement is recorded above.
- **AC-3** — no gate is built, so nothing is owed on "asserted by the lane rather than reported"
  and no selftest is owed. No document left in the tree promises a fidelity gate is coming.
- **AC-4** — `docs/live-render.md`'s surviving deferral ("the pixel-diff gate is still deferred")
  is retired; the file states the settled posture and its reasoning instead of pointing at an
  unbuilt component.
- **AC-5** — `docs/live-render.md`'s opening no longer credits milestone 3 with semantically
  comparing the render against a cached design frame; it describes what the gate actually does
  (runs the harness, takes the PNG, hashes it into the receipt) and names the review session as
  the reader that compares.
- **AC-6** — the tree carries neither shape of this defect, checked on **both** axes. Round 1
  demonstrated that the vocabulary arm alone is not a completeness criterion (D-6):
  1. **Deferral vocabulary.**
     `git grep -i -e 'pixel-diff' -e 'pixel diff' -e 'screenshot-diff' -e 'screenshot diff'` over
     `plugins/` and `docs/`, excluding `docs/plans/`, returns no text deferring to, or promising, a
     gate that does not exist.
  2. **False capability claim** — the shape the first arm is blind to: a sentence crediting the
     gate with comparison never has to name a pixel differ. No hit of

     ```
     git grep -n -i -E '(gate|milestone[ -]?3|lane).{0,80}(compar|verif(y|ies).{0,20}(against|design)|check.{0,20}against the design)|(compar|check|verif).{0,40}(design frame|handoff frame|figma frame|mock)' -- docs/ plugins/ schema/ ':!docs/plans/'
     ```

     credits the gate, the lane, or milestone 3 with comparing a render against the design.
     `docs/plans/` is excluded on the same ground as arm 1 — it is the historical record, and
     this run's own verdict record quotes the defect verbatim in order to report it. The
     grep is deliberately broader than the claim it polices, so its output is a triage queue, not
     a verdict: a hit that **denies** the capability, or that attributes the comparison to the
     `/dev-pipeline:review-lean` session, is the compliant form.

     Triage at the fix-round head — **12 hits, none a live claim**, in four classes:
     *hypothetical* (`docs/live-render.md:197`, "a pixel differ **would** compare");
     *denial* (`lean-gate.sh:3539`, `:3552`);
     *attributed to the sighted reader* (`lean-gate.sh:4689`, `figma-faithful/SKILL.md:243` — the
     design engine comparing its own render, expressly "what every static gate misses");
     and *a different subject entirely* — the scheduler's progress-token comparison
     (`orchestrate-lean.sh:48-49`, `:362`, `:1035`, `orchestrate-lean-selftest.sh:976`,
     `lean-gate.sh:2130`), `pipeline-manifesto.md:72`'s P4 register, and
     `stall-probe.mjs:285`'s "comparable across arms".

## Follow-up owed (not filed from this lane)

A ticket for direction 2, scoped as a program rather than a doc change:

> **Measured-property fidelity assertion over the translation plan's `dimensions` table.** #701
> made the design-side numbers a committed, gate-asserted artifact. Compare them against measured
> rendered properties per declared `RS-n` and assert the comparison in the lane. Requires: a
> selector (or equivalent node binding) column on the `dimensions` table; a second emitted artifact
> in the `design.liveRender` command contract (breaking for every consumer harness); a tolerance
> model for responsive/subpixel variance. Known limitation to state in the ticket: it verifies
> plan→code, never design→plan, so it narrows the fidelity gap rather than closing it.

## Verification

```bash
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
SKIP_STRESS=1 bash tools/run-selftests.sh --full --exclude tools/install-topology-selftest.sh
```

This change is documentation only — no shell, no JSON, no gate behavior. The sweep is run because
the recipe of record says to, not because a suite is expected to move.
