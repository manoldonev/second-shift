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

## Checks

- `bash scripts/import-selftest.sh`
- yarn test --filter import

## Fan-out

Refuter: cross (opus/fable alternating)
Lenses: retry-semantics opus 1/4 · storage-limits fable 1/3 · validation opus 1/5 · list-views fable 1/2 · premortem fable 0/3
Tally: rows added 1 · snapshot claims overturned 1 · questions added 1

| ID | Angle | Claim | Tag | Disposition |
| --- | --- | --- | --- | --- |
| F-1 | retry-semantics | The import worker retries a 409 forever (`worker.ts:88`, observed in a bounded probe) | new | became D-1 |
| F-2 | storage-limits | Uploads above 50 MB are already rejected at the proxy (`nginx.conf:12`) | already-had | already D-4 |
| F-3 | validation | class-validator rejects nested arrays without `@Type` (`dto.ts:30`) | overturned (snapshot: "nested arrays validate as-is") | became D-3 |
| F-4 | list-views | The admin list sorts client-side | not material | not material — the list is capped at 50 rows |

### Snapshot

    | ID | Decision | Resolution |
    | --- | --- | --- |
    | D-1 | Rate limit for the import endpoint | 100/min |
    | D-3 | DTO validation library | class-validator; nested arrays validate as-is |

## Implementation steps

1. Step one.
