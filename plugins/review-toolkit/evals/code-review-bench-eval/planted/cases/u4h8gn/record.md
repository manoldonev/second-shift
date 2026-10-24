# Decision record — #2055 Changing color of the "ring"/circle around the rank

## Summary

The stats card takes a `ring_color` option for its rank circle. The color resolves through
`getCardColors` like the card's other colors, with the title color as its last fallback.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Where the ring color resolves | In `getCardColors`, next to the other card colors, so a theme can set `ring_color` later. | user-answered | intent |
| D-2 | The fallback order | The query value, then the theme's `ring_color`, then the resolved title color. | user-answered | intent |
| D-3 | Which cards take the option | Only the stats card, which is the only card with a rank circle. | user-answered | intent |
| D-4 | What the tests cover | `getCardColors` in `utils.test.js`, the rendered styles in `renderStatsCard.test.js`, and the api pass-through in `api.test.js`. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2 AC-3

AC-1: a stats card rendered with ring_color 0000ff strokes the rank circle and its rim with #0000ff
AC-2: getCardColors with no ring_color returns the title color as ringColor, for the default theme and for a set title color
AC-3: getCardColors returns the theme's or the title's color as ringColor when the given ring_color is not a hex color
