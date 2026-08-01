# Plan: acme-8888 — Fixture plan for plan-scope-paths selftest

## Context

Fixture. Exercises multiple path tokens in Affected files/modules and one in
Out-of-scope.

## Affected files/modules

- `apps/api/src/modules/widget/widget.service.ts`
- `apps/api/src/modules/widget/widget.controller.ts`
- Also touches `apps/api/src/modules/widget/widget.service.ts` again (dup — must dedupe)

## Reuse inventory

- none.

## Implementation steps

1. Step one.

## Test strategy

N/A — fixture.

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| ----- | ------------------ | ------- | ------- |
| AC-1  | Fixture only        | 1       | — no test (infra-only) |

## Verification commands

- n/a

## Risks / rollback notes

- None.

## Out-of-scope

- Do not touch `apps/api/src/modules/widget/widget.module.ts` in this change.
