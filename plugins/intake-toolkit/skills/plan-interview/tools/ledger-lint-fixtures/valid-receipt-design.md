# Intake receipt: PROJ-9998 — Fixture receipt for a repo with design.provider set

## Context

Fixture. A receipt on a design-provider repo: the explicit empty form under `## Checks`, and a
`## Design frames` table whose every row names what the route smoke must find on the screen.

## Decision Ledger

| ID  | Decision | Resolution | Provenance | Kind |
| --- | -------- | ---------- | ---------- | ---- |
| D-1 | Empty-state copy for the import list | "Nothing imported yet", per the frame | user-answered | intent |

## Open Regions

No open regions — every decision in scope is ratified.

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | Empty state when the user has imported nothing yet | decided (D-1) |

## Checks

No ticket-specific checks — the configured lanes cover this change.

## Design frames

| RS | route | state | frame | must-show |
| --- | --- | --- | --- | --- |
| RS-1 | /imports | empty | 815:2201 | Nothing imported yet |
| RS-2 | /imports | loaded | 815:2240 | data-test=import-row |

## Implementation steps

1. Step one.
