# Decision record — #244 dayjs() instanceof dayjs = false

## Summary

The `dayjs` factory's `prototype` is set to the `Dayjs` class's prototype, so `instanceof dayjs`
holds for every instance. The API reference documents it.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | How instanceof is made to work | Assign `Dayjs.prototype` to `dayjs.prototype` after the class. | user-answered | intent |
| D-2 | Where the tests live | A new `test/constructor.test.js`, with `MockDate` set around each test as the other suites do. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2 AC-3

AC-1: dayjs() instanceof dayjs is true
AC-2: dayjs.isDayjs(dayjs()) is true
AC-3: exempt — docs only
