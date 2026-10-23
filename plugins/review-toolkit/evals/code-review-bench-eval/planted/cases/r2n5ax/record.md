# Decision record — #1007 dayjs.duration().humanize() international

## Summary

`dayjs.duration()` passes the global locale to the new duration, and the constructor no longer
defaults the locale to `en`.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Which locale a new duration takes | The global locale at the time `dayjs.duration()` is called. | user-answered | intent |
| D-2 | An instance locale | `.locale('fr')` on a duration still wins over the global locale. | user-answered | intent |

## Test intent

ACs: AC-1

AC-1: after dayjs.locale(en|fr|es), a new duration of one minute humanizes in that locale
