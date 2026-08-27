# second-shift #694 — the translation plan becomes an artifact the harness asserts

## Problem

`figma-faithful` step 7 emits a translation plan — the completed token table, the placement
decision, the resolved-component list, the chosen analog, the file list — and calls it "the
cheapest place to catch a wrong token row". Nothing on the lean lane ever reads it. It is prose a
build session emits and then implements against, so every check written to grade it reaches
nothing, and two such checks currently sit dead:

- **Per-node sizing** is required unconditionally by `figma-faithful/SKILL.md` step 3b, but the
  plan reviewer's only sizing finding is scoped to a "repeating / wrapping group". A screen of
  individually sized controls is not one, so a plan carrying no control dimensions at all draws
  zero findings — and the design-blind code reviewer then has no recorded number to compare
  against either.
- **Component-resolution suitability** has no owner. The plan reviewer defers component identity
  to `figma-faithful-spec-reviewer`, which checks presence rather than suitability — and which
  returns `N/A` on any input lacking Copy Index / Components / Screens sections, i.e. on every
  lean-lane spec. Both deferred checks land nowhere.

## The contract (OR-1, as the operator decided it)

Settled on the issue, not by this session
(<https://github.com/manoldonev/second-shift/issues/694#issuecomment-5440267225>):

| #   | Decision            | Answer                                                                                              |
| --- | ------------------- | --------------------------------------------------------------------------------------------------- |
| a   | Path                | `<plansDir>/<key>-lean-plan.md`, mirroring `-lean-renders.md`                                        |
| b   | Required sections   | resolved-component list with a `why this component` cell; dimension table with a `dimensions` cell. An empty cell is the finding |
| c   | Asserting milestone | milestone 3, **before** the render pass — a wrong token row reds before anything is rendered          |
| d   | Arming predicate    | the spec's `## Design` section, same predicate as the render lane                                    |
| e   | Disarm state-lock   | yes — the same `design_was_armed` lock, so a failed plan is not disarmed away on re-entry             |
| f   | Patch binding       | a `planned_from` patch-id header, same shape as `rendered_from`                                      |
| g   | Re-entry            | re-assert on every milestone-3 run; a stale patch id reds                                            |

OR-2 was decided **figma-only**: the non-figma `design-faithful` family has no translation-plan
step and no plan-reviewer agent, so mirroring there is net-new surface rather than an edit and is
out of this diff.

## Acceptance Criteria

- **AC-1** — an armed spec's translation plan is a committed artifact at
  `<plansDir>/<key>-lean-plan.md`, carrying a `planned_from:` header the gate stamps with this
  branch's plan patch identity, and milestone 3 refuses — **before** the render pass — when the
  artifact is absent, when either required table is missing/empty-celled, or when the recorded
  binding is stale. The refusal rides the same arming predicate and the same `design_was_armed`
  state lock as the render lane.
- **AC-2** — WHEN an armed spec's plan artifact records no dimension row for a control-bearing
  screen, THEN the plan review reports it. The check is inverted from the shipped one: it fires on
  the **silent** case (no dimension rows at all), not only on the loud one (a repeating/wrapping
  group).
- **AC-3** — WHEN a plan resolves a component whose rendered affordances exceed what the frame
  draws, with no note that the extra affordance is intended, THEN the plan review reports it.
- **AC-4** — every deferral in the `figma-faithful` reviewer family names an owner that can
  actually run on the lean lane, or says plainly that none can. No deferral may name a target that
  returns `N/A` on every lean-lane input, and none may name a gate that does not exist.
- **AC-5** — `figma-faithful/SKILL.md` step 7 describes the artifact (path, required tables, the
  `planned_from` header) and the milestone that asserts it, replacing the placeholder text left by
  the predecessor (#693) that says the lane asserts no such artifact.
- **AC-6** — `lean-gate-selftest.sh` covers AC-1 — arming, absence, each malformed shape, the
  stamp-and-commit cycle, staleness, and the disarm lock — and
  `scenario-liveness-selftest.sh` carries the composed leg, per CLAUDE.md's rule that a new gate
  contract extends the liveness scenario.
- **AC-7** — `docs/live-render.md` and `plugins/dev-pipeline/skills/build-lean/SKILL.md` describe
  the plan gate where they describe the render receipt, so neither reads as the complete armed
  contract while omitting half of it.

## Decision Ledger

| D-n | Decision | Resolution | Provenance |
| --- | -------- | ---------- | ---------- |
| D-1 | The plan artifact's path | `<plansDir>/<key>-lean-plan.md` | user-answered |
| D-2 | What the gate mechanically requires of the body | A table declaring a `why this component` column and a table declaring a `dimensions` column; at least one data row each; every declared cell non-empty and no short rows | user-answered |
| D-3 | Which milestone asserts it, and in what order | Milestone 3, before the render pass | user-answered |
| D-4 | Arming predicate | The spec's `## Design` section ANDed with config `design.provider` — the render lane's own `design_state()` | user-answered |
| D-5 | Does the disarm state-lock | Yes — the same `\| milestone-3 \| armed \|` record; the plan pass now writes it, since it runs first | user-answered |
| D-6 | Patch binding | A `planned_from:` header, stamped by the gate, over a plan patch identity | user-answered |
| D-7 | Re-entry behavior | Re-asserted on every milestone-3 run; a stale id reds | user-answered |
| D-8 | Mirror into the non-figma `design-faithful` family | No — figma-only; net-new surface belongs in its own ticket | user-answered |
| D-9 | Which patch identity binds the plan | Its own `plan_patch_id()` — the branch diff less the verdict record, the render receipt AND the plan itself. Reusing `render_patch_id()` cannot converge: the plan sits inside it, so committing the plan would restale the stamp that commit carried | codebase-derived |
| D-10 | Whether `render_patch_id()` also excludes the plan | No. It is held in lockstep with `scripts/check-lean-chain.sh`'s own render-id computation, and a consumer pinning an older boundary ref would red every armed PR. The ordering in D-3 makes the exclusion unnecessary: the plan is committed before the render pass ever computes an id | codebase-derived |
| D-11 | Fix-budget class of the plan reds | Absence, a missing header line, and a stale stamp are `block_milestone` (the absent budget) — each names something the run was going to do anyway, which is #642's own criterion. A malformed table is `fail_milestone`: that is a fix that did not work | codebase-derived |
| D-12 | Whether the merge boundary gets a plan arm | No. The boundary re-asserts the **verdict** chain, and `fidelity: pass` binds to the render receipt, not to the plan. A new boundary arm also owes a capability stamp, an inert path and a pre-stamp fixture (docs/testing.md) — surface no AC here asks for | codebase-derived |
| D-13 | Whether the gate can author the plan body | No — it is design reasoning, not derivable state. The gate stamps only the `planned_from:` line and refuses when that line is absent, so it never invents structure inside an author-owned artifact | codebase-derived |

## Explicitly out of scope

- Any change to `design-faithful` / `design-faithful-reviewer` / `design-faithful-spec` (D-8).
- A merge-boundary arm for the plan artifact (D-12).
- Diffing a plan against the design. Nothing in this repo resolves a Figma frame; the plan gate is
  a completeness-and-binding check, and the reviewer checks are questions the plan must answer.
  Neither verifies a recorded value is the value the design shows.

## Stated limit

A `planned_from` stamp the gate writes is **tamper-evidence, not proof the plan was re-read**. On
a stale binding the gate re-stamps and reds; nothing can verify that the author reconsidered the
token table against the code that moved. What the artifact buys is that the plan exists, is
committed, has both required tables fully populated, and is dated against a specific patch — so an
omission is visible as an empty cell rather than an absent thought, and a reviewer can see which
code the plan was current for. This is the same bargain #693 struck for the fidelity evidence
table, and it is stated here for the same reason.
