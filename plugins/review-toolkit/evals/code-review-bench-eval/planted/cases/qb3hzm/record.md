# Decision record — #10068 Sourcemap for '...bootstrap.min.css' points to missing source files

## Summary

The dev server keeps the `sourcesContent` a sourcemap already carries and reads from disk only the
entries that are missing, so a dependency that ships its sources inside its map no longer warns
about missing source files.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | How missing content is filled | `injectSourcesContent` keeps every non-null entry of `sourcesContent` and reads only the null ones from disk; a source still missing after that warns as before. | user-answered | intent |
| D-2 | When the fill runs | Every served map with mappings goes through it (JS modules, HTML inline styles and CSS with `css.devSourcemap`), not only maps that carry no content at all. | user-answered | intent |
| D-3 | How sources are resolved | Unchanged: relative to the map's `sourceRoot`, else to the file that holds the map. | user-answered | intent |
| D-4 | What the tests cover | Unit tests of `injectSourcesContent` with a fixture file on disk and a source that is not. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2

AC-1: a map whose sourcesContent holds the text of a source that is not on disk keeps it and logs no warning
AC-2: a null entry is read from the fixture file, sourceRoot is honoured, and a source neither carried nor on disk warns once
