# Decision record — #953 add month will change hour when use utcOffset

## Summary

When `$set` moves the month or the year, it keeps the internal Date of the intermediate
instance. In utcOffset mode that Date carries the offset, so the hour no longer shifts.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | What $set keeps for a month or a year | The intermediate instance's internal Date, with no round trip through the offset-adjusted time. | user-answered | intent |
| D-2 | The immutable test's offset | `d.utcOffset() + 1`, an offset that is never the machine's own. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2 AC-3

AC-1: at offsets +10 and -8, adding 1 and -2 months keeps hour 6
AC-2: at offsets +10 and -8, hour(5) is 5, plus 1 hour is 6, minus 10 hours is 19
AC-3: the immutable test passes with an offset that differs from the local one
