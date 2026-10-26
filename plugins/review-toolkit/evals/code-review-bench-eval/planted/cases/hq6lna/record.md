# Decision record — #13400 Calling print() on a property that is not a child node is not always caught

## Summary

The non-node check moves out of the language printers into the core print loop, runs for every
printer before the empty-value return, and is a no-op in a production build.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Where the check runs | Once, in `mainPrintInternal` in `src/main/ast-to-doc.js`, before the `undefined`/`null` return; the per-language copies are removed. | user-answered | intent |
| D-2 | Which keys the check allows | The printer's `getVisitorKeys`, or the node's own keys minus the non-traversable ones when the printer has none. | user-answered | intent |
| D-3 | Which node holds the printed property | Read from the path stack, since `path.getParentNode()` skips a missing value. | codebase | implementation |
| D-4 | Production builds | The check is a no-op when `process.env.NODE_ENV` is `production`. | user-answered | intent |
| D-5 | Printers that called print() on keys their nodes lack | Fixed at the call: GraphQL descriptions are printed only when present, and a TypeScript abstract class property passes no value key to `printAssignment`. | user-answered | intent |
| D-6 | What the tests cover | `print-pre-check.js`: an inline plugin printer over a child key, a string property, a missing non-child key, a missing child key and no `getVisitorKeys`; TypeScript abstract properties and GraphQL definitions format unchanged. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2 AC-3

AC-1: print() on a string property or a missing non-child key rejects with the non-node error, also for a printer without getVisitorKeys
AC-2: print() on a missing child key prints nothing
AC-3: TypeScript abstract class properties and GraphQL definitions and extensions format unchanged
