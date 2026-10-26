# Decision record — #14654 HMR re-transforms every importer of a changed module

## Summary

An importer that statically imports a changed module is soft-invalidated: its previous transform
result is kept, and its next request only rewrites the import timestamps instead of loading and
transforming the file again.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Which importers may skip the transform | Only an importer whose code statically imports the changed module. An importer that depends on it any other way, such as a watched file, is invalidated in full as before. | user-answered | intent |
| D-2 | How a static import is known | `importAnalysis` records the urls of the module's static and dynamic imports as `staticImportedUrls` on the module node, apart from the imported modules that also hold watched files. | user-answered | intent |
| D-3 | What a soft-invalidated client module returns | Its previous transform result, with each import of a module that has an HMR timestamp rewritten to carry that timestamp. | user-answered | intent |
| D-4 | What a soft-invalidated SSR module returns | Its previous SSR transform result unchanged, as `ssrLoadModule` controls re-execution. | user-answered | intent |
| D-5 | What the tests cover | The hmr playground: a module edited under an importer that counts its transforms. | user-answered | intent |

## Test intent

ACs: AC-1

AC-1: after child.js changes, the page shows child is updated while soft-invalidation/index.js is still transformed 1 times
