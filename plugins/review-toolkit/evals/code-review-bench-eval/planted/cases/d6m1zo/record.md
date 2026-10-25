# Decision record — #2836 Query parameter `show`

## Summary

The stats card replaces the `show_total_reviews` flag with a `show` list, so later optional stats
join the same parameter instead of adding one flag each.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | The parameter's form | `show`, a comma-separated list read with `parseArray`, like `hide`. | user-answered | intent |
| D-2 | The old flag | `show_total_reviews` is dropped with no alias, since few users have set it yet. | user-answered | intent |
| D-3 | The first item | `reviews`, which shows the total PR reviews line. | user-answered | intent |
| D-4 | What the tests cover | The card rendered with `show` in `renderStatsCard.test.js`, and the endpoint's pass-through in `api.test.js`. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2

AC-1: a stats card rendered with show reviews is one row taller than the default card
AC-2: /api called with show=reviews sends a card that carries the reviews line
