# Pass filenames including queries to `renderBuiltUrl` like <8.3.0

https://github.com/vitejs/vite/pull/22886 made filenames passed to `renderBuiltUrl` not to contain the queries (and hashes). But Vinext returns URL containing queries from `renderBuiltUrl` and that causes final URL to be like `asset.svg?dpl=id?marker=value` (https://github.com/cloudflare/vinext/pull/3263, it was `asset.svg?dpl=id&marker=value` as the query injection was handled by `renderBuiltUrl`).

To fix this we need to either:

- pass a new param to `renderBuiltUrl` that contains queries / hashes
- include queries / hashes in the `filename` param of `renderBuiltUrl` as before

Another thing we need to decide is whether this query handling should exist on Rolldown (/ Rollup) side, or be handled by `urlId`.

## Acceptance criteria

- AC-1: When a JS module imports an asset with a query, such as `/asset.txt?url&marker=value`, the `filename` that `experimental.renderBuiltUrl` receives for it includes the query, so a `renderBuiltUrl` that adds its own query renders `?dpl=id&marker=value`, and two imports of the same file with different queries keep their own query each.
- AC-2: A `url()` reference with a query in CSS reaches `renderBuiltUrl` the same way: the `filename` includes the query, and the built stylesheet holds the rendered URL with both queries for each reference.
