# Plan: acme-9998 — Zero-AC refactor fixture

## Context

Refactor with no issue acceptance criteria (no AC heading in the issue body).

## Assumptions

- None.

## Affected files/modules

- `apps/api/src/modules/example/example.service.ts`

## Reuse inventory

- none — no new helpers introduced

## Implementation steps

1. Rename the helper.

## Test strategy

Verify-after via the standard suite (refactor).

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| ----- | ----------------- | ------- | ------- |

## Verification commands

- `yarn --cwd apps/api test example`

## Risks / rollback notes

- None.

## Out-of-scope

- Everything else.
