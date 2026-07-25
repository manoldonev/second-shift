# Plan: acme-9998 — Hydration fixture, emphasis-delimiter drift

## Context

Fixture. Hydrates `hydration-ledger.md` with two Resolution cells rewritten by a markdown
formatter and nobody's author — `*object*` to `_object_` (italic) in D-1, and `**conflict**`
to `__conflict__` (bold) in D-4. `norm_cell()` folds the two through separate rules, so both
are needed to exercise it. Check 6 must not read either as drift.

## Assumptions

- None.

## Decision Ledger

| ID  | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Serialization shape for the import payload | return a bare _object_, never an array | codebase-derived |
| D-2 | Retry budget for the import worker | three attempts with exponential backoff | codebase-derived |
| D-3 | Naming convention for the new helper | use snake_case to match the sibling tools | codebase-derived |
| D-4 | Behavior on a duplicate import id | reject it as __conflict__, do not overwrite | codebase-derived |

## Affected files/modules

- `apps/api/src/modules/example/example.service.ts`

## Reuse inventory

- none — no new helpers introduced

## Implementation steps

1. Step one.
2. Step two.

## Test strategy

Test-first for the behavior change.

## Acceptance-criteria traceability

| AC ID | Criterion (short)                | Step(s) | Test(s)                     |
| ----- | -------------------------------- | ------- | --------------------------- |
| AC-1  | Import returns the credited ride | 1       | example.service.spec (AC-1) |
| AC-2  | A failed import is retried       | 2       | example.service.spec (AC-2) |

## Verification commands

- `yarn --cwd apps/api test example`

## Risks / rollback notes

- None.

## Out-of-scope

- Everything else.
