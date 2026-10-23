# Decision record — #1465 `dayjs.updateLocale` does not support setting `invalidDate` string

## Summary

`format()` of an invalid date returns the locale's `invalidDate` when the locale has one, and
`Invalid Date` otherwise.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | The locale key | `invalidDate`, the key Moment.js reads. | user-answered | intent |
| D-2 | The fallback | `C.INVALID_DATE_STRING`, unchanged, when the locale has no `invalidDate`. | user-answered | intent |

## Test intent

ACs: AC-1

AC-1: after updateLocale with an invalidDate, format() of an invalid date returns it, as Moment.js does
