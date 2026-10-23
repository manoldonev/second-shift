# Decision record — #1745 .format('YYYY') returns less than 4 digits for years < 1000

## Summary

`YYYY` pads the year to four digits with zeros, as Moment.js does. `YY` keeps its behavior.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | How YYYY pads | With zeros, to four digits, through the core's `Utils.s` helper. | user-answered | intent |
| D-2 | What the tests compare with | Moment.js's output for the same input, in the existing `Format Year YY YYYY` test. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2

AC-1: a three-digit year formatted with YYYY returns four digits, as Moment.js does
AC-2: a three-digit year formatted with YY returns its last two digits, as Moment.js does
