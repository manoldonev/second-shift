# Decision record — #14312 Caret in on-screen error output points to the wrong line

## Summary

`generateCodeFrame` puts the caret on the line and column of the position it is given, for a
numeric offset and for a line/column position, and accepts an end position so that errors and
warnings that know their range underline all of it.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Where the fix lands | In `generateCodeFrame` itself: a line's newline is counted after the start check, so an offset at column 0 belongs to its own line and the caret pad needs no correction. | user-answered | intent |
| D-2 | The shape of the end argument | `end` takes a numeric offset or a line/column position, like `start`; with no `end` the frame shows a single caret. | user-answered | intent |
| D-3 | Which callers pass a range | postcss warnings pass their end line and column, parse5 errors their end offset, and the dynamic import warning its end offset. | user-answered | intent |
| D-4 | The esbuild message frame | `prettifyMessage` passes the esbuild message location instead of computing an offset by hand. | user-answered | intent |
| D-5 | What the tests cover | Snapshots in `utils.spec.ts` of a numeric and a line/column start, a CRLF source, an end on one line and across lines, and a frame in a longer source. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2 AC-3

AC-1: generateCodeFrame with offset 24 or with line 2 column 0 puts the caret under the first character of line 2, and offset 1 puts it under the second character of line 1
AC-2: generateCodeFrame on a CRLF source with line 2 column 0 puts the caret under line 2
AC-3: generateCodeFrame with start 0 and end 29 underlines all of line 1 and line 2
