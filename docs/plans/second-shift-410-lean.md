# second-shift #410 — test-coverage review gets a second axis: coverage that cannot fail

## Problem

`test-coverage-reviewer` carries Critical intents for *absent* tests and no intent at all for
*decorative* ones, so every pipeline run can only push the test count up. The rule that would
catch it already exists — `test-coverage-reviewer.md`'s `### Test-Surface Shape` section, whose
"coverage that restates what a scenario already drives is accretion, not assurance" is exactly
right — but the section is scoped to this repo's own artifacts (pipeline gates, per-tool
fixtures, prose greps), so a consumer repo's reviewer never applies it to the equivalent shapes
in application code. The observed cost is CI timeout pressure, and the reflex fix is to raise a
per-file test timeout — treating the symptom.

## Constraint (binding, from the issue)

The existing floors do not move. A repo with genuinely missing coverage still gets a Critical.
This is a **second axis, not a discount on the first**.

## Non-goals

- No new transport. Decorative findings ride the propose-mode advisory channel that already
  exists (`mockAuditFindings[]`: `warning | note`, spec-scoped, already dispositioned by Stage 5
  as "address inline"). No schema field, no new array, no `mutation-gate.mjs` change.
- No promotion path to blocker. Severity `blocker` stays unavailable to this class by
  construction — that unavailability *is* the constraint above, mechanized.
- No re-baselining of `.claude/prose-budget.baseline.tsv`. It is already stale across 19 rows on
  a clean tree; regenerating it here would sweep unrelated files into this diff.

## Acceptance criteria

**AC-1.** `plugins/review-toolkit/agents/test-coverage-reviewer.md`'s `### Test-Surface Shape
(pipeline-gate and contract-duplication changes)` section is restated stack-neutrally: neither
the heading nor any bullet scopes the rule to pipeline-gate or contract-duplication changes, and
no remaining clause requires the repo under review to have gates, scenarios, fixtures, or a
lockstep manifest for the check to apply.

**AC-2.** That section enumerates the six stack-neutral decorative shapes named in the issue —

1. a test whose assertions differ from a sibling's only by fixture,
2. asserting static copy no branch selects between,
3. an existence inventory: a run of presence assertions with no interaction and no state change,
4. asserting the absence of code that does not exist,
5. asserting what a library did with what we passed rather than what we passed,
6. re-testing a pure function through an expensive integration render

— plus the **mirror harness** shape retained from the current section (a test that re-declares
production logic and asserts on the copy).

**AC-3.** The section remains under `## Warning Rules` and states in-file that it never
downgrades a Critical Coverage Intent, so the next editor cannot promote it without deleting the
sentence that forbids it.

**AC-4.** A cost intent is present in that section: both a new case whose wall-clock is out of
line with its siblings **and** a raised per-file test timeout in the diff are flagged, with the
raised ceiling named as a symptom rather than a fix.

**AC-5.** The composed-contract rule surviving from the current first bullet is generalized, not
deleted: a change to a contract that multiple components compose against must name the affected
paths and say how the end-to-end test exercising them composed was extended for each.

**AC-6.** `plugins/review-toolkit/skills/mutation-review/SKILL.md` defines the decorative-test
check as part of the propose process: for each test **added in the commit range**, which proposed
mutant is it the only killer of; if none — because it kills nothing, or a cheaper sibling kills
everything it does — report it with the remedy (delete, or fold the fixture into the case that
already covers the rule). The definition states all three of: bounded to tests added in the range,
never blocker-class, and carried on the existing advisory channel.

**AC-7.** `plugins/review-toolkit/agents/unit-test-mutation-reviewer.md` carries the check in its
`## Process` steps, its severity table, and both output modes (propose-only and advisory).

**AC-8.** `plugins/dev-pipeline/skills/run/workflows/unit-tests.mjs`'s mutation-review dispatch
prompt names the decorative-test check alongside the mock-only audit it already names, so the
Stage-5 dispatch is not weaker than the agent contract it dispatches.

**AC-9.** A `runtime-shim-selftest.mjs` case drives the **real** `unit-tests.mjs` body under the
shim with `kind: 'mutation-review'` and asserts the dispatched prompt carries the AC-8 clause,
following the Case-H `H2a/H3a` precedent (assert on `calls[0].prompt` from an executed dispatch).
An anti-vacuity assertion pins that the mutation-review dispatch actually happened, so the case
cannot pass on a dispatch that never occurred.

## Test tier

Per `CLAUDE.md`'s tier map, AC-1 through AC-7 are prose in markdown files — **nothing** is
written for them; a grep asserting a literal is present in a `.md` is the banned class. AC-8 is a
production Workflow `.mjs` dispatch, so it takes a shim case (AC-9) — the tier map's row for
"a production Workflow `.mjs` dispatch ladder". No mutation-catalog row: the sweep mutates shell
guards, and no shell guard changes here.

## Release metadata

- Bump: **minor**. New reviewer capability in `review-toolkit`, and per `CLAUDE.md` this repo's
  AI tooling *is* the product, so the honest verb is `feat:`. The level derives from the squash
  subject, so the **PR title** must carry `feat(review-toolkit): …`.
- `Changelog:` trailer: consumer-visible, so a real trailer — not `none`.
