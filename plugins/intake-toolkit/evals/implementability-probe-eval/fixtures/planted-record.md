# Decision record — machine-readable output for ledger-lint

Receipt: v4

## Summary

`ledger-lint.sh` gains a `--json` flag that reports the lint result as JSON.

Open regions: none.

Provenance legend: `user-answered` = the operator chose. `user-delegated` = the operator gave the choice to the agent. `codebase-derived` = a fact from the code or the docs, with its proof.

## Decision Ledger

| ID | Kind | Decision | Resolution | Provenance |
| --- | --- | --- | --- | --- |
| D-1 | intent | Where does `--json` output go? | To stdout. Prose violations keep going to stderr. | user-answered |
| D-2 | intent | What does a clean ledger print under `--json`? | Nothing, with exit 0. The operator said "your call"; the agent chose silence over an empty JSON object. | user-delegated |
| D-3 | intent | Shape of a violation | JSON-encoded. | user-answered |
| D-4 | fact | Is `jq` available? | Yes, it is a repo prerequisite. cited (convention): CLAUDE.md:1 | codebase-derived |

Options weighed:
- D-1: stdout or stderr. The operator chose stdout.
- D-2: an empty object or no output. The agent chose no output, under the operator's "your call".
- D-3: an object per violation or a string per violation. The operator chose JSON-encoded.

## Open Regions

none

## Test intent

ACs: AC-1 AC-2
AC-1: under `--json`, a clean ledger prints nothing and exits 0.
AC-2: under `--json`, the output reports the number of violations.

## Surface Inventory

| Surface | State |
| --- | --- |
| `ledger-lint.sh --json` | decided (D-1) |
