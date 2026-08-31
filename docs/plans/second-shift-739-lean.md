# #739 — an armed claude-design run has no plan-stage reviewer

Follow-up to #710 (merged), per OR-1 of the #705 intake receipt.

#710 made the translation plan a GRADED artifact: milestone 3 refuses to render until the
provider's plan reviewer's verdict is committed at `<plansDir>/<key>-lean-plan-review.md`. The
mandate is **figma-only**, and the reason is that there was nothing else to mandate —
`design_family_plan_reviewer()` maps `figma` → `figma-faithful-plan-reviewer` and returns
non-zero for every other family, because no claude-design counterpart exists.

So an armed run whose `## Design` section hands off to a `claude.ai/design` surface reaches the
render pass with its translation plan asserted for shape and read by nobody. This slice builds the
missing reader and arms the family. **It also closes the producer side**: `design_plan_gate`
demands the plan on every armed run, and only `figma-faithful` step 7 says how to write one — a
reviewer grading an artifact improvised against a gate error string is not review (D-1).

## Acceptance criteria

- **AC-1**: `plugins/design-toolkit/agents/design-faithful-plan-reviewer.md` exists, carrying the
  artifact-stage frontmatter shape (`model: opus`, `effort: high`, `tools: Read, Grep, Glob,
  Bash`, `skills: reviewer-baseline`, no `maxTurns`) and a checklist whose sections are exactly
  the D-2 set — component-resolution suitability, per-node dimensions, analog suitability,
  state→code wiring, file coverage, Decision Ledger — with **no** token-arithmetic section.
- **AC-2**: `design_family_plan_reviewer()` in `lean-gate.sh` resolves `claude-design` to
  `design-faithful-plan-reviewer`. On an armed claude-design run with no plan-review record,
  `bash G 3` REDS before any render command runs, naming
  `design-toolkit:design-faithful-plan-reviewer`, and spends no fix attempt.
- **AC-3**: `plugins/design-toolkit/skills/design-faithful/SKILL.md` carries a
  pre-implementation plan step that mandates the artifact at `<plansDir>/<key>-lean-plan.md` with
  the two gate-asserted tables (`why this component`, `dimensions`), the chosen analog, the file
  list and a placement decision, and states the dispatch-and-record obligation on the lean lane.
  It mandates no handoff-CSS→token-role map table (D-3).
- **AC-4**: the (dpr7) case in `lean-gate-selftest.sh` is inverted — it drives an armed
  claude-design host and asserts the refusal — and `tools/mutation-catalog.tsv`'s
  `lean-gate-plan-review-family-universal` row is re-anchored to the surviving `*)` arm (its
  mutant deletes `claude-design)` so the family falls through and is declined again). The mutant
  is probed and killed by the inverted (dpr7).
- **AC-5**: the stale-gap prose is gone, on a decidable oracle. Both of
  `git grep -n 'DOES NOT EXIST' -- ':!docs/plans/'` and
  `git grep -n 'OR-1 of' -- ':!docs/plans/'` return **nothing** — those are the two strings by
  which the tree today asserts that claude-design plan review is an unfiled open gap. The
  `ships no plan-stage reviewer` refusals survive verbatim and describe the unreachable `*)`
  fall-through only.
- **AC-6**: `plugins/design-toolkit/evals/design-faithful-plan-reviewer-eval/` ships the
  instrument — committed flat fixtures with `.expected.json` siblings including one clean
  control, `rubric.py`, `run.sh` passing the namespaced agent name, `README.md`, `changelog.md`,
  and a `CLOSEOUT-BASELINE.md` recording the baseline as **OWED** with the reason no reading
  exists. `bash scripts/check-eval-model-identity.sh` stays green.
- **AC-7**: `build-lean/SKILL.md` step 6 no longer carries the
  `design-toolkit:<provider>-faithful-plan-reviewer` dispatch template — which expands to a name
  that does not exist for claude-design — and points at the gate's own refusal, which prints the
  exact agent (D-9).
- **AC-8**: `docs/extension-points.md`'s design-tokens reader row names the new agent, and
  `plugins/design-toolkit/evals/README.md` describes four eval directories rather than "three,
  one per static Figma reviewer".
- **AC-9**: `bash tools/prose-blockers.sh check` is green — every blocking construct the new
  agent and the new skill step introduce carries a `docs/prose-blocker-triage.tsv` row.
- **AC-10**: `bash scripts/check-gate-buckets.sh`, `bash scripts/check-lockstep-pairs.sh` and
  `bash plugins/review-toolkit/scripts/check-reviewer-references.sh` are green; the commit takes
  a `feat(design-toolkit):` verb and a `Changelog:` trailer.

## The arm

One line, and every other arm of the gate is already family-agnostic:

