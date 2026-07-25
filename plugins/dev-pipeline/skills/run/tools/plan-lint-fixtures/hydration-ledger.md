# Decision Ledger — acme-9998

Backing ledger fixture for plan-lint Check 6 hydration cases. Resolved as the sibling
of `hydration.json` (`dirname(state)/$(basename state .json)-ledger.md`).

Each row is authored for one hydration case:

- `D-1` carries markdown emphasis in its Resolution cell.
- `D-2` carries a multi-word Resolution, for the internal-whitespace case.
- `D-3` carries an identifier with exactly ONE underscore. Paired emphasis folding has
  nothing to pair it with, so it must survive normalization unchanged — a lone
  underscore swapped for an asterisk is a real difference, not a formatting one.
- `D-4` carries BOLD emphasis. `norm_cell()` folds bold (`__x__`) and italic (`_x_`)
  through two separate rules, so D-1 alone would leave the bold rule unexercised.

| ID  | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Serialization shape for the import payload | return a bare *object*, never an array | codebase-derived |
| D-2 | Retry budget for the import worker | three attempts with exponential backoff | codebase-derived |
| D-3 | Naming convention for the new helper | use snake_case to match the sibling tools | codebase-derived |
| D-4 | Behavior on a duplicate import id | reject it as **conflict**, do not overwrite | codebase-derived |
