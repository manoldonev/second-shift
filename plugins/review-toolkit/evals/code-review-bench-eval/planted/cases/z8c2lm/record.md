# Decision record — #3696 Add support async handlers

## Summary

A layer whose handler is an async function catches the promise's rejection and passes it to
`next`, on the request path and on the error path.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | How an async handler is detected | `fn.constructor.name === 'AsyncFunction'`. A sync handler that returns a promise is not changed. | user-answered | intent |
| D-2 | The order of the checks in a layer | The existing arity check runs first and keeps skipping a handler of the wrong kind. Only a handler that passes it reaches the async check. | user-answered | intent |
| D-3 | Older Node versions | The tests that build async functions run only where `async` parses, through a `asyncFunctionsSupported()` helper in `test/support/utils.js`. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2

AC-1: a route whose async handler throws reaches the error handler with the error, and skips the next request handler
AC-2: a route whose async error handler throws reaches the next error handler with the new error
