# Decision record — #1261 Extra pins tab has the language overlapping with stars/other stats

## Summary

The repo card lays out its language, stars and forks by their measured widths instead of fixed
offsets, and the compact language card places its second column after its longest name.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | How the repo card places its bottom row | The language, the stars and the forks sit in one row laid out by `flexLayout`: each item starts after the measured widths of the items before it, plus a 25 px gap. | user-answered | intent |
| D-2 | How `flexLayout` learns the widths | An optional `sizes` array, one width per item, in item order. A caller that passes no sizes keeps the old even spacing. | user-answered | intent |
| D-3 | How the compact language card splits its names | Two columns of half the languages each. The second column starts 20 px after the longest name in the first, and at least 150 px from the left. | user-answered | intent |
| D-4 | What the tests cover | `flexLayout` gets its own test file, `tests/flexLayout.test.js`. The repo card test of the fixed star offset goes, since the offset is gone. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2

AC-1: flexLayout with sizes places each item after the sizes and gaps of the items before it
AC-2: flexLayout with a gap and no sizes places the second item at that gap
