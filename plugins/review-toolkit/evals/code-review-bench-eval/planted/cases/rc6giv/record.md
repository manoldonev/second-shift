# Decision record — #12257 Missing parens for `ClassExpression` with decorators

## Summary

A class expression with decorators always keeps parentheses, so the printed output stays a class
expression instead of turning into a class declaration without a name.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Which class expressions get parentheses | Every `ClassExpression` with decorators, in any position, decided in `needs-parens.js` before the parent-specific rules. | user-answered | intent |
| D-2 | The layout inside the parentheses | The decorators and the class on their own lines, indented one level, with the parentheses on their own lines around them. | user-answered | intent |
| D-3 | The leading semicolon in no-semi mode | Printed before the opening parenthesis, as for any other statement that starts with a parenthesis. | user-answered | intent |
| D-4 | Other decorated nodes | Unchanged: a decorated declaration still prints its decorators before it and never gets parentheses. | user-answered | intent |
| D-5 | What the tests cover | `tests/format/js/decorators/class-expression/` with and without semicolons, and `4.ts` in `type-arguments-bit-shift-left-like` for babel-ts. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2 AC-3

AC-1: formatting a decorated class expression as a statement, an initializer, an argument, a member object and a superclass keeps the parentheses and puts the decorators and class on indented lines
AC-2: formatting the same fixtures with semi false prints a semicolon before the parenthesis of a statement that starts with a decorated class expression
AC-3: formatting the bit-shift-like decorated class expression with babel-ts keeps its parentheses