```sh
design_family_plan_reviewer() { # design_family_plan_reviewer <family>
  case "${1:-}" in
    figma)         printf 'figma-faithful-plan-reviewer' ;;
    claude-design) printf 'design-faithful-plan-reviewer' ;;
    *)             return 1 ;;
  esac
}
```

The missing/stale/malformed/`block` refusals, the writer (`cmd_plan_review`), and the record
schema all interpolate `$rev` and need no change. The record's `reviewer:` key stays BARE for the
reason #710 recorded: `header_key`'s charset stops at the first character outside
`[A-Za-z0-9._-]`, so a `design-toolkit:`-qualified value would truncate to `design-toolkit`.

## What the `*)` arm becomes

Unreachable, and kept anyway as fail-closed defense (D-5). `design_state` refuses an armed spec
that classifies to neither family, and `cmd_3_render` reds on that `error:*` before
`design_plan_gate` runs — so no third family reaches this function. It carries a comment saying
so rather than a catalog row asserting a kill nothing can produce.

`tools/mutation-catalog.tsv`'s `lean-gate-plan-review-family-universal` row moves onto the arm
that IS reachable: deleting `claude-design)` makes an armed claude-design run fall through to
`*)` and be declined again — the exact regression this slice exists to prevent. Its killer is the
inverted (dpr7), and (dpr1) cannot be that killer, because (dpr1) drives a figma host.

## Scope boundaries

- **The gate's assertion set does not widen** (OR-2). `planned_from:` plus the two named columns
  is #710's contract for BOTH families. The skill step mandates more than the gate asserts, and
  D-10 is what makes that safe: the reviewer reviews what is there and NAMES the checks that had
  no input, so a missing analog is visible in the review rather than silently unchecked.
- **The two families' plan steps are not lockstep.** The claude-design contract is deliberately
  narrower than figma's — a claude-design handoff carries CSS custom properties, not a
  `Figma value | Figma token | Repo output` table, so a token-arithmetic section would have no
  columns to read.
- **`scenario-liveness-selftest.sh` is not extended** (D-8). The composed verdict path is
  unchanged; only which agent name the family resolves to moves, and that is an existing gate
  contract widening, not a new one.
- **`docs/plans/second-shift-710-lean*.md` are not edited** (D-13). They are the committed spec
  and verdict record of a closed run — history, not documentation of current behavior.
