# second-shift #574 — retire the five #348-stranded engines (lean spec)

Issue: https://github.com/manoldonev/second-shift/issues/574
Pre-flight ledger: `.claude/pipeline-state/574-ledger.md` (binding input; ratified 2026-08-18).
Sequencing: this lands **before** #575 — its strengthened parity check must find rows 56/61/63
TRUE on main, which is what AC-4 produces.

## Problem

#348 deleted the staged lane's stage docs — the only dispatchers of four shipped Workflow
engines (`design-sync.mjs`, `figma.mjs`, `mutation-gate.mjs`, transitively `unit-tests.mjs`) —
and left them in the tree unreachable. The same class covers `pipeline-cost-block.sh`'s
stateful branch (sole live caller passes `--stateless`). #577 already corrected parity rows
56/61/63 to `dropped` with `CORRECTED (#574)` notes; this PR executes the ratified
dispositions: **retire all five**, plus the engineer-elected retirement of the two config keys
the mutation pair stranded.

## Acceptance criteria

- **AC-1 — engine deletion.** `plugins/dev-pipeline/workflows/design-sync.mjs`,
  `figma.mjs`, `mutation-gate.mjs`, `unit-tests.mjs`, and `design-sync-selftest.mjs` are
  deleted. The runtime-shim ladder (`runtime-shim-selftest.mjs`) carries no design-sync/
  mutation-gate/unit-tests cases; `workflows-mjs-selftest.sh` no longer executes
  `design-sync-selftest.mjs`; `pipeline-doctor.sh`'s node check and workflow loop name only
  surviving engines. No non-historical reference to the four engines remains outside
  `docs/plans/`, `CHANGELOG.md`, and registers whose rows are permanent record
  (`tools/capability-parity.tsv` paths cell, mutation registers' historical rows).
- **AC-2 — cost-block stateful branch.** Every `$STATELESS`-guarded stateful path in
  `plugins/dev-pipeline/tools/pipeline-cost-block.sh` is removed (per-stage bucketing,
  `cost-log.jsonl` writer, `costBlockApplied` record), along with the selftest cases and
  `cost-tracking-fixtures/` entries only they drive. The stateless CLI contract is unchanged:
  `--stateless --sessions <ids> --start/--end` invocations produce the same output as before
  (D-10). `cost-tracking-setup.md` drops the stateful prose.
- **AC-3 — config-key retirement (breaking).** `commands.<host>.unitTestScope` and
  `commands.<host>.testFile` are out of the schema; `config-lint.sh` rejects each **by name**
  with a migration pointer (#569/#571 shape); the configVersion migration doc satisfies
  `check-configversion-migration-doc.sh`. Advisory surfaces that read or recommend the keys
  (config-grill `T4.mutation-plumbing`, onboard, doctor and their selftests,
  `config-diff-guard`, `check-config-shadowing`) are updated coherently. `gates.mutation`
  stays (D-5 — it declares D-18 sweep intent, not engine wiring).
- **AC-4 — parity rows final form.** Rows 56, 61, 63 of `tools/capability-parity.tsv` stay
  `dropped`; each note replaces its "Re-wire or retire is tracked in #574" tracking sentence
  with the executed disposition naming **resolvable** successors: row 61 → advisory
  `unit-test-mutation-reviewer` via review-lead (propose half), execution-verified blocking
  dropped by architecture, consumer on-ramp #482 (left unprejudiced, D-9); rows 56/63 →
  intake-routed `design-faithful-spec` (produce), row-62 free dispatch (implement),
  milestone-3 render receipt + review-lead fidelity dimension + `review-lean --fidelity`
  per row 76 (verify).
- **AC-5 — model-tier carriers (OR-1 default).** The `EXECUTOR_MODEL` (mutation-gate) and
  `UNIT_TEST_MODEL` (unit-tests) carrier arms are removed from
  `plugins/review-toolkit/scripts/check-model-tiers.sh` (+ its selftest) and from
  `plugins/dev-pipeline/model-tiering.md`; the schema's `modelOverrides` description no
  longer offers `mutation-executor` as its example. Flagged in the PR body as a deliberate
  tier-guard shrink (reversible if #482 restores an executor surface).
- **AC-6 — docs.** `docs/testing.md`, `docs/extending.md`, `docs/namespaces.md`,
  `docs/config-schema.md`, and CLAUDE.md's registers carry no reference to the deleted
  engines or retired keys as live surfaces. CLAUDE.md's mirror-harness *history* prose
  (the design-sync `ReferenceError` lesson) stays — it records the past, not the tree.
  `plugins/design-toolkit` "Dispatched by the design-sync engine" frontmatter/prose is
  re-pointed to the row-62 posture (D-7): skills survive, dispatch is the session's choice,
  `design-faithful-spec` is intake-routed.
- **AC-7 — register obligations.** `scripts/lockstep-manifest.tsv` rows citing the deleted
  files are resolved (dropped or re-anchored, DROPPED entries carrying the reasoning);
  `tools/mutation-baseline.tsv` generic-survivor ordinals for every edited guard are re-keyed
  in the same diff; `tools/mutation-catalog.tsv` rows addressing edited guards are
  re-anchored; `tools/install-topology-known-red.tsv` rows naming deleted suites are
  resolved.

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | mutation-gate.mjs + unit-tests.mjs disposition | Retire: delete both engines. Execution-verified mutant blocking dropped BY ARCHITECTURE — lean has no model-billed gate seam (milestone 3 runs commands, not Workflow harnesses; a voluntarily-dispatched gate is not a gate) and the D-18 repo-carried sweep owns mutation with a deterministic/no-model-calls contract, so re-wiring would ship a second mutation owner. Propose half survives as advisory unit-test-mutation-reviewer via review-lead. Consumer on-ramp stays #482, unprejudiced. | user-answered |
| D-2 | design-sync.mjs + figma.mjs disposition | Retire: delete both engines, design-sync-selftest.mjs, and the runtime-shim ladder's design-sync cases. Successors per arm: produce → intake router dispatches design-toolkit:design-faithful-spec directly; implement → row-62 precedent (outcome-gated build, session dispatches design-faithful by choice); verify → milestone-3 render receipt + review-lead fidelity dimension + review-lean --fidelity (parity row 76, #394 machinery). | user-answered |
| D-3 | pipeline-cost-block.sh stateful branch | Retire: strip every $STATELESS-guarded stateful path (per-stage bucketing, cost-log.jsonl writer, costBlockApplied record), the selftest cases that exist only to drive it, and any cost-tracking-fixtures only they consume. CLI contract for the live caller unchanged (D-10). | user-answered |
| D-4 | Config keys stranded by D-1 (`commands.<host>.unitTestScope`, `commands.<host>.testFile`) | Retire the keys IN THIS PR, the #569/#571 shape: out of the schema, config-lint rejects them by name, configVersion migration doc updated (check-configversion-migration-doc.sh gates this). Engineer chose in-PR over the recommended follow-up ticket — the PR is therefore breaking (`!`). Blast radius includes every tool that RECOMMENDS the keys (config-grill T4.mutation-plumbing, onboard, doctor-selftest, config-diff-guard). Gitignored dogfood configs carrying the keys are migrated by operators — the migration doc says so. | user-answered |
| D-5 | `gates.mutation` | KEEP — live regardless of D-1: declares intent for the repo-carried D-18 sweep, read by config-grill/doctor advisories (#477). Only stale description references change. Grounding: schema `gates.mutation` description; docs/onboarding.md D-18 contract. | codebase-derived |
| D-6 | Parity rows 56/61/63 final form | Keep `dropped`; replace the tracking sentence with the executed disposition naming resolvable successors — required by the operator's sequencing constraint (#575 lands after): https://github.com/manoldonev/second-shift/issues/574#issuecomment-5320705645 | ticket-sourced |
| D-7 | design-toolkit skills/agents dispatcher prose | Survive untouched as skills; re-point "Dispatched by the design-sync engine" prose per the row-62 precedent. Grounding: tools/capability-parity.tsv row 62; the intake router scenario table. | codebase-derived |
| D-8 | Row-note successor mapping | Row 61: advisory unit-test-mutation-reviewer (propose) + dropped-by-architecture (execute) + #482 (on-ramp). Rows 56/63: intake→design-faithful-spec / row-62 dispatch / render receipt + fidelity panel per row 76. Grounding: rows 62/76 of tools/capability-parity.tsv; review-lead SKILL.md reviewer routing. | codebase-derived |
| D-9 | #482 scope boundary | This PR must NOT decide #482's form question. Row 61's note may cite #482 as the open consumer on-ramp; nothing else. Grounding: #482 body — filed needs-intake-review, "the central question is whether this should ship at all". | codebase-derived |
| D-10 | pipeline-cost-block.sh CLI contract | Unchanged externally: `--stateless --sessions <ids> --start/--end` stays the invocation shape (sole live caller build-lean SKILL.md step 7). Internal flag handling is the builder's call. Grounding: pipeline-cost-block.sh:83-107; build-lean SKILL.md step 7. | codebase-derived |
| D-11 | modelOverrides `mutation-executor` override (EP-4) | Parked under OR-1 (pre-flight receipt): default executed as AC-5 — remove the EXECUTOR_MODEL/UNIT_TEST_MODEL carrier arms with their carriers; reversible via #482; flagged in the PR body. | deferred |

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | Parity rows 56/61/63 final notes | decided (AC-4) |
| S-2 | model-tiering.md + check-model-tiers.sh carrier arms | decided (AC-5) |
| S-3 | pipeline-doctor.sh operator output naming mutation-gate.mjs | decided (AC-1) |
| S-4 | Schema keys, config-lint by-name rejection, migration doc | decided (AC-3) |
| S-5 | config-grill/onboard/doctor advisory text reading unitTestScope | decided (AC-3) |
| S-6 | docs/*.md + CLAUDE.md registers; design-toolkit dispatcher prose | decided (AC-6) |
| S-7 | cost-tracking-setup.md | decided (AC-2) |
| S-8 | Test/register surfaces (shim ladder, workflows-mjs, cost-block selftest, lockstep, mutation baseline/catalog, install-topology-known-red) | decided (AC-1, AC-2, AC-7) |
| S-9 | CHANGELOG.md / versions / marketplace metadata | out-of-scope — release-derived frozen files; intent travels as the commit's Changelog trailer |
| S-10 | Gitignored dogfood configs carrying retired keys | decided (AC-3 — operator migration named in the migration doc) |

No user-facing UI surface — every surface above is an operator-read artifact.

## Out of scope

- #575's strengthened parity check (lands after this, by design).
- #482's consumer on-ramp form question (D-9).
- Any change to the D-18 execution block or its CLI contract.
- Versions / CHANGELOG.md / marketplace metadata (release-derived).
