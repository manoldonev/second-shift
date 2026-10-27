# Decision record — #15282 Prettier prints a trailing comma after type argument list even if the languages is `ts` in markdown

## Summary

The trailing comma after the lone type parameter of an arrow function, as in `<T,>() => {}`, is
kept only where the code may be TSX, so a `ts` or `typescript` code block in Markdown prints
`<T>() => {}` and a `tsx` block keeps the comma.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | When the comma after a lone type parameter is kept | Wherever the code may be TSX, since `<T>() =>` reads as a JSX tag there; not in TypeScript that cannot hold JSX. | user-answered | intent |
| D-2 | Where the choice is made | In `shouldForceTrailingComma` in `src/language-js/print/type-parameters.js`, which already makes it; the Markdown embed is not changed. | user-answered | intent |
| D-3 | What the tests cover | `tests/format/markdown/code/ts-trailing-comma.md`: one `ts`, one `typescript` and one `tsx` block with the same arrow function. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2

AC-1: the ts and typescript blocks of ts-trailing-comma.md print <T>(value: T) => {} without the comma
AC-2: the tsx block of ts-trailing-comma.md and tsx-trailing-comma.md keep <T,>(value: T) => {}
