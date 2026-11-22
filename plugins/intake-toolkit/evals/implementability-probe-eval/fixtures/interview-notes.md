# Interview notes — machine-readable output for ledger-lint

Working notes of the intake interview. Not part of the handoff.

**Q. A run with violations under `--json`: which exit status?**
Operator: not 1. A caller has to tell "the lint found violations" from "the lint itself broke".
Use exit 7 for "report produced, violations found". Keep 1 for a usage error.

**Q. Does the caller count the violations itself?**
Operator: no. Put the count in a top-level field named `violationTally`, beside the list.

**Q. Is the JSON a stable contract?**
Operator: internal for now. No version key.
