# Decision record — #18222 `resolve.conditions` not working reliably on custom environment

## Summary

A package's resolved entry cache is keyed by the resolve options that change which entry a lookup
picks, so environments that share the package cache but differ in conditions no longer read each
other's entries.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Where the fix lands | In the package data cache in `packages.ts`: one map per package, keyed by the lookup key and the resolve options, in place of the separate web and node maps. | user-answered | intent |
| D-2 | What the cache key holds | The lookup key joined with webCompatible, isRequire, conditions, extensions and mainFields. | user-answered | intent |
| D-3 | The cost of a longer key | Building the joined key on each lookup is accepted after measuring it on a reproduction. | user-answered | intent |
| D-4 | A browser field that maps a deep import to false | It is stored through `setResolvedCache` under the same key, like every other deep import entry. | user-answered | intent |
| D-5 | What the tests cover | `environment.spec.ts` sets up six environments with `noExternal: true` and checks dev module runner imports, an ssr CSS and JS load, and a build of each environment. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2 AC-3

AC-1: six module runners in one dev server each import @vitejs/test-dep-conditions and get index.default.js, index.worker.js, index.custom1.js, index.custom2.js, index.custom3.js and index.custom3.js
AC-2: ssrLoadModule of entry.css?inline returns the .test-css rule and of entry.js returns index.default.js
AC-3: a build of each of the six environments outputs the same entries as AC-1
