# Plan: acme-9999 — Fixture plan for plan-lint selftest

## Context

Fixture. Exercises every mandated section and the traceability-table shapes.

## Assumptions

- None.

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

| AC ID | Criterion (short)                     | Step(s) | Test(s)                     |
| ----- | ------------------------------------- | ------- | --------------------------- |
| AC-1  | Ride credited on upload (shows A \| B) | 1       | example.service.spec (AC-1) |
| AC-2  | No credit on empty FIT file            | 2       | — no test (infra-only)      |

## Verification commands

- `yarn --cwd apps/api test example`

## Risks / rollback notes

- None.

## Out-of-scope

- Everything else.
