# Decision record — #13157 Line breaks in multiline strings aren't replaced with `literalline` and confuse `fits`

## Summary

A string literal with escaped line breaks is printed with its line breaks as literal lines, so the
doc printer measures only its first line and a two-line string is laid out like a three-line one.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | How a line break inside a printed string reaches the doc printer | As a literal line, so the string's continuation lines keep their content and column and only the first line counts toward the width. | user-answered | intent |
| D-2 | Where the conversion lives | In `printString`, the one function that prints a JavaScript string literal and a Flow or TypeScript string literal type, so the three share one path. | user-answered | intent |
| D-3 | The changelog entry | One entry under `changelog_unreleased/javascript/` with the input, the stable output and the new output from the report. | user-answered | intent |
| D-4 | What the tests cover | `tests/format/js/strings/multiline-literal.js` with babel and flow, under the default and `trailingComma: "all"`; `tests/format/flow/literal/multiline.js`; `tests/format/typescript/literal/multiline.ts`. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2

AC-1: formatting const declarations whose string literal spans two and three lines with escaped line breaks puts both strings on their own line after the equals sign, with the continuation lines unchanged
AC-2: formatting Flow and TypeScript type aliases whose string literal type has escaped line breaks keeps the string content, and the Flow ones break after the equals sign for two and three lines
