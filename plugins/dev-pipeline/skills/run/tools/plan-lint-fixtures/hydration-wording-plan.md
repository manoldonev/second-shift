# Plan: acme-9998 — Hydration fixture, real drift that must still fail

## Context

Fixture. Hydrates `hydration-ledger.md` with two rows that differ for reasons no formatter
could produce, so Check 6 must still fail on both:

- `D-1`'s Resolution is genuinely reworded — the decision itself was inverted.
- `D-3` swaps the lone underscore of `snake_case` for an asterisk. Emphasis folding is
  paired-only, so a single delimiter has nothing to pair with and this stays a real
  difference. A blanket underscore-to-asterisk fold would wrongly pass this row.

## Assumptions

- None.

## Decision Ledger

| ID  | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Serialization shape for the import payload | return an array, never a bare *object* | codebase-derived |
| D-2 | Retry budget for the import worker | three attempts with exponential backoff | codebase-derived |
| D-3 | Naming convention for the new helper | use snake*case to match the sibling tools | codebase-derived |

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
