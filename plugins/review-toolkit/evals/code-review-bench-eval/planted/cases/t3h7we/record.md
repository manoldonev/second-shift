# Decision record — #51 All stats card and repo features are down. Error cannot fetch user is shown on all cards including your readme #bug

## Summary

The cards send their GitHub queries through a retryer that rotates over several personal access
tokens, so one rate-limited token no longer takes every card down.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Where the tokens come from | Environment variables `PAT_1` to `PAT_8`, tried in order. | user-answered | intent |
| D-2 | When the next token is tried | On a `RATE_LIMITED` GraphQL error, and on a "Bad credentials" response. | user-answered | intent |
| D-3 | How a request gets its token | The fetcher passes it to `request` as an `Authorization` header, so `request` reads no environment variable. | user-answered | intent |
| D-4 | The cards' cache | Both endpoints send `Cache-Control: public, max-age=1800`, to spend fewer requests. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2 AC-3

AC-1: the retryer returns the second token's response after the first is rate limited, and throws "Maximum retries exceeded" after eight rate-limited tries
AC-2: fetchStats rejects with GitHub's own error message
AC-3: fetchRepo returns the second token's response after the first is rate limited