- **The eval baseline is not measured** (D-14, OR-1). `claude -p --agent` resolves a plugin agent
  only from the INSTALLED cache, so a brand-new agent exits 1 in under a second pre-release and
  every fixture scores 0 — a reading that would read as an agent failure rather than the
  environment one it is.

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Does this slice close the PRODUCER side, or only the reviewer? | Yes — add a plan step to `plugins/design-toolkit/skills/design-faithful/SKILL.md`. `design_plan_gate` (lean-gate.sh:4181) demands the plan on every armed run, but only `figma-faithful` step 7 says how to write one; without a claude-design step the new reviewer grades an artifact improvised against a gate error string. | user-answered |
| D-2 | `design-faithful-plan-reviewer`'s checklist scope | Gate-guaranteed input only: component-resolution suitability (`why this component`), per-node `dimensions`, analog suitability, state→code wiring against the spec's `RS-n` rows, file coverage, Decision Ledger check. NO token-arithmetic section — claude-design handoffs carry CSS custom properties, not `Figma value \| Figma token \| Repo output` columns, so that section would have no columns to read. | user-answered |
| D-3 | What the new `design-faithful` plan step mandates | Only what a reader exists for: the two gate-asserted tables (`why this component`, `dimensions`), plus the chosen analog, the file list, and a placement decision — each mapping to a D-2 check. No handoff-CSS→token-role map table: a mandated element with no reader is the shape this slice opposes. | user-answered |
| D-4 | New agent's frontmatter tier | `model: opus`, `effort: high`, no `maxTurns`, `tools: Read, Grep, Glob, Bash`, `skills: reviewer-baseline` — the artifact-stage shape both `figma-faithful-plan-reviewer` and `figma-faithful-spec-reviewer` carry. Diff-stage reviewers (`design-faithful-reviewer`, `figma-faithful-reviewer`) are the sonnet + `maxTurns: 15` + `bypassPermissions` shape; this agent is not one. | codebase-derived |
| D-5 | Fate of `design_family_plan_reviewer`'s `*) return 1` arm and its catalog row | Keep the arm as fail-closed defense, unreachable and un-rowed, with a comment stating why (`design_state` lean-gate.sh:3442 refuses an armed spec classifying to neither family, and `cmd_3_render`:4306 reds on that `error:*` before `design_plan_gate` runs). RE-ANCHOR `tools/mutation-catalog.tsv:140` (`lean-gate-plan-review-family-universal`) to the NEW arm — delete `claude-design)` so the family falls through and is declined again — killed by the inverted (dpr7). The catalog keeps a row on the function, on the arm that is actually reachable. | user-answered |
| D-6 | Shape of the (dpr7) inversion | (dpr7) becomes: an armed claude-design run with no plan-review record REDS before any render, naming `design-toolkit:design-faithful-plan-reviewer`. It is the killer for the re-anchored row 140 — its value is proving the family arm RESOLVES, which (dpr1) cannot, since (dpr1) drives a figma host. No separate declined-mandate case survives; ticket item 3's "keep a case for a family that still has no reviewer" is not satisfiable end-to-end, per D-5's reachability finding. | user-answered |
| D-7 | Eval fixture set (ticket item 4) | Ship the instrument now — `plugins/design-toolkit/evals/design-faithful-plan-reviewer-eval/` with fixtures, `rubric.py`, `run.sh`, `README.md`, modeled on `figma-faithful-plan-reviewer-eval/`. `CLOSEOUT-BASELINE.md` is written as OWED, not measured. See D-14. | user-answered |
| D-8 | Extend `scenario-liveness-selftest.sh` with a claude-design arm? | No. The composed verdict path is unchanged — only which agent name the family resolves to — and `writing-tests` binds a NEW gate contract, not the widening of an existing one. The inverted (dpr7) covers the new arm. Recorded so a reviewer sees this was decided, not missed. | user-answered |
| D-9 | Agent name, and `build-lean/SKILL.md`'s dispatch template | Name it `design-faithful-plan-reviewer` — no provider prefix, matching all three siblings (`design-faithful`, `design-faithful-spec`, `design-faithful-reviewer`). Step 6's `design-toolkit:<provider>-faithful-plan-reviewer` template is therefore WRONG for claude-design (it expands to `claude-design-faithful-plan-reviewer`) and must be replaced with a pointer to the gate's own refusal, which prints the exact agent. Harmless today because the family declines; a live mis-dispatch once the mandate arms. | user-answered |
| D-10 | The new agent's recognizer / N/A discipline | Mirror the sibling's rule: recognize the lean-lane artifact at `<plansDir>/<key>-lean-plan.md` by its `planned_from:` header and its two tables; on a plan missing the analog or file list, review what IS there and name which checks had no input. Never return N/A on an artifact the gate names you as the reader of — that is the dark-agent failure #692 measured on `figma-faithful-spec-reviewer`. | user-answered |
| D-11 | Does the new agent owe an emit-deadline stanza? | No. `check-emit-deadline.sh` enrolls only on a DEMONSTRATED death, never prophylactically, and its unenrolled sibling `figma-faithful-plan-reviewer` ships with no `maxTurns` and no deadline stanza. | codebase-derived |
| D-12 | The stale-prose correction set forced by the arm | Six live sites, enumerated so none is missed: `lean-gate.sh:3213` (the "ONE FAMILY, not two … DOES NOT EXIST" comment), `lean-gate.sh:4115` (the `say` declining the mandate), `lean-gate.sh:4251` (`cmd_plan_review`'s envfail naming OR-1 as unfiled), `lean-gate.sh:4186` (`design_plan_gate`'s absent-plan refusal, which says "Emit the figma-faithful step-7 plan" to a claude-design run — now family-correct per D-1), `plugins/design-toolkit/evals/README.md` ("Three eval directories, one per static Figma reviewer" + its table), and `docs/extension-points.md:20` (the design-tokens reader list). | codebase-derived |
| D-13 | Are the `docs/plans/second-shift-710-lean*.md` records edited? | No. They are the committed spec and verdict record of a closed run — immutable history, not documentation of current behavior. Their prose describing the gap is correct as of that run. | codebase-derived |
| D-14 | The eval baseline reading | Deferred. Owner: operator, after the release that ships `design-faithful-plan-reviewer` into the plugin cache. `claude -p --agent` resolves a plugin agent only from the INSTALLED cache, so a brand-new agent exits 1 in under a second pre-release and every fixture scores 0 — a reading that would read as an agent failure rather than the environment one it is. Falls under OR-1. | deferred |
ledger-carry-forward: projected 14 row(s) from /Users/mdonev/github/second-shift/.claude/pipeline-state/739-ledger.md

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | The eval baseline reading for `design-faithful-plan-reviewer` (D-14) | reversible-default-and-flag |
| OR-2 | Whether the gate should also ASSERT the analog / file list / placement decision that D-3 makes the skill mandate | reversible-default-and-flag |

**OR-1** — the default this build takes is to ship `CLOSEOUT-BASELINE.md` marked OWED, with the
provenance block stating why no reading exists, and to attempt no measurement. Reversing it is
cheap: the operator runs `run.sh` after the release that ships the agent into the plugin cache and
commits the numbers into the same file. Nothing downstream binds to the absent number.

**OR-2** — the default is NO gate widening, for the reason under Scope boundaries. Reversing later
costs a gate edit plus catalog re-anchoring, which is why it is flagged rather than taken.
