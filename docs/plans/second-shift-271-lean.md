# Lean spec — #271: pipeline-retro's retro-scorer dispatch has no emit deadline or retry

## Context

`pipeline-retro` Step 2 dispatches exactly one `retro-scorer` agent via the Task/Agent tool,
with no emit deadline, no retry, and no darkness detection. The emit-deadline machinery that
closed #175/#183 (`code-review.mjs`'s progressive-emit + `check-emit-deadline.sh`, the
`structured-emitter` rung-2 fallback) protects the **Workflow** fan-out only; Step 2's
Task-tool dispatch carries none of it. When the agent dies without emitting, the retro loses
its only independent voice and nothing in the skill notices.

Measured twice: run `2026-07-30T000042Z-second-shift-0158f2fe` (#244, PR #270) — the
`retro-scorer` dispatch returned no output after 78k tokens / 26 tool calls / 196s, and a
`SendMessage` resume to the same agent id recovered the full verdict in 14s / 0 tool calls,
proving the analysis was sitting in the transcript, only its emission was lost. The `#243`
retro datapoint comment on this issue reproduced the same shape independently (20 tool calls,
dark, resumed successfully) — the recovery is not a one-off.

The issue's own proposed fix (cheapest rung on the enforcement ladder in
`pipeline-retro/SKILL.md` Step 5: neither a statectl precondition nor a bash helper nor a
`.mjs` sequencer fit a single ad-hoc Task-tool dispatch) is a **skill-file edit to Step 2**:
name the empty return as a failure mode, resume via `SendMessage` before anything else, and
only if that also comes back empty, say so explicitly in the report rather than leaving a
blank column or silently reusing the self-score.

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Recovery mechanism | Resume the same `retro-scorer` agent (`SendMessage`-equivalent) with a nudge to emit from evidence already in its transcript, no further tool calls — not a fresh redispatch, which would discard the 78k tokens of work already done. | issue body, confirmed by both the #244 measurement and the #243 datapoint comment |
| D-2 | Generalize the resume pattern beyond pipeline-retro? | No — out of scope here. The issue raises this as an open question for "whoever picks this up"; deciding it now rather than leaving it implicit: other Agent-tool dispatches in the pipeline may have the same exposure, but auditing and fixing them is a separate, broader change this issue does not fund. | issue body open question 1, resolved explicitly per this spec |
| D-3 | Move `retro-scorer` onto the Workflow substrate? | No. That would buy the existing emit-deadline stack but adds StructuredOutput-staller surface for what is structurally a single dispatch — the issue itself calls this "likely not worth it." The resume fix already closes the gap at lower cost. | issue body open question 2, resolved explicitly per this spec |
| D-4 | Fallback when the resume also returns empty | Step 6's report records the independent score as `DARK — no output after resume` per criterion (not a blank cell), and Step 2 explicitly forbids substituting the self-score. A dark-after-resume dispatch is itself logged as an environment-friction item for Step 4/5 routing. | codebase-derived, from the issue's stated worry ("a less careful run would... quietly reuse the self-score") |

## Acceptance Criteria

- AC-1: `plugins/dev-pipeline/skills/pipeline-retro/SKILL.md` Step 2 names an empty
  `retro-scorer` return (no text emitted, whether from a silent completion or a `maxTurns`
  cutoff) as a failure mode, and instructs resuming the *same* agent (its transcript, not a
  fresh dispatch) with an instruction to emit its verdict from evidence already gathered, no
  further tool calls — before taking any other action.
- AC-2: Step 2 instructs that if the resumed dispatch also returns empty, the run must not
  fall back to the self-score and must not silently proceed to Step 6 as if scored. Step 6's
  report template (or the prose immediately above it) is updated so the score-comparison
  table records `DARK — no output after resume` in the Independent column for every criterion
  in that case, instead of a blank cell.
- AC-3: A dark-after-resume `retro-scorer` dispatch is called out as its own Step 4
  environment-friction item (not silently absorbed into the score-comparison table alone), so
  Step 5 routes it like any other friction item.
- AC-4: Step 2 states explicitly, in one or two sentences, that (a) this resume pattern is
  scoped to this dispatch and is not being generalized to other Agent-tool dispatches in the
  pipeline (D-2), and (b) `retro-scorer` is deliberately staying off the Workflow substrate
  (D-3) — so both of the issue's open questions are answered in the artifact, not left
  implicit.
- AC-5: Documentation-only change — no selftest pins `pipeline-retro` Step 2 prose or
  `retro-scorer` dispatch behavior (confirmed: no `-selftest.sh` under `plugins/` references
  `retro-scorer`, and `e2e-replay-selftest.sh`'s one `pipeline-retro` hit is an unrelated
  comment). shellcheck, jq, and the full `*-selftest.sh` sweep stay green — this AC guards
  against a regression introduced elsewhere, not new coverage for this edit.

## Out of scope

- Auditing or fixing other Agent-tool dispatches in the pipeline for the same dark-return
  exposure (D-2) — a broader change, not funded by this issue.
- Moving `retro-scorer` onto the Workflow substrate (D-3).
- Changing `eval-criteria.md` or the retro-scorer agent's own frontmatter/prompt — this is a
  dispatch-protocol fix in the calling skill, not a scoring-rubric change.
