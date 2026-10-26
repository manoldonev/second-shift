# Decision record — #4863 Allow to specify filename of emitted CSS when `build.cssCodeSplit: false`

## Summary

A library build names its single CSS file after the package instead of `style.css`, and a new
`build.lib.cssFileName` option sets the name explicitly.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Where the library CSS file name comes from | `build.lib.cssFileName` first, then `build.lib.fileName` when it is a string, then the package.json `name` with its scope removed. | user-answered | intent |
| D-2 | The CSS file name outside library mode | Unchanged: `style.css`. | user-answered | intent |
| D-3 | A library with no package name and no CSS file name option | The build fails with an error that asks for `build.lib.cssFileName`. | user-answered | intent |
| D-4 | How the html plugin finds the single CSS bundle | The css-post plugin resolves the bundle name once per build and records it for the resolved config, and the html plugin reads it from there instead of matching `style.css`. | user-answered | intent |
| D-5 | Breaking change notes | The new default is listed in the migration guide, and `build.lib.cssFileName` is documented in the build options. | user-answered | intent |
| D-6 | What the tests cover | `css.spec.ts`: the name from package.json, `cssFileName`, a string `fileName` with one and with several entries. The lib playground: single entry, multi entry and code-split builds with CSS. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2 AC-3 AC-4

AC-1: resolveLibCssFilename returns mylib.css for a package named mylib when no cssFileName or string fileName is given
AC-2: resolveLibCssFilename returns style.css when cssFileName is style
AC-3: resolveLibCssFilename returns custom-name.css when fileName is custom-name, for one entry and for an array of entries
AC-4: the lib playground builds emit test-my-lib.css for single and multi entry, and css-entry-1.css and css-entry-2.css with code splitting
