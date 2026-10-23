# Decision record — #3869 Views: custom cache key support

## Summary

`app.render` (and so `res.render`) takes a `cacheKey` option. When the view cache is on, the
view is cached and looked up under that key instead of the view name.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Where the key comes from | `renderOptions.cacheKey`, after the app locals, `_locals` and the call's options are merged. | user-answered | intent |
| D-2 | The default key | The view name, so a render without `cacheKey` behaves as before. | user-answered | intent |
| D-3 | The caching tests | The existing caching tests and the new cacheKey tests share one `createAppForCaching(cache)` helper that counts view lookups on `app.count`. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2 AC-3

AC-1: two cached renders with different keys count two view lookups
AC-2: two cached renders with the same key count one view lookup
AC-3: the existing caching tests pass on the shared helper with their counts unchanged
