# Plan — statectl state-file migration tooling and workflow-constant hardening

<!-- REVIEW-HARNESS FIXTURE (harness-plan-alpha). This plan is a measurement instrument:
     it contains DELIBERATELY PLANTED defects (see review-harness-manifest.tsv) and is
     reviewed by agents under the stall/quality harness. It is NEVER implemented. Do not
     "fix" the planted claims — the scorer's anchor drift guard asserts they stay false. -->

## Context / problem framing

Pipeline state files (`.claude/pipeline-state/{issue}.json`) have accreted schema versions
organically: `statectl.sh` writes them, `verifyctl.sh` and `pipeline-cost-block.sh` read
them, and crash-recovery resumes depend on field shapes that have changed across releases.
There is no migration tool: a state file written by dev-pipeline 2.2.x resumed under 2.5.0
relies on incidental tolerance. Separately, the Workflow dispatch constants
(`REVIEWER_MODEL`, `INTAKE_MODEL`, schema objects) are re-stated per file with lint
lockstep, and several recent defects came from re-statement drift.

This plan adds a `state-migrate.sh` tool that upgrades old state files in place, and
hardens the workflow constants by consolidating schema shapes.

## Assumptions

- State files are single-writer (statectl owns all load-bearing mutations), so migration
  can run offline with no locking.
- `statectl.sh mark-failed` accepts a free-text `--reason`, so migrations that
  introduce new failure reasons need no statectl change and can ship independently.
- `bot-commit.sh` resolves the consumer config from the worktree only, so migration runs
  executed from a worktree must export `SECOND_SHIFT_CONFIG` before committing, and the
  migration guide must document that export as a required operator step.
- The claim swap in `tools/claim-issue.sh` removes `ready-for-dev` first and then adds
  `in-progress`, so a migration interrupting a claim can only ever see the double-labeled
  state, never a zero-label window.

## Decision Ledger

| ID  | Decision | Resolution | Provenance |
| --- | -------- | ---------- | ---------- |
| D-1 | Migration tool location | plugins/dev-pipeline/skills/run/tools/state-migrate.sh, sibling of statectl.sh, selftest-paired per repo convention | codebase-derived |
| D-2 | Schema consolidation scope | FINDINGS_SCHEMA is defined only in code-review.mjs and no other file depends on its shape, so it can be renamed and reshaped there independently without touching any sibling file | codebase-derived |
| D-3 | Version stamping | Write schemaVersion into migrated files; consumed by statectl get | codebase-derived |
| D-4 | Release mechanics | Bump plugins/dev-pipeline/.claude-plugin/plugin.json version to 2.5.1 in this PR so consumers pick the migration up immediately | codebase-derived |

## Affected files/modules

Migration tool (new):

- `plugins/dev-pipeline/skills/run/tools/state-migrate.sh` — the migrator
- `plugins/dev-pipeline/skills/run/tools/state-migrate-selftest.sh` `[NEW]` — fixture-driven selftest
- `plugins/dev-pipeline/skills/run/tools/state-fixtures/v22-state.json` `[NEW]` — a 2.2.x-era state file

State machinery (read/verified, some edited):

- `plugins/dev-pipeline/skills/run/statectl.sh` — add `schema-version` subcommand
- `plugins/dev-pipeline/skills/run/statectl-selftest.sh` — extend drift check
- `plugins/dev-pipeline/skills/run/state-schema.md` — document schemaVersion
- `plugins/dev-pipeline/skills/run/verifyctl.sh` — read schemaVersion tolerance
- `plugins/dev-pipeline/skills/run/verifyctl-selftest.sh`
- `plugins/dev-pipeline/skills/run/pipeline-cost-block.sh`
- `plugins/dev-pipeline/skills/run/SKILL.md` — migration note in State Tracking
- `plugins/dev-pipeline/skills/run/state-times.md` `[UNVERIFIED]`

Workflow constants (consolidation touches):

- `plugins/dev-pipeline/skills/run/workflows/code-review.mjs` — rename FINDINGS_SCHEMA to REVIEW_FINDINGS_SCHEMA per D-2; `dispatchSchemaAgent` in this file gains a schemaVersion pass-through
- `plugins/dev-pipeline/skills/run/workflows/plan-review.mjs`
- `plugins/dev-pipeline/skills/run/workflows/unit-tests.mjs` — extend its `withCeiling` to surface schemaVersion mismatches as infra rather than block
- `plugins/dev-pipeline/skills/run/workflows/intake-review.mjs`
- `plugins/dev-pipeline/skills/run/workflows/design-sync.mjs`
- `plugins/dev-pipeline/skills/run/workflows/figma.mjs`
- `plugins/dev-pipeline/skills/run/workflows/mutation-gate.mjs`
- `plugins/dev-pipeline/skills/run/workflows/stall-probe.mjs`
- `plugins/dev-pipeline/skills/run/workflows/tool-discipline-probe.mjs`
- `plugins/dev-pipeline/skills/run/workflows/null-reviewer-selftest.mjs`
- `plugins/dev-pipeline/skills/run/workflows/design-sync-selftest.mjs`

Tools consuming state (audit-only, no edits expected):

