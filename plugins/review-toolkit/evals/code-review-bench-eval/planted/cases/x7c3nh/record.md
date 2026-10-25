# Decision record — #1038 [Bug] wakatime langs_count  is invalid when layout=compact

## Summary

The compact WakaTime layout honors `langs_count`. Both layouts render from one list of languages,
filtered to the ones with activity and cut to `langs_count`.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Where the languages are cut | Once, before either layout renders: languages with no hours and no minutes are dropped, then the list is cut to `langs_count`. | user-answered | intent |
| D-2 | How the compact card is sized | Its height follows the number of kept languages, two to a legend row. | user-answered | intent |
| D-3 | What the tests cover | The existing compact layout test of `renderWakatimeCard`. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2

AC-1: the compact card for the test data renders only the languages with activity, in the bar and in the legend
AC-2: the compact card's bar segments for the test data cover the width of the bar
