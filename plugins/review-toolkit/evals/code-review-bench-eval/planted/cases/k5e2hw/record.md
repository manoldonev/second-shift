# Decision record — #888 Duration.toISOString() returns wrong result

## Summary

`toISOString` adds the `T` designator when the duration has hours, minutes or seconds. It
tested the month component `M` instead of the minute component `m`.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | When the T designator is written | When the hour, minute or second component is not empty. | user-answered | intent |
| D-2 | The existing expectations that encode `P1M` and `P5M` | They are wrong and are corrected to `PT1M` and `PT5M` in this change. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2

AC-1: toISOString of a duration of minutes only starts with PT
AC-2: the corrected expectations for 60 seconds and for toJSON of 5 minutes pass
