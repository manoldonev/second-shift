# Support Cloudflare workers deployment

### Is your feature request related to a problem? Please describe.

Vercel has cold start issues once there's not request for a while. Cloudflare workers shouldn't have this problem.

### Describe the solution you'd like

Support deploying to Cloudflare workers.

### Describe alternatives you've considered

_No response_

### Additional context

_No response_

## Acceptance criteria

- AC-1: `npx wrangler deploy` deploys a worker whose entrypoint serves `/api`, `/api/pin`, `/api/top-langs`, `/api/gist`, `/api/wakatime`, `/api/status/up` and `/api/status/pat-info`.
- AC-2: On the worker, the cards read the `PAT_n` tokens and `FETCH_MULTI_PAGE_STARS` from the worker's environment. On Vercel they keep reading `process.env`.
- AC-3: Every card served by the worker answers there. axios does not run on Cloudflare Workers, so each request a card makes there goes through `fetch`.

## Out

- `include_all_commits` keeps its REST call for now; the worker does not support it yet.
- `CACHE_SECONDS` stays a Vercel setting outside `/api`.
