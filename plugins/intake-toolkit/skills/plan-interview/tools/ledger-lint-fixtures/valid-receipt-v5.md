# Intake receipt: PROJ-9999 — Fixture receipt for ledger-lint receipt mode, v5

Receipt: v5

## Context

Fixture. Exercises a well-formed v5 INTAKE receipt: the v4 sections, and a Fan-out section in the
v5 form. It has no `Refuter:` line. Each finding that became a row is linked from that row with
`From: F-n`, one finding became two rows, and the tally agrees with the rows: three rows added, one
snapshot claim overturned, two questions added. A finding the session already had names its row
with no link, and a finding whose check failed is set aside as not material.

## Intake steps

Requirements: the ticket body as written — spec-reviewer: implementable
Split: not split — one PR's worth of work
Explore: done — the import worker, its DTOs and the proxy config
Fan-out: ran — 4 items, see Fan-out
Dup-scan: no candidates at or above threshold 12
Post-merge scan: no post-merge AC
Sizing: opus

## Decision Ledger

| ID  | Decision | Resolution | Provenance | Kind |
| --- | -------- | ---------- | ---------- | ---- |
| D-1 | Import retry on 409 | No retry on 409. run: `grep -n "retry" worker.ts` → 88: retries every status. From: F-1 | user-answered | intent |
| D-2 | 404 vs 409 on duplicate import (shows A \| B) | 409. From: F-1 | user-delegated | intent |
| D-3 | DTO validation library | class-validator; nested arrays need `@Type` — run: `grep -n "@Type" src/dto.ts` → 30: absent. From: F-3 | codebase-derived | fact |
| D-4 | Max upload size for a single import | 50 MB, per the operator's comment https://example.invalid/tracker/PROJ-9999#comment-7 | ticket-sourced | fact |
| D-5 | Backfill ordering across historical records | parked under OR-1 (owner: reporter, before the next milestone) | deferred | open |
| D-6 | Import audit rows are retained, never purged on import | retained — cited (kb): <kb-page> | codebase-derived | fact |

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | Ordering guarantees for the historical backfill | pause-and-ask |

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | First paint while the import list is still loading | decided (D-1) |
| S-2 | Print stylesheet for the import report | out-of-scope — nothing in this ticket is printed |

## Checks

- `bash scripts/import-selftest.sh`

## Fan-out

Lenses: retry-semantics opus 3 · storage-limits opus 2 · validation opus 4 · list-views opus failed · premortem opus 1
Tally: rows added 3 · snapshot claims overturned 1 · questions added 2 (D-1, D-2)

| ID | Angle | Claim | Tag | Disposition |
| --- | --- | --- | --- | --- |
| F-1 | retry-semantics | The import worker retries a 409 forever (`worker.ts:88`) | new | became D-1, D-2 |
| F-2 | storage-limits | Uploads above 50 MB are already rejected at the proxy (`nginx.conf:12`) | already-had | already had — D-4 |
| F-3 | validation | class-validator rejects nested arrays without `@Type` (`dto.ts:30`) | overturned (snapshot: "nested arrays validate as-is") | became D-3 |
| F-4 | premortem | The admin list sorts client-side (`list.ts:40`) | not material | not used — did not hold: the server sorts it (`list.ts:12`) |

### Snapshot

    | ID | Decision | Resolution |
    | --- | --- | --- |
    | D-3 | DTO validation library | class-validator; nested arrays validate as-is |

    Facts held: the proxy caps uploads at 50 MB (ticket body).

## Knowledge source

Knowledge source: none declared

## Test intent

ACs: AC-1 AC-2

AC-1: a second import of the same document by one user answers 409 and writes no row
AC-2: exempt — the README's import section is prose; no test can prove it
