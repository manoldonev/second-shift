# Decision record — #587 quarter() difference from Moment

## Summary

`quarter(n)` sets the month to the same month of quarter n instead of adding `n - 1` quarters
to the current date.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | The month quarter(n) sets | `month % 3 + (n - 1) * 3`, the same position within quarter n. | user-answered | intent |
| D-2 | What the test compares with | Moment.js's `quarter(n)` on a date in the fourth quarter. | user-answered | intent |

## Test intent

ACs: AC-1

AC-1: quarter(3) of 2018-11-25 formats as Moment.js's
