# Decision record — #1259 Bug: word wrapping

## Summary

A long repo name no longer runs past the repo card's edge, and a Chinese description wraps at
its punctuation, since it has no spaces to wrap at.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | How long the repo card's header may be | 35 characters, then `...`. | user-answered | intent |
| D-2 | How a Chinese description wraps | It is split at each full-width comma `，`, with the same three-line limit and `...` on the last line. A text with no full-width comma wraps by width as before, at 59 characters. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2

AC-1: a repo card for a 44-character repo name shows its first 35 characters and '...'
AC-2: wrapTextMultiline on a Chinese sentence returns three lines, cut at its commas
