# Plan: PROJ-9999 — Fixture plan for ledger-lint selftest

## Context

Fixture. Exercises a well-formed Decision Ledger with every provenance value.

## Decision Ledger

| ID  | Decision | Resolution | Provenance |
| --- | -------- | ---------- | ---------- |
| D-1 | Uniqueness of document fingerprint per user | Partial unique index on (userId, fingerprint) | user-answered |
| D-2 | 404 vs 409 on duplicate import (shows A \| B) | 409 | user-delegated |
| D-3 | DTO validation library | class-validator (repo convention, CLAUDE.md) | codebase-derived |
| D-4 | Backfill ordering across historical records | deferred to next milestone (owner: reporter) | deferred |

## Implementation steps

1. Step one.
