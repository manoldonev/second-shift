# #710 — the translation plan is asserted for shape and graded by nobody

Slice 3 of 4 of #705. Predecessor #709 (merged). Successor #711.

#701 made the translation plan an artifact milestone 3 asserts — `why this component` and
`dimensions` cells non-empty. Non-empty is not right: no agent grades the content, and
`figma-faithful-plan-reviewer` is dispatched by nothing on this lane. The gate cannot run an
agent, so this slice takes the verdict record's shape: **the build session dispatches the plan
reviewer, and the gate asserts the committed OUTPUT.**

## Acceptance criteria

- **AC-1**: on an armed run, `bash G 3` with no plan-review record reds before any render command
  runs — the render stub is never invoked.
- **AC-2**: a record whose `reviewed_plan_from` differs from the current plan patch id reds as
  stale; committing the record does not itself stale it.
- **AC-3**: `verdict: block` reds milestone 3 on its budget, quoting the record's first finding;
  `pass` and `fix-and-go` proceed to render.
- **AC-4**: `bash G plan-review` stamps `reviewed_plan_from` from the checkout and refuses a
  verdict outside the enum.
- **AC-5**: no file in `plugins/design-toolkit` still states that no autonomous lane dispatches
  the plan reviewer (`grep -rn 'autonomous lane' plugins/design-toolkit` is empty or names the
  new contract).
- **AC-6**: catalog rows for each new red; the liveness scenario's armed chain is extended with
  the record; `feat(dev-pipeline):` commit verb and a `Changelog:` trailer.
- **AC-7**: every refusal site this slice adds to `lean-gate.sh` carries a row in
  `scripts/gate-buckets.tsv` — `scripts/check-gate-buckets.sh` is green.
- **AC-8**: `build-lean/SKILL.md` step 6 states the dispatch-and-record obligation on an armed
  run, and `docs/live-render.md`'s plan section states the same lane contract rather than the
  retired operator-only one.
- **AC-9**: the OR-1 follow-up (plan-stage review for the `claude-design` family) is filed as a
  GitHub issue and referenced from the code that declines the mandate.

## The artifact

`<plansDir>/<key>-lean-plan-review.md`. The suffix must not end in `-lean.md` — the merge
boundary's artifact arm takes the FIRST path ending there and calls it the spec, the same
reasoning that gave `-lean-plan.md` and `-lean-renders.md` their own suffixes.

Header keys, all written by `bash G plan-review` and never by hand:

```
reviewed_plan_from: <the plan patch id at write time>
verdict: pass | fix-and-go | block
reviewer: figma-faithful-plan-reviewer
model: <the model the dispatch ran on>
```

`reviewer:` is the BARE agent name, not the qualified `design-toolkit:` form: `record_key`'s
charset stops at the first character outside `[A-Za-z0-9._-]`, so a qualified value would
truncate to `design-toolkit` and the family check would compare against a plugin prefix.

Body: the reviewer's findings verbatim, from `--summary-file`.

## Where the assertion runs

At the END of `design_plan_gate` — after the plan-completeness assertion and after the plan's own
`planned_from` binding is confirmed current, and before `cmd_3_render` reaches the harness config
or a single render command.

D-32 says "after the approved-round short-circuit (`:4016-4032`)". That citation resolves, at the
sha the ticket was filed against (`864e8c1`), to `plan_stamp` and `design_plan_gate`'s own header
comment — not to the render pass's approved-round short-circuit. The purpose the row states is
what binds: *an approved round does not re-plan.* This placement satisfies it, because
`plan_patch_id` excludes the verdict record, the render receipt, the plan and now the plan-review
record, so on an approved round the plan and its review are both still current and both pass.

## Budget classes

| Arm | Primitive |
| --- | --- |
| record missing | `block_milestone` |
| `reviewed_plan_from` stale | `block_milestone` |
| malformed header (missing key, verdict outside the enum, wrong `reviewer`, empty `model`) | `fail_milestone` |
| `verdict: block` | `block_milestone` |

The ticket's guess-point 7 names `block_milestone` for the `block` arm and glosses it "(spends an
attempt — the plan is wrong)". The two halves disagree: `block_milestone` walks the ABSENT budget
and charges no fix attempt. The named PRIMITIVE wins, and it is also what D-33 of the #705 receipt
records without the gloss.

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-3 | How does the plan get reviewed when the gate cannot run an agent? | Same shape as the verdict record: build-lean mandates the dispatch on an armed run and the gate asserts the committed OUTPUT at `<plansDir>/<key>-lean-plan-review.md`; missing, stale, or `block` reds milestone 3 before the render pass. | user-delegated |
| D-27 | No `design-faithful-plan-reviewer` exists. | This slice mandates the record for the figma family only; claude-design plan review is parked under OR-1 and filed as a follow-up at this build. | deferred |
| D-28 | `reviewer:` must match the family. | Yes, host-derived — from `design_family`, the same derivation the fidelity reviewer's mandate uses. | user-delegated |
| D-29 | `model:` provenance. | `--model`, validated non-empty only. | codebase-derived |
| D-30 | `fix-and-go` with no fix landed. | Accepted and proceeds: a real fix moves nothing the record binds to, so the finding list ships into the PR where review-lean reads it. | user-delegated |
| D-31 | Symmetric `render_patch_id` exclusion for the plan-review record. | No — the record is committed BEFORE the render pass, the same argument the plan itself makes; a later record commit means a re-plan, and restaling the render is then correct. | codebase-derived |
| D-32 | Order vs the approved-round short-circuit. | End of `design_plan_gate`; see "Where the assertion runs" for why the cited range does not name the render short-circuit. | user-delegated |
| D-33 | Budget class per plan-review arm. | missing / stale / `block` → `block_milestone`; malformed → `fail_milestone`. | codebase-derived |
| D-34 | `plan-review` subcommand shape. | `bash G plan-review <issue> --verdict <v> --summary-file <p> --model <m>`, flag style like `verdict`; a second call overwrites. `--summary-file` is REQUIRED, unlike `verdict`'s optional one — a `block` the gate must quote needs a body to quote from. | user-delegated |
| D-35 | Build-side toolkit-absent on an armed figma run. | `envfail`, no attempt spent — `resolve_plan_reviewer_agent()` walks the same `resolve_sibling` ladder `resolve_ledger_lint()` already uses, so an absent design-toolkit names the missing agent instead of redding on a dispatch the checkout cannot make. It answers "on disk", not "enabled in this session"; the absent direction is the one worth acting on. | codebase-derived |

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | Plan-stage review for the `claude-design` family — no `design-faithful-plan-reviewer` agent exists, so an armed claude-design run is unreviewed at the plan stage. Filed as #739 and cited from `design_family_plan_reviewer()` | reversible-default-and-flag |
