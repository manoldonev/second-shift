# Decision record — #20113 .prettierrc.json and .prettierrc.toml reject a leading UTF-8 BOM

## Summary

A textual configuration file that starts with a UTF-8 BOM is read with the BOM removed before it
is parsed, so JSON and TOML configs load like JSON5 and YAML already do, and the formatter and the
config reader share one BOM helper.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Where the BOM is removed | In `readFile`, behind a `stripBom` option that defaults to off, so other readers of `readFile` (the ignore file) keep reading the raw text. | user-answered | intent |
| D-2 | Who asks for it | The config loaders take an options argument and pass it to `readFile`; `loadConfig` asks for `stripBom`. | user-answered | intent |
| D-3 | BOM handling in the formatter | `core.js` uses the shared `src/utilities/bom.js` helpers instead of its own `BOM` constant; output is unchanged. | codebase | intent |
| D-4 | What the tests cover | `tests/unit/config-loader.js`: `loadConfig` on package.json, `.prettierrc`, `.prettierrc.json`, `.prettierrc.yml`, `.prettierrc.json5` and `.prettierrc.toml`, each written with a leading BOM. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2

AC-1: config-loader.js loads .prettierrc.json and .prettierrc.toml with a leading BOM to { tabWidth: 5 }
AC-2: config-loader.js loads package.json, .prettierrc, .prettierrc.yml and .prettierrc.json5 with a leading BOM to { tabWidth: 5 }
