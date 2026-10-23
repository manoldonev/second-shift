# Decision record — #5554 4.19.0 breaks passing new URL() into res.redirect(...)

## Summary

`res.location` converts its argument to a string before the 4.19.0 encoding checks read it, so
a URL instance works again.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Where the value becomes a string | At the start of `res.location`, with `String(url)`. The `'back'` alias still compares the argument itself. | user-answered | intent |
| D-2 | Where the test runs | Only where `URL` is a global, so the suite still runs on old Node versions. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2

AC-1: res.location with a URL instance sets Location to the URL's string
AC-2: exempt — docs only
