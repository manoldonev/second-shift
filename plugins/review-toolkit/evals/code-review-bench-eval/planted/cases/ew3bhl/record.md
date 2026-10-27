# Decision record — #6741 Vite inlines icon resources that should not be inlined

## Summary

Icon and manifest `<link>` references in HTML are always emitted as files in a build. The HTML
plugin tells the asset code not to inline them; every other reference keeps the existing inline
rules.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Which link rels stay files | `icon`, `apple-touch-icon`, `apple-touch-startup-image` and `manifest`. Obsolete rels (`shortcut`, `mask-icon`, `apple-touch-icon-precomposed`) get no entry of their own. | user-answered | intent |
| D-2 | How the HTML plugin overrides inlining | An optional `shouldInline` argument on `urlToBuiltUrl` and `fileToBuiltUrl`: `false` forces a file, leaving it out keeps the size-based heuristics. | user-answered | intent |
| D-3 | Lib mode | Unchanged: with no `shouldInline`, lib builds still inline every asset. | user-answered | intent |
| D-4 | What the tests cover | The assets playground: the icon, apple-touch-icon and manifest links build to hashed files under `assets/`. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2

AC-1: the icon and apple-touch-icon links of the assets playground have hashed assets/favicon href values in build
AC-2: the manifest link of the assets playground has a hashed assets/manifest href in build
