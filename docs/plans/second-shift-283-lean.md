# Lean spec — #283: port the emit-deadline stack to `intake-review.mjs` (+ `plan-review.mjs`)

## Context

`workflows/code-review.mjs` survives a diff-size-driven turn-budget stall via three
mechanisms: a dispatch-time `PROGRESSIVE_EMIT` preamble for its two exhaustive-class
reviewers, a per-agent wall-clock ceiling (`REVIEWER_CEILING_MS` + `withCeiling`), and —
at the AGENT-DOC level, enforced by `review-toolkit/scripts/check-emit-deadline.sh` — a
turn-numbered "write by turn N" deadline in the agent's own body. `workflows/
intake-review.mjs` has none of the three; `workflows/plan-review.mjs` has the ceiling
only. Run #273 measured the gap directly: `spec-reviewer` died twice inside
`intake-review.mjs`'s fan-out (turn-cap exhaustion, zero output), which — per
`intake-orchestrator`'s fail-closed contract — aborts the whole run and parks the issue
for a human on an infra fault unrelated to the spec.

**Correction to the issue's evidence framing.** The issue's measurement table greps the
three `.mjs` files for `PROGRESSIVE_EMIT` / `deadline` / `ceiling` token counts. Read
literally, "deadline" sounds like a workflow-level mechanism to add inside the `.mjs`
files. It is not: the emit deadline that `check-emit-deadline.sh` enforces is a
turn-numbered sentence in the **agent's own `.md` doc** (e.g. `security-reviewer.md`'s
"By turn 10 (of your 15 maximum) you MUST be writing the report"), loaded automatically
whenever that `agentType` is dispatched — it is never something a calling workflow
script can "carry" itself. `code-review.mjs`'s 3 grep hits on "deadline" are prose
comments *about* the concept, not a workflow-level construct. This spec's AC-1/AC-2
"emit deadline" work is therefore agent-doc + lint-enrollment work, not `.mjs` work.

Verified via `check-emit-deadline.sh`'s own agent inventory: `plan-reviewer.md` **already**
carries a valid turn-numbered deadline and is **already** enrolled in the lint's
`DEADLINE_AT_DEFAULT` (added for an earlier, analogous gap). `spec-reviewer.md` and
`codebase-explorer.md` carry **no** deadline and are **not** enrolled — both sit at the
15-turn default cap, which is exactly why the lint stays silent on the run #273 death: an
un-enrolled default-cap agent is nobody's jurisdiction.

Also discovered in the course of this work (noted, **not** fixed here — see Out of
scope): `spec-reviewer.md` and `codebase-explorer.md` both still carry a stale
pre-#169 sentence ("Call StructuredOutput first, as your sole output") in their own doc,
left over from before the schema-free explorer/emitter transport. `reviewer-baseline`'s
shared "Output Mode" section carries the same staleness for every reviewer, including
`security-reviewer` — which still completes fine under it, so it is evidently not the
differentiator run #273 measured. Fixing `spec-reviewer.md`'s copy is folded into AC-1
below only because this change touches that exact paragraph anyway (to insert the new
deadline sentence); `codebase-explorer.md` and `reviewer-baseline` are left untouched as
out of scope for this ticket.

## Decision Ledger (from the issue; D-5/D-6 added here)

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Root cause | `code-review.mjs` has all three mechanisms; `intake-review.mjs` has none; `plan-review.mjs` has the ceiling only. Measured by grep + corroborated by run #273's per-workflow dark-rates. | codebase-derived |
| D-2 | Scope | Both `intake-review.mjs` and `plan-review.mjs` in one change. | codebase-derived |
| D-3 | Shape | Extract shared preamble/deadline where possible; a lockstep row where not. | codebase-derived |
| D-4 | Retry semantics | The deadline/ceiling must cover the retry dispatch, not only the first attempt. | codebase-derived |
| D-5 | "Deadline" is agent-doc work | `check-emit-deadline.sh` enforces a turn-numbered sentence in the dispatched agent's own `.md`, not a construct inside the calling workflow script. `plan-reviewer.md` already has it + is already enrolled; `spec-reviewer.md` needs both added (demonstrated death, satisfies the lint's own enrollment bar: "add a name only on a DEMONSTRATED death"). `codebase-explorer.md` is left un-enrolled (no demonstrated death — the lint's enrollment bar explicitly says never prophylactically). | codebase-derived |
| D-6 | PROGRESSIVE_EMIT scope inside intake-review.mjs | Applied to `spec-reviewer` only (replaces its `BOUNDED_SPEC_GROUNDING` nudge — the observed death matches the exhaustive-enumeration failure class, not the "explore less" class). `codebase-explorer` completed cleanly in #273 (67s/12 tool calls) and gets no prompt-level nudge change, but is still covered by the new per-agent ceiling (a structural safety net, not a judgment call about its review style). | codebase-derived |

## Acceptance Criteria

- AC-1: `intake-review.mjs` carries the progressive-emit preamble (on `spec-reviewer`'s
  dispatch, replacing `BOUNDED_SPEC_GROUNDING`), `spec-reviewer.md` carries a turn-numbered
  emit deadline and is enrolled in `check-emit-deadline.sh`'s `DEADLINE_AT_DEFAULT`, and a
  per-agent wall-clock ceiling wraps both `spec-reviewer` and `codebase-explorer` dispatches
  — a leg that exceeds the ceiling is declared dark (`{ result: null, retried: true,
  failed: true, ceiling: true }`) on the timer rather than by exhausting its turn cap.
- AC-2: `plan-review.mjs` carries the progressive-emit preamble on its `plan-reviewer`
  dispatches (Gate 1 + Gate 2); the emit deadline is already satisfied transitively
  (`plan-reviewer.md` already carries it and is already enrolled) — verified, not
  re-added; it already has a ceiling (unchanged).
- AC-3: The deadline and ceiling apply to the retry dispatch, not only the first attempt
  — satisfied structurally (the nudge rides on the base prompt string reused by the
  retry; the ceiling wraps the whole per-agent dispatch function, which loops both
  attempts internally), verified by the AC-5 selftest.
- AC-4: The shared `PROGRESSIVE_EMIT` text is single-homed across the three workflows, or
  — single-homing is not achievable (Workflow scripts cannot `import`) — a
  `scripts/lockstep-manifest.tsv` row keeps the copies honest. Two new verbatim rows,
  `code-review.mjs` as the canonical side, anchor `progressive-emit` added to all three
  files.
- AC-5: A selftest exercises the deadline path for `intake-review.mjs` at the tier
  `docs/testing.md` prescribes for Workflow `.mjs` dispatch ladders
  (`workflows/runtime-shim-selftest.mjs`) — a new case executes the REAL
  `intake-review.mjs` body via the shim with a fake agent that never resolves, and
  asserts the ceiling's timer (not the turn cap) is what declares the leg dark.
- AC-6: The shellcheck, jq, and full `*-selftest.sh` sweeps stay green.

## Out of scope

- Raising `maxTurns` (measured non-fix, #175).
- Changing `intake-orchestrator`'s escalate-on-`spec-reviewer`-failure contract.
- Fixing `codebase-explorer.md`'s or `reviewer-baseline`'s stale pre-#169
  "Call StructuredOutput first" language — a real, independently-discovered staleness,
  but not the differentiator run #273 measured (`security-reviewer` completes fine under
  the same stale shared doc), and touching `reviewer-baseline` is cross-cutting to every
  reviewer in the repo. Left for a follow-up.
