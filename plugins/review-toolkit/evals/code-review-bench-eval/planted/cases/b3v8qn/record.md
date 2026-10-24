# Decision record — #9916 Unexpected reactivity watching shallowReactive array

## Summary

`watch` accepts a number for its `deep` option as the depth to watch, and a `shallowReactive`
source is watched at its root level only, as its reactivity is.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | What a number in `deep` means | The depth to traverse: `deep: 1` tracks the source's own properties, `deep: 2` one level below them, and so on. `deep: true` stays unlimited. | user-answered | intent |
| D-2 | How a `shallowReactive` source is watched with no `deep` option | At its root-level properties only, the same as `deep: false` on a reactive source. | user-answered | intent |
| D-3 | The dev warning for a numeric `deep` | Removed, since a number is now a supported value. | user-answered | intent |
| D-4 | What the tests cover | `apiWatch.spec.ts`: a numeric depth on a reactive object, a ref and an array, a `shallowReactive` source, and `deep: false`. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2

AC-1: watch with deep: 2 on a reactive object calls the callback for a change two levels down and not for one three levels down
AC-2: watch on a shallowReactive object calls the callback for a root-level change and not for a nested one
