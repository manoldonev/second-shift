# Decision record — #544 UTC Plugin Milliseconds parsing

## Summary

The string parser reads a fraction of a second with any number of digits, so a string with more
than three fraction digits takes the parser's path instead of falling back to `new Date`.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | How many fraction digits the string parser reads | Any number: the last group of `REGEX_PARSE` becomes `(\d+)?`. | user-answered | intent |
| D-2 | A string that ends in `Z` | Unchanged: it still skips `REGEX_PARSE` and goes to `new Date`. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2

AC-1: dayjs.utc of a string with six fraction digits is the instant the same string with a Z gives
AC-2: dayjs of a string with nine fraction digits has Moment.js's value and millisecond
