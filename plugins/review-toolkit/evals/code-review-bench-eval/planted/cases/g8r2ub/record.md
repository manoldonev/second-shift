# Decision record — #1650 Add pie chart style to language card

## Summary

The top languages card gets a `donut` layout: a ring of arcs, one per language, beside a compact
legend. The layouts share one function that hides and trims the languages.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | The chart's shape | A donut, drawn as one SVG arc path per language, and a full circle when one language holds 100%. | user-answered | intent |
| D-2 | The layout's name | `layout=donut`, beside `normal` and `compact`. | user-answered | intent |
| D-3 | The legend | The compact layout's language items, one per row beside the donut. | user-answered | intent |
| D-4 | How the card grows | The height is fixed up to five languages and grows by one legend row for each language after that, with the donut kept centred. | user-answered | intent |
| D-5 | What the tests cover | The geometry helpers, the height helpers, the trimming, and the donut render of the shared test languages. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2 AC-3

AC-1: a donut card for the test languages renders one arc per language, each sized by the language's percent, and a legend that names each percent
AC-2: the donut card's arcs and legend for the test languages come out in the same order
AC-3: the donut height and the donut centre follow the number of languages, for zero to ten languages
