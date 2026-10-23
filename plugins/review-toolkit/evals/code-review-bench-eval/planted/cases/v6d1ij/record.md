# Decision record — #865 dayjs.duration(x.diff(y)) 后获取seconds()返回大于59

## Summary

A duration built from milliseconds stores whole seconds and the remaining milliseconds apart,
and each getter returns its stored component.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | How milliseconds are split | Whole seconds into `$d.seconds`, the rest into `$d.milliseconds`. | user-answered | intent |
| D-2 | What each getter returns | Its stored component; `weeks()` keeps computing whole weeks, and `milliseconds()` keeps the milliseconds within the second. | user-answered | intent |

## Test intent

ACs: AC-1

AC-1: for 61000 ms, seconds() returns 1 and minutes() returns 1
