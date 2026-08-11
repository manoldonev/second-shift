# Intake receipt: PROJ-9999 — Fixture receipt for ledger-lint receipt mode

## Context

Fixture. Exercises a well-formed INTAKE receipt: every Kind value, every legal
Kind/provenance pairing, an `open` row mapped to a declared region, and a surface
inventory carrying both dispositions.

## Decision Ledger

| ID  | Decision | Resolution | Provenance | Kind |
| --- | -------- | ---------- | ---------- | ---- |
| D-1 | Uniqueness of document fingerprint per user | Partial unique index on (userId, fingerprint) | user-answered | intent |
| D-2 | 404 vs 409 on duplicate import (shows A \| B) | 409 | user-delegated | intent |
| D-3 | DTO validation library | class-validator (repo convention, CLAUDE.md) | codebase-derived | fact |
| D-4 | Max upload size for a single import | 50 MB, per the operator's comment https://example.invalid/tracker/PROJ-9999#comment-7 | ticket-sourced | fact |
| D-5 | Backfill ordering across historical records | parked under OR-1 (owner: reporter, before the next milestone) | deferred | open |

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | Ordering guarantees for the historical backfill | pause-and-ask |
| OR-2 | Retention window for import audit rows | reversible-default-and-flag |

OR-2's reversible default: 90 days, matching the neighboring audit table; flagged on
the PR so the operator can widen it without a migration.

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | First paint while the import list is still loading | decided (D-1) |
| S-2 | Empty state when the user has imported nothing yet | decided (D-2) |
| S-3 | Print stylesheet for the import report | out-of-scope — nothing in this ticket is printed |

## Implementation steps

1. Step one.