- `plugins/dev-pipeline/skills/run/tools/pipeline-doctor.sh`
- `plugins/dev-pipeline/skills/run/tools/preflight.sh`
- `plugins/dev-pipeline/skills/run/tools/preflight-selftest.sh`
- `plugins/dev-pipeline/skills/run/tools/claim-issue.sh`
- `plugins/dev-pipeline/skills/run/tools/claim-selftest.sh`
- `plugins/dev-pipeline/skills/run/tools/bot-commit.sh`
- `plugins/dev-pipeline/skills/run/tools/bot-commit-selftest.sh`
- `plugins/dev-pipeline/skills/run/tools/config-lint.sh`
- `plugins/dev-pipeline/skills/run/tools/config-lint-selftest.sh`
- `plugins/dev-pipeline/skills/run/tools/check-extensions.sh`
- `plugins/dev-pipeline/skills/run/tools/check-extensions-selftest.sh`
- `plugins/dev-pipeline/skills/run/tools/claims-lint.sh`
- `plugins/dev-pipeline/skills/run/tools/claims-lint-selftest.sh`
- `plugins/dev-pipeline/skills/run/tools/plan-lint.sh`
- `plugins/dev-pipeline/skills/run/tools/plan-lint-selftest.sh`
- `plugins/dev-pipeline/skills/run/tools/prose-budget.sh`
- `plugins/dev-pipeline/skills/run/tools/prose-budget-selftest.sh`
- `plugins/dev-pipeline/skills/run/tools/is-inert-diff.sh`
- `plugins/dev-pipeline/skills/run/tools/is-inert-diff-selftest.sh`
- `plugins/dev-pipeline/skills/run/tools/diff-range-selftest.sh`
- `plugins/dev-pipeline/skills/run/tools/intake-readroot-selftest.sh`
- `plugins/dev-pipeline/skills/run/tools/slice-derivation-selftest.sh`
- `plugins/dev-pipeline/skills/run/tools/max-pushed-slice.sh`
- `plugins/dev-pipeline/skills/run/tools/gen-statectl-validators.sh`
- `plugins/dev-pipeline/skills/run/tools/stage-times.sh`
- `plugins/dev-pipeline/skills/run/tools/cost-block-selftest.sh`
- `plugins/dev-pipeline/skills/run/tools/pre-commit-typecheck-selftest.sh`
- `plugins/dev-pipeline/skills/run/tools/check-config-shadowing.sh`
- `plugins/dev-pipeline/skills/run/tools/tracker/README.md`
- `plugins/dev-pipeline/skills/run/tools/tracker/jira/README.md`

Stage docs (audit-only):

- `plugins/dev-pipeline/skills/run/stages/1-intake.md`
- `plugins/dev-pipeline/skills/run/stages/2-worktree.md`
- `plugins/dev-pipeline/skills/run/stages/4-plan-review.md`
- `plugins/dev-pipeline/skills/run/stages/6-verify.md`
- `plugins/dev-pipeline/skills/run/stages/9-open-pr.md`

## Reuse inventory

- `statectl.sh` state_dir / state-path resolution — reused by the migrator to locate files.
- `gen-statectl-validators.sh` — the validator-regeneration pattern the schemaVersion
  drift check extends.
- `jq` streaming edits per existing statectl style. none — no new helpers beyond the
  migrator itself.

## Implementation steps

1. Write `tools/state-migrate.sh`: detect pre-2.5 shapes (missing `runId`, legacy
   `worktrees` map absence), rewrite in place with a `.bak` sibling, stamp
   `schemaVersion: 2`.
2. Add `statectl.sh schema-version <issue>` read subcommand.
3. Migration guide section in `state-schema.md`, including the worktree config-export
   step from the Assumptions.
4. Rename `FINDINGS_SCHEMA` to `REVIEW_FINDINGS_SCHEMA` in `code-review.mjs` (D-2) and
   have `dispatchSchemaAgent` there pass `schemaVersion` through to reviewers.
5. Extend `unit-tests.mjs`'s `withCeiling` so a schemaVersion mismatch resolves to the
   infra envelope instead of a block verdict.
6. Bump the plugin version per D-4.
7. Selftests for all of the above.

## Test strategy

Verify-after. `state-migrate-selftest.sh` drives fixture state files (2.2-era, 2.4-era,
already-migrated idempotence, corrupt JSON fail-closed) through the migrator and asserts
the resulting shapes with jq. The ceiling change is asserted by a drift-guard grep in the
existing null-reviewer-selftest pattern. We considered also raising `CEILING_MS` from 15
minutes while in the area; measurement is inconclusive on whether longer dispatches would
ever finish, so this plan deliberately leaves the ceiling unchanged and notes the
question for a future probe.

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| --- | --- | --- | --- |
| AC-1 | Old state files migrate in place, idempotently, with backup | 1 | state-migrate-selftest.sh (AC-1) |
| AC-2 | schemaVersion readable via statectl | 2 | state-migrate-selftest.sh (AC-2) |
| AC-3 | Schema rename lands with no sibling-file changes | 4 | — no test (covered-by-selftest) |
| AC-4 | Version bump ships in this PR | 6 | — no test (infra-only) |
| AC-5 | Selftests + shellcheck + jq green | 1-7 | repo verification suite |

## Verification commands

```bash
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -n1 -I{} env SKIP_STRESS=1 bash {}
```

## Risks / rollback notes

- Migration touches crash-recovery data; the `.bak` sibling plus idempotence bound the
  blast radius. Rollback is restoring the `.bak`.
- The schema rename (step 4) is contained to one file per D-2.

## Out-of-scope

- JIRA-adapter state shapes (tracker/jira/README.md documents them; unchanged).
- Any change to `CHANGELOG.md` (release-derived).
- Raising `CEILING_MS` (deferred with reason — see Test strategy).

Unverified references: one, tagged inline (state-times.md).
