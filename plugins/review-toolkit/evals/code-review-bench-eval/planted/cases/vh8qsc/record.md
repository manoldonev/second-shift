# Decision record — #23487 Pass filenames including queries to `renderBuiltUrl` like <8.3.0

## Summary

The `filename` that `renderBuiltUrl` receives for an emitted asset carries the query and hash the
asset was referenced with again, in JS and in CSS, so a `renderBuiltUrl` that adds its own query
renders one query string instead of two.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | How the query reaches `renderBuiltUrl` | In the `filename` argument, as before 8.3.0, rather than through a new parameter. | user-answered | intent |
| D-2 | Where the query is kept until the URL is rendered | On the Vite side: the asset's URL metadata stores it under a `urlId`, and the code that resolves the reference appends it to the file name. Rolldown is not asked to carry it. | user-answered | intent |
| D-3 | How a reference names its metadata | JS uses `import.meta.ROLLDOWN_FILE_URL_<referenceId>_<urlId>`; text uses `__VITE_ASSET__<referenceId>_<urlId>__`, and `assetUrlRE` matches the 22-character reference id with an optional `urlId`. A reference with no query and no file URL gets no `urlId`. | user-answered | intent |
| D-4 | What the tests cover | `build.spec.ts`: a `renderBuiltUrl` that adds `dpl=id`, over an entry that imports one asset with two different queries and a stylesheet that references it with the same two queries. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2

AC-1: building an entry that imports `/asset.txt?url&marker=value` and `/asset.txt?url&marker=other` with a renderBuiltUrl that adds `dpl=id` puts `?dpl=id&marker=value` and `?dpl=id&marker=other` in the entry chunk
AC-2: the same build with a stylesheet whose url() references carry the two queries puts both rendered URLs in the CSS asset
