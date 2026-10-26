# Decision record — #2173 Add build.assetInlineExclude config

## Summary

`build.assetsInlineLimit` accepts a callback next to the number form, so a project can opt single
assets in or out of inlining by file path or content while every other asset keeps the size limit.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Shape of the option | `build.assetsInlineLimit` takes a number or a `(filePath, content) => boolean \| undefined` callback; no separate exclude list is added. | user-answered | intent |
| D-2 | What the callback can override | Everything but lib mode, which still inlines every asset; a `true` or `false` from the callback wins over the built-in html and svg-fragment exclusions. | user-answered | intent |
| D-3 | A callback that returns nothing | The default 4096-byte limit applies, with the usual html, svg-fragment and Git LFS exclusions. | user-answered | intent |
| D-4 | Where the default limit lives | One shared `DEFAULT_ASSETS_INLINE_LIMIT` constant used by the build defaults and the asset plugin. | codebase | intent |
| D-5 | What the tests cover | The worker playground configs switch from a limit of 100 to a callback that keeps svg files as urls; a build test checks the svg is emitted as a file. | user-answered | intent |

## Test intent

ACs: AC-1

AC-1: in the es worker build, worker_asset-vite.svg is emitted as a file in dist/es/assets while it is under the default limit
