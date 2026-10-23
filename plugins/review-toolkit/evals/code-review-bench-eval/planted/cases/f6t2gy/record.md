# Decision record — #1205 Day.js doesn't parse ISO 8601 timezone offset +NN

## Summary

customParseFormat's `Z` and `ZZ` tokens accept an offset of hours alone (`+09`), beside `+09:00` and
`+0900`. An offset with no minutes counts as zero minutes.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Which offsets the zone tokens read | `+HH`, `+HH:mm` and `+HHmm`, and the same with `-`. | user-answered | intent |
| D-2 | The parse without a format | Out of this change: `dayjs('2020-12-01T20:00:00+00')` with no format keeps its current result. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2

AC-1: '2020-12-01T20:00:00+09' with ZZ parses to 1606820400000, as Moment.js does
AC-2: an offset in the input under a format with no zone token parses as local time, as Moment.js does
