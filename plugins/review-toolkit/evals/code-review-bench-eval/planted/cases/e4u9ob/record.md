# Decision record — #2364 dayjs add duration returns Invalid Date

## Summary

A duration getter returns 0 for a unit the duration does not hold, so adding a duration to a
Dayjs instance adds 0 for that unit instead of `undefined`.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | What a getter returns for a missing unit | 0, and 0 for -0, never `undefined`. | user-answered | intent |
| D-2 | Where it changes | The duration's `get`, which every unit getter and `add` to a Dayjs instance read. | user-answered | intent |

## Test intent

ACs: AC-1

AC-1: adding a duration of 7 hours and 10 minutes to now equals adding 7 hours and 10 minutes
