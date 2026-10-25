# Decision record — #108 Automatic Resizing Fit to Content

## Summary

When the rank is hidden, the stats card shrinks to the width of its title. The title is measured
with a table of average character widths, since the card is rendered on a server with no font
metrics.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | How the title is measured | `measureText` in `src/common/utils.js` sums a per-character width table at 10 px and the card doubles it for the 18 px header. Characters outside the table take the table's average. | user-answered | intent |
| D-2 | Which title sets the width | The title the card shows: the custom title when one is given, else the card's default title. | user-answered | intent |
| D-3 | The bounds of the width | 50 px of padding on top of the title, and at least 270 px, so the stat lines keep their room. | user-answered | intent |
| D-4 | Which cards resize | Only the stats card, the one card with a rank circle. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2

AC-1: a card for the test user with hide_rank renders 305.8 px wide, its title's width plus the padding
AC-2: a card with hide_rank and the custom title "Hello world" renders at the 270 px minimum
