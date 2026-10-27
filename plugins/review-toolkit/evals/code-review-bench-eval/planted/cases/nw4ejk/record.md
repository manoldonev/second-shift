# Decision record — #14654 HMR re-transforms every importer of a changed module

## Summary

An importer that statically imports a changed module is soft-invalidated: its previous transform
result is kept, and its next request only rewrites the import timestamps instead of loading and
transforming the file again.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Which importers may skip the transform | An importer whose code imports the changed module. An importer that only watches it, through a file a plugin added with `addWatchFile`, is invalidated in full as before. | user-answered | intent |
| D-2 | How a watched file is known | `importAnalysis` records the files that plugins added with `addWatchFile` while transforming the module as `pluginWatchedFiles` on the module node; every other imported module is imported by the code. | user-answered | intent |
| D-3 | What a soft-invalidated client module returns | Its previous transform result, with each import of a module that has an HMR timestamp rewritten to carry that timestamp. | user-answered | intent |
| D-4 | What a soft-invalidated SSR module returns | Its previous SSR transform result unchanged, as `ssrLoadModule` controls re-execution. | user-answered | intent |
| D-5 | What the tests cover | The hmr playground: a module edited under an importer that counts its transforms. | user-answered | intent |

## Test intent

ACs: AC-1

AC-1: after child.js changes, the page shows child is updated while soft-invalidation/index.js is still transformed 1 times
