# Decision record — #3433 Support Cloudflare workers deployment

## Summary

The project deploys to Cloudflare Workers as well as Vercel. A `cloudflare/` entrypoint adapts the
worker's request and response to the existing endpoint handlers. Each handler takes the environment
as a parameter, because the worker passes its variables in rather than through `process.env`.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | How the worker reaches the endpoints | One entrypoint, `cloudflare/index.js`, routes by path to each endpoint's handler, through a request adapter and a response adapter. | user-answered | intent |
| D-2 | How a handler gets its environment | Each endpoint exports `handler(req, res, env)`. Its default export calls the handler with `process.env`, so Vercel and Express keep working. | user-answered | intent |
| D-3 | How the code knows it runs on the worker | The entrypoint sets `IS_CLOUDFLARE` in the environment, and the retryer turns it into a `useFetch` flag for the fetchers. | user-answered | intent |
| D-4 | How a request is sent on the worker | `request` in `src/common/utils.js` sends with `fetch` when `useFetch` is set, and with axios otherwise. | user-answered | intent |
| D-5 | What the tests cover | The fetchers and the retryer, called with an explicit environment. The worker itself runs only under wrangler. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2 AC-3

AC-1: unchecked — the worker entrypoint runs only under wrangler, which the test suite does not start
AC-2: each fetcher and the retryer, called with an environment object, read the tokens, the retry count and FETCH_MULTI_PAGE_STARS from it
AC-3: unchecked — fetch replaces axios only on the worker, which the test suite does not start
