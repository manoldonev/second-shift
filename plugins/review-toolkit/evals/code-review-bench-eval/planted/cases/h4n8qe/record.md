# Decision record — #1363 Spanish days and months should be lowercase

## Summary

The Spanish locales write month names in lowercase. Weekday names are lowercase already.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Which locales change | es and its regional variants es-do, es-pr and es-us, so that the variants keep matching es. | user-answered | intent |
| D-2 | Other languages that capitalize month names | Out of this change: pt, ca and the rest keep their month names. | user-answered | intent |

## Test intent

ACs: AC-1

AC-1: the existing es expectations in test/locale.test.js read the month name in lowercase
