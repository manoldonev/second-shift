# Decision record — #15553 Prettier should format JSONC with trailing commas

## Summary

Prettier gets a `jsonc` parser for JSON with Comments. It parses like `json`, respects `trailingComma`,
keeps object keys quoted and strings double-quoted, and is the default parser for the JSON with Comments
language.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | How JSONC is supported | A new `jsonc` parser, built on the same parse function as `json` and `json5`, with the estree printer. | user-answered | intent |
| D-2 | Trailing commas | `jsonc` follows the `trailingComma` option; `json` keeps forcing `none`. | user-answered | intent |
| D-3 | Object keys and string quotes | `jsonc` always quotes keys and always uses double quotes, like `json`. | user-answered | intent |
| D-4 | Which files use it by default | The JSON with Comments language from linguist infers `jsonc`; the hand-added `.eslintrc` filename is dropped. | user-answered | intent |
| D-5 | The json5 workaround | Kept as is: `json5` with `quoteProps: "preserve"` and no `singleQuote` still prints double quotes. | user-answered | intent |
| D-6 | What the tests cover | `tests/format/json/jsonc` for trailing commas, quote props, single quotes and range formatting, and `with-parser-inference.js` for the inferred parser. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2 AC-3 AC-4

AC-1: test.jsonc formatted with trailingComma none, es5 and all prints commas after the last array item and the last property only for es5 and all
AC-2: {key:""} in test.jsonc prints as { "key": "" } under quoteProps as-needed, consistent and preserve
AC-3: a single-quoted string in test.jsonc prints double-quoted with singleQuote true
AC-4: formatting a .swcrc file by its path infers jsonc and adds trailing commas
