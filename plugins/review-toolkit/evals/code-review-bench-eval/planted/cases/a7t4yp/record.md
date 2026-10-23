# Decision record — #5028 [1.0.0] Set-Cookie header in a response interceptor is not an array anymore

## Summary

`normalizeValue` maps an array header value to an array of strings, and `toJSON` keeps arrays
unless it is asked to join them.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Where arrays are normalized | In `normalizeValue`, recursively, so `set` and `normalize` both keep them. | user-answered | intent |
| D-2 | How toJSON treats arrays | It keeps them by default. `toJSON(true)` joins each array with `, ` for a caller that needs strings. | user-answered | intent |
| D-3 | The public typing | `index.d.ts` declares the new parameter as `toJSON(asStrings?: boolean): RawAxiosHeaders` in this change. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2

AC-1: a local server sets two cookies, and a response interceptor sees them as an array
AC-2: toJSON() of headers built from foo: [1, 2, 3] after normalize() gives foo: ['1', '2', '3']
