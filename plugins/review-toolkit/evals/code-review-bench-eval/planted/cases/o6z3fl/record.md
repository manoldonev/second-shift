# Decision record — #1521 Duration format result is not as expected

## Summary

The ISO 8601 duration parser stores 0 for each component the string leaves out, so `format()`
prints zeros where it printed `NaN`.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Where a missing component becomes 0 | In the ISO string parser of the duration plugin, when the regex groups are read. | user-answered | intent |
| D-2 | The fraction of a second | Out of this change: `ss` and `SSS` keep their current output. | user-answered | intent |

## Test intent

ACs: AC-1

AC-1: a duration parsed from 'PT1H' formats every missing component as zeros
