# Decision record — #16889 Regression on decorators + async + jsdoc

## Summary

A comment on its own line between a decorator and a class method is attached to the decorator, so
it is printed after the decorator and before the method's modifiers instead of after `async`.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Which comments move to the decorator | An own-line comment between a decorator and a class member, line or block, becomes a trailing comment of the decorator. | user-answered | intent |
| D-2 | How the handler knows a comment is on its own line | From the placement the comment attachment already computes for every comment (`ownLine`, `endOfLine`, `remaining`), with no new scan of the source text. | user-answered | intent |
| D-3 | Block comments on the same line | Unchanged: a block comment on the decorator's line, or between `async` and the method name, keeps its current attachment. | user-answered | intent |
| D-4 | Where the change lives | `handleMethodNameComments` in `handle-comments.js`, the handler that already moves line comments after a decorator. | user-answered | intent |
| D-5 | What the tests cover | `tests/format/typescript/comments/16889.ts` with the typescript parser: own-line comments before `async`, modifier and generator methods, the same-line and line comment forms, and an undecorated abstract method. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2

AC-1: formatting 16889.ts keeps each own-line block comment after its decorator and before the method's modifiers
AC-2: formatting 16889.ts leaves the line comments, the same-line block comments and the comment before the abstract method where they were
