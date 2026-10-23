# Decision record — #1533 Parsing with Unix Timestamp tokens X/x and strict mode results in Invalid Date

## Summary

customParseFormat reads a format of `X` as seconds and a format of `x` as milliseconds since the
epoch, before it builds the token parser.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | The units | `X` is seconds and may carry a fraction; `x` is milliseconds. | user-answered | intent |
| D-2 | Which formats take the timestamp path | Only a format that is exactly `X` or exactly `x`. Every other format, including one that holds X or x beside other tokens or escaped text, goes through the token parser as before. | user-answered | intent |
| D-3 | What the tests compare with | Moment.js's `valueOf()` for the same input and format. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2

AC-1: parsing '1410715640.579' with 'X' gives Moment.js's valueOf
AC-2: parsing '1410715640579' with 'x' gives Moment.js's valueOf
