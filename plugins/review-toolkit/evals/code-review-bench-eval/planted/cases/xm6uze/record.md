# Decision record — #18034 Got wrong url when importing some svg files

## Summary

A small SVG asset is inlined as a data URL in dev too, under the same rules as in build, so the
quoting differences between an SVG file URL and an inlined SVG show up before deploying.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Which assets dev inlines | SVG only. Other asset types keep their file URL in dev. | user-answered | intent |
| D-2 | The rule that decides inlining in dev | The same `shouldInline` as build: `?no-inline` and `?inline`, `.html` never, an SVG with a fragment never, then `build.assetsInlineLimit` as a number or a callback. | user-answered | intent |
| D-3 | Build-only inline rules | Library mode always inlining, and an entry never inlining, apply only when a build plugin context is passed. | user-answered | intent |
| D-4 | HMR for an inlined asset | No `?t=` query is added to a data URL; the new content already gives a new URL. | user-answered | intent |
| D-5 | Reading build config in dev | Accepted as an exception, since the point is to match the built output. | user-answered | intent |
| D-6 | What the tests cover | The assets playground: CSS `url()` and `image-set()` with SVG, a JS SVG import with a fragment. The hmr and hmr-ssr playgrounds: an inlined and a not-inlined SVG edited in dev. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2 AC-3 AC-4

AC-1: the css-url-svg and css-image-set-svg backgrounds are data:image/svg+xml URLs in dev and in build
AC-2: the svg-frag-import image src is a data:image/svg+xml URL ending in #icon-heart-view
AC-3: after editing logo.svg the module runner's logo value is a different data:image/svg+xml URL
AC-4: after editing logo-no-inline.svg the image updates to height 40 and the runner's URL contains logo-no-inline.svg?t=
