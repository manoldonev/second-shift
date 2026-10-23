# Decision record — #2376 `Duration.toISOString()` fractional seconds still have precision issues with certain values

## Summary

`toISOString` adds the milliseconds to the seconds first and rounds the sum to three decimals,
instead of rounding the milliseconds alone.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Where the rounding happens | Once, on the seconds plus the milliseconds, to millisecond precision. | user-answered | intent |
| D-2 | What toISOString may change | Nothing: it reads the duration and computes its string in locals. `$d` is never written, so two calls return the same string. | user-answered | intent |

## Test intent

ACs: AC-1

AC-1: toISOString of the three durations in the AC returns their strings with no floating-point error
