# Decision record — #18395 Resolve conditions that Vite adds on its own cannot be turned off

## Summary

Package `exports` and `imports` resolve through the configured conditions only. The conditions
Vite used to add internally move into the default config values, so a user can remove them.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Which conditions resolution uses | The configured list, plus `import` or `require` and `default`. Nothing else is added internally. | user-answered | intent |
| D-2 | How the mode condition is expressed | A `development\|production` entry that resolves to `production` when `NODE_ENV` is `production` and to `development` otherwise. | user-answered | intent |
| D-3 | The new default lists | Client `['module', 'browser', 'development\|production']`, server `['module', 'node', 'development\|production']`, external `['node']`. | user-answered | intent |
| D-4 | `overrideConditions` and `webCompatible` | Removed. Externalized SSR imports resolve with `externalConditions`, and `process.env` replacement follows a new `keepProcessEnv` option. | user-answered | intent |
| D-5 | `ssr.target: 'webworker'` | Kept working: the ssr environment gets client-like conditions, keeps no `process.env`, and its build output defaults to single-file `[name].js` entries. | user-answered | intent |
| D-6 | Breaking change notes | The migration guide tells users with custom conditions to add the defaults they still want. | user-answered | intent |
| D-7 | What the tests cover | `environment.spec.ts`: ssr, worker and two custom environments, in dev with the dependency inlined and externalized, and in build. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2 AC-3

AC-1: in dev the custom1 and custom1_2 environments load index.custom1.js and the worker environment index.worker.js, with noExternal and with the dependency externalized
AC-2: building the ssr, worker, custom1 and custom1_2 environments yields index.default.js, index.worker.js, index.custom1.js and index.custom1.js
AC-3: the ssr environment with default conditions loads index.default.js and the worker environment index.worker.js
