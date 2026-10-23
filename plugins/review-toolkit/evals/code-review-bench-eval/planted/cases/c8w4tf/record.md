# Decision record — #2095 `dayjs(null)` throws error, not return dayjs object as invalid date

## Summary

objectSupport no longer reads `constructor` of `null`, so `dayjs(null)` with the plugin returns
the invalid date that the core returns without it.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | What dayjs(null) returns with objectSupport | An invalid date, the same as the core without the plugin. | user-answered | intent |
| D-2 | What the tests cover | `dayjs(null)` and `dayjs()` with objectSupport loaded, in `test/plugin/objectSupport.test.js`. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2

AC-1: dayjs(null).isValid() is false with objectSupport loaded
AC-2: dayjs().isValid() is true with objectSupport loaded
