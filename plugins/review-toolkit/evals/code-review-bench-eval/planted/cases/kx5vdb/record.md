# Decision record — #15511 TypeError in HTML parser when parsing a custom element followed by a prototype

## Summary

The HTML printer looks up an element's CSS display and white-space in tables keyed by tag name. A tag
named after an `Object.prototype` member found the inherited member instead of a table entry, and the
printer crashed on it. The lookups now read own keys only, so such a tag is formatted like any unknown
element.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | How the CSS display and white-space tables are read | Through own keys only (`Object.hasOwn`), in both `getNodeCssStyleDisplay` and `getNodeCssStyleWhiteSpace`. | user-answered | intent |
| D-2 | Where the fix lives | In the two lookup functions in `src/language-html/utils/index.js`; the tables in `constants.evaluate.js` stay plain objects. | user-answered | intent |
| D-3 | What the tests cover | A format test with one element per `Object.prototype` property name, under `tests/format/html/tags/object-prototype-properties`. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2

AC-1: formatting `<constructor>constructor</constructor>` and the other Object.prototype names with the html parser completes without an error
AC-2: each such element prints on one line with its text unchanged
