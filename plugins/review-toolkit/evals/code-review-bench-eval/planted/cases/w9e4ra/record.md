# Decision record — #915 CustomParseFormat: Issue with parsing dates in 'D-MM-YYYY' format

## Summary

customParseFormat numbers a parsed month name from 1, so `MMM` and `MMMM` parse December as
month 12 instead of falling back to the current month.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | How a month name becomes a month number | Its 1-based position in the locale's `monthsShort` or `months`, so December is 12. | user-answered | intent |
| D-2 | A month name the locale does not know | Still an invalid date, as before. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2

AC-1: '21-Dec-18' with D-MMM-YY parses to the same time as Moment.js
AC-2: '21-December-18' with D-MMMM-YY parses to the same time as Moment.js
