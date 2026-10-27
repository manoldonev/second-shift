# Decision record — #13772 JavaScript parsers ignore the source type that .cjs and .mjs file names fix

## Summary

The JavaScript parsers read the source type from the file name. A `.cjs` path parses only as a
script and a `.mjs` path only as a module, matched without case; any other path, or none, keeps the
module-then-script attempts.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Where the source type comes from | `options.filepath`: a name ending in `.cjs` is a script, in `.mjs` a module, compared lower-cased; anything else is unknown. One helper, `parse/utils/get-source-type.js`, serves every parser. | user-answered | intent |
| D-2 | What a known source type changes in acorn, espree and meriyah | One attempt with that type instead of module then script; acorn allows import and export only in module code. | user-answered | intent |
| D-3 | Babel | Uses `__babelSourceType` when a caller sets one, else the type from the file name; script code rejects import and export, as the other parsers do. | user-answered | intent |
| D-4 | `tryCombinations` | Takes one array of attempts instead of rest arguments; `typescript.js` passes an array too. | codebase | intent |
| D-5 | What the tests cover | A format error test over acorn, espree and meriyah with `script.cjs`, `module.mjs` and `module.mJs` snippets, under `tests/format/misc/errors/js/known-source-type`. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2

AC-1: `import "foo"` in script.cjs fails with the import-outside-a-module error of acorn, espree and meriyah
AC-2: `with(foo) {}` in module.mjs and `delete foo` in module.mJs fail with each parser's strict-mode error
