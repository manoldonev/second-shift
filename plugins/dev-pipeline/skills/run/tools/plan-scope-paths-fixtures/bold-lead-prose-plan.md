# Plan: acme-8890 — Fixture plan with bold-lead prose inside a section body

## Context

Fixture. Regression guard for the #109 round-2 review finding: a bold-LEAD
prose line (e.g. `**Note:** ...`, in the style this repo's own plans use for
`**D-1.**`/`**Changed:**`/`**Created:**` labels) sits INSIDE the
Affected-files body, between two path bullets. It must NOT be mistaken for a
section-boundary heading — only a STANDALONE bold-line header (the whole
trimmed line is exactly `**...**`) ends the slice.

## Affected files/modules

- `foo/bar.ts` — the first one.
**Note:** clarifying context that happens to start with a bold marker.
- `foo/baz.ts` — the second one, must still be captured.

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

- Everything else.
