# Decision record — #3105 Accessing env variables from index.html

## Summary

Html files support a `%ENV_NAME%` placeholder that Vite replaces with the value of
`import.meta.env.ENV_NAME`, in dev and in build, before user html hooks run.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | The placeholder syntax | `%ENV_NAME%`, so templating plugins such as `vite-plugin-html` that use `<% %>` keep working. | user-answered | intent |
| D-2 | Which values are available | Every key of `import.meta.env`: the loaded env files, the built-in `MODE`, `BASE_URL`, `PROD` and `DEV`, and `import.meta.env.*` keys set through `define`. | user-answered | intent |
| D-3 | A placeholder with no value | Left as written; a warning is logged when its name starts with an env prefix, since it is likely mistyped. | user-answered | intent |
| D-4 | Where the hook runs | First among the normal html hooks in build, and before the dev html hook in dev. | user-answered | intent |
| D-5 | What the tests cover | The html playground's env.html: a `.env` variable in text and in a class attribute, a `define` key, and `PROD` and `DEV`. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2 AC-3

AC-1: env.html shows bar for %VITE_FOO%, and its class attribute env-%VITE_FOO% becomes env-bar
AC-2: env.html shows 5173 for %VITE_NUMBER% defined as import.meta.env.VITE_NUMBER in define
AC-3: env.html shows true for %PROD% in build and true for %DEV% in dev
