# Plan: acme-8891 — Fixture plan with a standalone bold-line section header

## Context

Fixture. Counterpart to bold-lead-prose-plan.md: a STANDALONE bold-line header
(the whole trimmed line is exactly `**...**`, the `plan-lint.sh`
`section_present()` bold-header convention) still correctly ends the section —
narrowing the terminator to exclude bold-LEAD prose must not also stop it from
recognizing a genuine bold-line heading.

## Affected files/modules

- `foo/bar.ts`

**Reuse inventory**

- `foo/baz.ts` should NOT be captured — it is past the standalone bold header,
  in a different section entirely.

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

- Everything else.
