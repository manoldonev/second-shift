# Decision record — #8378 loop varible is undefined in inline anonymous function in template

## Summary

The identifier walk that prefixes template expressions treats the variables a `for...of` loop
declares as local inside the loop, as it already does for function parameters and block
declarations, so an inline handler that loops over a list reads its loop variable instead of a
missing `_ctx` property.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Where the loop variables are recorded | On the `for...of` statement node, in the same scope count as function parameters and block declarations, so they are dropped again when the walk leaves the loop. | user-answered | intent |
| D-2 | Which loop declarations are covered | A single identifier and an array pattern, element by element. | user-answered | intent |
| D-3 | What the tests cover | `compileTemplate.spec.ts`: an inline arrow-function handler with a plain loop variable and one with an array-destructured loop variable, each checked against a snapshot. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2

AC-1: an inline handler with for (const item of arr) compiles to code that reads item, not _ctx.item
AC-2: an inline handler with for (const [item, index] of Maptype) compiles to code that reads item and index, not _ctx.item or _ctx.index
