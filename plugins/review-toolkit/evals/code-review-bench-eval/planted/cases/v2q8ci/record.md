# Decision record — #82 [Feature Request] Support custom cache control

## Summary

The stats and pin endpoints take a `cache_seconds` option for their `Cache-Control` header,
clamped so the cache never drops below the current 30 minutes.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | The parameter's name | `cache_seconds`, in seconds, after Shields.IO's `cacheSeconds`. | user-answered | intent |
| D-2 | The bounds | At least 1800 seconds and at most one day, with `clampValue` in `src/utils.js`. | user-answered | intent |
| D-3 | When the header is set | After the fetch succeeds, so an error card is not cached for the requested time. | user-answered | intent |
| D-4 | The pin card's default | Two hours when its stars and forks are both over 1k or both zero, since the card shows no exact count then. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2

AC-1: /api with cache_seconds 2000 sets max-age 2000, and values above one day or below 30 minutes clamp to the bounds
AC-2: /api/pin with cache_seconds 4000 sets max-age 4000
