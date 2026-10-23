# Decision record — #1022 RelativeTime plugin bug while using BadMutable plugin

## Summary

`monthDiff` adds months to a clone of its first argument, so with badMutable loaded it no longer
moves that instance, and `diff` and `fromNow` return the right value.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Where the clone happens | In `monthDiff`, for both anchors, so every caller of `Utils.m` is safe. | user-answered | intent |
| D-2 | The test | In `test/plugin/badMutable.test.js`, a year diff compared with Moment.js's. | user-answered | intent |

## Test intent

ACs: AC-1

AC-1: with badMutable, a year diff between an instance and its clone plus a year is -1, as in Moment.js
