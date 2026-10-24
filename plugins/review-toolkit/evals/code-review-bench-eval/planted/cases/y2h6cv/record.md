# Decision record — #1548 [Feature request] Add "Other" to top-lang card

## Summary

A `merge_others` option on the top languages card keeps the card at `langs_count` entries and
turns the last one into `Others`, the sum of every language past the first `langs_count - 1`.
Without the option the card is unchanged.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | How many entries the card shows | `langs_count` in all, the last of them `Others`. | user-answered | intent |
| D-2 | The color of `Others` | `#9E9F9E`, a gray. | user-answered | intent |
| D-3 | The default | Off: a card without the option shows the top `langs_count` languages, as before. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2 AC-3

AC-1: with merge_others and more languages than langs_count, the card shows langs_count - 1 languages and Others
AC-2: with merge_others and no more languages than langs_count, the card shows every language and no Others
AC-3: exempt — docs only
