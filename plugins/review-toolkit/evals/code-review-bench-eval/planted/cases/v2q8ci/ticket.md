# [Feature Request] Support custom cache control

**Is your feature request related to a problem? Please describe.**

Talking about rate limiter, it is better to have a customizable `cache-control`. E.g. I will use longer cache-control for repo card (extra pin). It is also helpful for people trying to avoid rate limiting.

**Describe the solution you'd like**

Add a parameter `&cache_control=<maxage>`. But the minimum `maxage` should retain `1800` to avoid abusement.

**Additional context**

[Shields.IO](https://shields.io/) has parameter `?cacheSeconds=` support, and they are using `3600s` as default cache-control.

## Acceptance criteria

- AC-1: `cache_seconds` on `/api` sets the stats card's `Cache-Control` max-age, clamped between 1800 and 86400 seconds. Without it, the card caches for 30 minutes.
- AC-2: `cache_seconds` on `/api/pin` sets the pin card's max-age the same way. Without it, a repo whose stars and forks are both over 1k, or both zero, caches for two hours.
