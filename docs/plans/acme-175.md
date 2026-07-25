# Plan: #175 — maxTurns-cap deaths: targeted raises + declared-dormancy lint

## Context

The explorer/emitter transport (#170) killed the schema-forced stall, but an agent that
hits its frontmatter `maxTurns` cap before writing any text resolves with an empty result —
no sentinel, correctly dark. Six deterministic deaths across two repos share one signature:
tool calls ≈ cap, empty final text, zero errors. The two victims are the mandate-exhaustive
agents: `scope-completeness-reviewer` (cap 15, died 16–18 calls, 2/2, run #165) and the
`unit-test-mutation-reviewer` proposer (cap 12, died 4/4 at 12–14 calls, consumer repo).
The field re-dispatch WITH the bounding nudge wired still died 4/4 — the cap itself is the
defect. Fix: raise the two caps to 30. Ride-alongs (zero runtime behavior): a
declared-dormancy lint rule closing the dead-constant gap, and wording correction inside
the three dormant nudge constants.

## Assumptions

- A `maxTurns` raise is strictly permissive: it cannot change what an agent writes, only
  whether it gets to finish. Detection parity is therefore not implicated (no prompt,
  parser, or dark-path byte changes). Runaway cost stays bounded by the dispatchers'
  wall-clock ceiling (`CEILING_MS`, `withCeiling` in `code-review.mjs`).
- 30 ≈ 2× the observed death points (16–18 and 12–14 calls) is sufficient headroom;
  empirical sufficiency is validated by the next field runs (the parked consumer Stage-5
  resume is the designated first datapoint) per the intake verification decision.
- The three `BOUNDED_*` constants in `plan-review.mjs` / `unit-tests.mjs` are dormant by
  deliberate #170 decision (defined for probe lockstep, never appended) — confirmed by
  grep: no non-comment reference outside their definitions.

## Decision Ledger

Hydrated from the pre-flight ledger (`.claude/pipeline-state/175-ledger.md`); the D-2 cell is redacted for the public repo (branch/ticket identifiers described generically).

| id | decision | choice | provenance |
| --- | --- | --- | --- |
| D-1 | Root fix for turn-cap deaths | Raise maxTurns on the two mandate-exhaustive agents only: scope-completeness-reviewer 15 to 30, unit-test-mutation-reviewer 12 to 30; all other agents keep their measured caps | user-delegated |
| D-2 | Bounding-nudge proposal branch | Rejected as the fix: the consumer-repo field re-dispatch ran WITH the wired bound and still died 4 of 4 at 12 to 14 calls, and its plan-review wiring reverses the measured 0-of-8 no-nudge arm; branch stays parked, unmerged | user-delegated |
| D-3 | Emit-early skeleton contract | Not pursued: risks review depth for no need once caps fit the mandate; revisit only if raised caps still show cap-shaped deaths | user-delegated |
| D-4 | No-regression gate | Caps-only frontmatter change leaves every prompt, parser, and dark-path byte identical; gate is the full selftest sweep plus shellcheck plus jq plus check-bounded-exploration; detection-parity harness not implicated because review content is untouched; wall-clock CEILING_MS remains the runaway cost backstop | codebase-derived |
| D-5 | Recurrence lint | check-bounded-exploration.sh gains a dead-constant rule: any workflow-defined BOUNDED_ constant with zero references outside its definition fails, with a selftest case; closes the gap that let dead wiring pass | user-delegated |
| D-6 | Wording drift | Correct emit StructuredOutput to emit the REVIEW_RESULT block in the unwired production constants and the stall-probe copy, so future wiring cannot ship an instruction naming a tool schema-free explorers do not have | user-delegated |
| D-7 | Dark-path semantics | Unchanged: missing sentinel stays dark, truncation is never laundered into a verdict | codebase-derived |

Stage-1 amendments (spec-reviewer evidence, recorded in the intake comment):

- **D-6 narrowed.** The stall-probe copies serve the schema-FORCED control arm, where
  "emit StructuredOutput" is historically faithful, and the same phrase also lives in the
  LIVE `code-review.mjs` BOUNDED_EXPLORATION prompt. Wording correction is confined to the
  three dormant constants in `plan-review.mjs` / `unit-tests.mjs`; `stall-probe.mjs` and
  `code-review.mjs` are untouched (the live-string inconsistency is a measured follow-up).
- **D-5 refined.** A bare zero-references-fails rule would flag the deliberate #170
  dormancy red. Rule: a workflow-defined `BOUNDED_*` with zero non-comment references
  outside its definition AND no `bounded-exploration-dormant: <NAME> -- <reason>` marker
  fails; the dormant constants get markers. Deliberate deadness becomes declared.

## Affected files/modules

- `plugins/review-toolkit/agents/scope-completeness-reviewer.md` — frontmatter `maxTurns: 15` → `30` (line 7)
- `plugins/review-toolkit/agents/unit-test-mutation-reviewer.md` — frontmatter `maxTurns: 12` → `30` (line 6)
- `plugins/dev-pipeline/skills/run/tools/check-bounded-exploration.sh` — declared-dormancy rule
- `plugins/dev-pipeline/skills/run/tools/check-bounded-exploration-selftest.sh` — new cases
- `plugins/dev-pipeline/skills/run/workflows/plan-review.mjs` — dormant `BOUNDED_PLAN_GROUNDING` (line 60): wording + dormancy marker
- `plugins/dev-pipeline/skills/run/workflows/unit-tests.mjs` — dormant `BOUNDED_PLAN_GROUNDING` (line 103) + `BOUNDED_MUTATION_SWEEP` (line 114): wording + dormancy markers

## Reuse inventory

- `check-bounded-exploration.sh` existing marker grammar + per-file scan loop (grep-verified: marker parsing at its `bounded-exploration:` / `-optout:` / `-delegated:` sites) — the dormancy rule extends this file's existing scan, no new tool.
- `check-bounded-exploration-selftest.sh` fixture harness (grep-verified: existing 25-case suite with tmp-dir fixture files) — new cases reuse its `ok`/`bad` fixture pattern.
- none — no new helpers introduced.

## Implementation steps

1. Raise `maxTurns: 15` → `30` in `plugins/review-toolkit/agents/scope-completeness-reviewer.md` and `maxTurns: 12` → `30` in `plugins/review-toolkit/agents/unit-test-mutation-reviewer.md`.
2. In `plugins/dev-pipeline/skills/run/workflows/plan-review.mjs` and `unit-tests.mjs`, correct the trailing sentence of the three dormant constants: "Stop exploring and emit StructuredOutput before your budget runs low." → "Stop exploring and emit the REVIEW_RESULT block before your budget runs low." NOTE: in `unit-tests.mjs` the first occurrence is split across two source lines ("emit" / "StructuredOutput") — edit by constant, not by single-line grep.
3. Add a dormancy marker comment above each of the three dormant definitions: `// bounded-exploration-dormant: <NAME> -- defined for probe lockstep; deliberately not appended (measured no-nudge arm)`.
4. Add the declared-dormancy rule to `check-bounded-exploration.sh`: for every non-probe `workflows/*.mjs` file, each `const BOUNDED_[A-Z_]+ =` definition must have ≥1 non-comment reference to its name outside the definition (multi-line concatenation counts via the name appearing on a non-comment, non-definition line) OR a `bounded-exploration-dormant: <NAME>` marker in the same file; otherwise FAIL with a message naming the constant and the marker grammar. Probe files (`*-probe.mjs`) are exempt (their constants are table-referenced and they keep the open grammar).
5. Extend `check-bounded-exploration-selftest.sh`: (a) fixture with an unreferenced `BOUNDED_DEAD` and no marker → FAIL expected; (b) same fixture plus dormant marker → pass; (c) referenced constant, no marker → pass; the existing "live workflows tree is clean" case now exercises the rule against production files end-to-end (it fails unless step 3's markers exist — ordering: steps 2–3 land before or with step 4–5 in one commit).
6. Sweep the remaining workflow files (`design-sync.mjs`, `figma.mjs`, `intake-review.mjs`, `code-review.mjs`, `mutation-gate.mjs`) for any other dormant `BOUNDED_*` definition; wire-or-mark is out of scope — if one is found, it gets a dormancy marker with a reason (expected: none; `code-review.mjs` BOUNDED_EXPLORATION is live).

## Test strategy

Verify-after (infra/lint change, no product behavior surface). The lint rule is
behavior-tested by its selftest (new cases in step 5); the cap raises are frontmatter
values asserted by the verification commands below. No mutation surface: the repo
configures no `commands.second-shift.unitTestScope`.

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| --- | --- | --- | --- |
| AC-1 | Two agent caps at 30, no other cap changes | 1 | — no test (infra-only) |
| AC-2 | No production prompt/parser/dark-path changes; diff confined to listed files | 2, 3, 6 | — no test (covered-by-selftest) |
| AC-3 | Dormancy lint rule + markers + selftest coverage | 3, 4, 5 | check-bounded-exploration-selftest.sh new cases |
| AC-4 | Sweep + shellcheck + jq green | 1-6 | — no test (covered-by-selftest) |

## Verification commands

```bash
grep -n "maxTurns" plugins/review-toolkit/agents/scope-completeness-reviewer.md plugins/review-toolkit/agents/unit-test-mutation-reviewer.md   # AC-1: both 30
grep -rn "maxTurns" plugins/review-toolkit/agents/ | grep -v ": 30" | grep -vE ": (15|2)$" || true   # no other cap drifted (12 retired by step 1)
bash plugins/dev-pipeline/skills/run/tools/check-bounded-exploration.sh
bash plugins/dev-pipeline/skills/run/tools/check-bounded-exploration-selftest.sh
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -n1 -I{} env SKIP_STRESS=1 bash {}
```

## Risks / rollback

- R1: the "live workflows tree clean" selftest case turns the new rule loose on all
  production files — an unnoticed dormant `BOUNDED_*` elsewhere fails it. Mitigated by
  step 6's sweep; the fix is a marker, not a wiring change.
- R2: raised caps increase worst-case dispatch cost on the two agents. Bounded by the
  dispatchers' `CEILING_MS` wall-clock ceiling; the raise only permits completion of work
  already being attempted (and previously wasted at 100%).
- R3: `text-contract-selftest.sh` byte-lockstep covers `parseReviewResult`/`validateShape`
  only — the wording edits touch neither function; no lockstep surface is disturbed.
- Rollback: revert the two frontmatter values; the lint rule and markers are independent
  and can stay.

## Out-of-scope

- The live `code-review.mjs` BOUNDED_EXPLORATION wording inconsistency (prompt change —
  needs a measured pass).
- All `stall-probe.mjs` constants (schema-forced control-arm fidelity).
- The parked bounding-nudge proposal branch (field-eliminated as a cure).
- Any cap change to other agents; emit-early skeleton contract (D-3).

Unverified references: none.
