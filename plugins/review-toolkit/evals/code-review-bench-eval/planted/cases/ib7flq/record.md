# Decision record — #15284 Prettier formatting is inconsistent when using escaping in string

## Summary

When the right side of an assignment is a call with a lone string argument, the string is
measured by its printed form, after quote normalization drops unnecessary escapes, so a string
with an unnecessary escape and the same string without it get the same layout, and a second
format no longer changes the output.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | How a lone string argument is measured | By the string `printString` would print for it under the current options, not by its source text. | user-answered | intent |
| D-2 | Where the measurement lives | In `isLoneShortArgument`, which receives the formatting options for it. | user-answered | intent |
| D-3 | What the tests cover | `tests/format/js/strings/escaped.js`: the declaration with and without the escape, under the babel and flow parsers, for trailingComma `all` and `es5`. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2

AC-1: escaped.js prints both declarations as a break after = with goog.getMsg("That's all we know") on the next line
AC-2: escaped.js output is stable on a second format under trailingComma all and es5
