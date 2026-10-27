# Decision record — #3368 Linebreaks weirdly in long ES6 template strings with expressions

## Summary

An interpolation in a template literal is split across lines only when its `${...}` already holds
a line break in the source, or when printing it at unlimited width still gives one, for example a
nested function. Otherwise it stays on its line, however long the literal is, the same way an
object is kept on one line unless its source breaks after the `{`.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | When an interpolation may break | Only when the source between the end of the quasi before it and the start of the quasi after it holds a line break, or when the interpolation printed at unlimited width still holds one. | user-answered | intent |
| D-2 | What happens to an interpolation that may not break | It is printed at unlimited width and inserted as a string, and the break at `${` and `}` for member, conditional, sequence, cast and binary expressions is not added. | user-answered | intent |
| D-3 | Simple template literals | Unchanged: they keep the existing simple-literal path. | codebase | intent |
| D-4 | Where the rule lives | In the template literal printer, applied to each interpolation of a literal that is not simple. | user-answered | intent |
| D-5 | Docs | A `Template literals` section in `docs/rationale.md` explains the heuristic, plus a changelog entry. | user-answered | intent |
| D-6 | What the tests cover | `tests/format/js/strings/template-literals.js`: a long message with one interpolation and a template with one interpolation that has a line break and one that does not; the existing template literal, JSX, satisfies, `as` and Vue snapshots move to the one-line form. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2

AC-1: template-literals.js prints the long message with ${format(data)} on one line past the print width
AC-2: template-literals.js keeps ${this(one)} on its line and breaks the interpolation whose source already had a line break
