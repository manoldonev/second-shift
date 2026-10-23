# Decision record — #1304 gggg not working correctly

## Summary

`weekYear()` returns the previous year for a day in January whose week is week 52 or 53, as it
already returned the next year for a day in December whose week is week 1.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | The rule | In January, a week of 52 or more belongs to the previous year. | user-answered | intent |
| D-2 | What the new test compares with | Moment.js's `weekYear()` for the same day and locale, beside a fixed expected year. | user-answered | intent |

## Test intent

ACs: AC-1

AC-1: weekYear of the days from 2020-12-31 to 2021-01-05 in en-gb returns the year Moment.js returns
