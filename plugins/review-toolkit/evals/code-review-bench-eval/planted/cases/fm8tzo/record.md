# Decision record — #15617 Query parsing on every module id slows down transforms

## Summary

The plugins that only test for a query flag or read one query value use regexes on the id
instead of parsing the whole query string, and the shared parsing helper is removed.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | How a query flag is detected | A regex per flag that matches it after `?` or `&` and before `&` or the end of the id. | user-answered | intent |
| D-2 | The dev worker script URL | One added query, `worker_file&type=<type>`, and the worker plugin reads the type from that pair. | user-answered | intent |
| D-3 | The glob query a dynamic import produces | The query string as written, with its leading `?`; `import: '*'` stays for `raw`, `url` and `worker`. | user-answered | intent |
| D-4 | The html proxy index in the css-post plugin | Read with a regex, and an id without an index is an error instead of a silent `NaN` key. | user-answered | intent |
| D-5 | The removed helper | `parseRequest` is deleted; worker bundling no longer takes the parsed query. | user-answered | intent |
| D-6 | What the tests cover | The dynamic import vars parse snapshots, and the iife worker playground's sourcemap boundary test. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2

AC-1: the dynamic import vars snapshots show "query":"?raw", "?url" and "?worker" with "import":"*", and "query":"?foo=bar" for another query
AC-2: the dev page requests my-worker.ts?worker_file&type=module and its inline source map has the expected mappings
