# Decision record — #7238 [Bug] Base64 padding in themes breaks the extension

## Summary

`indexSitesFixesConfig` splits the config into blocks only at a delimiter line, so `==` inside a
block's CSS no longer ends the block.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Where the fix lives | The delimiter regex of `indexSitesFixesConfig`. The block parser is not changed. | user-answered | intent |
| D-2 | What a delimiter is | A whole line of two or more `=` signs, with optional whitespace around them and nothing else: the index uses the same pattern as `parseSitesFixesConfig`, `/^\s*={2,}\s*$/gm`, so the two always agree on where a block ends. | user-answered | intent |

## Test intent

ACs: AC-1

AC-1: a config whose CSS holds a base64 string padded with == indexes as two blocks, and the site's fix keeps its CSS whole
