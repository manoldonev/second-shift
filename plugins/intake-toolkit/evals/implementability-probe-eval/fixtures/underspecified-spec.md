# Machine-readable output for ledger-lint

## Goal

CI and the intake tooling both shell out to `ledger-lint.sh` and scrape its stderr to find out
what failed. Scraping human prose is brittle — a reworded violation message breaks a caller that
was never touched. Give the lint a machine-readable mode.

## Scope

### In

- A `--json` flag on `ledger-lint.sh` that emits the lint result as JSON.
- Every violation the lint can currently report is representable in that output.

### Out

- Changing which conditions are violations.
- Any other lint in the repo.

## Behavior

When `--json` is passed, `ledger-lint.sh` emits JSON describing the run: the number of ledger
rows it parsed, and the violations it found. Each violation carries enough for a caller to act
on it without reading English.

The existing behavior is unchanged when the flag is absent.

## Acceptance Criteria

- AC-1: WHEN `--json` is passed and the ledger is clean THEN the output parses as JSON and
  reports zero violations.
- AC-2: WHEN `--json` is passed and the ledger has violations THEN each violation appears in the
  output.
- AC-3: WHEN `--json` is absent THEN output is byte-identical to today's.

## Dependencies

`jq` is already a repo prerequisite.

## Deferred

Adopting the new mode in CI. This issue ships the flag; the callers migrate separately.
