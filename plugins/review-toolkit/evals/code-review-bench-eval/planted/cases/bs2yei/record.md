# Decision record — #18369 Improve template literal expression print in embeded language

## Summary

Interpolations inside embedded templates (CSS, GraphQL, HTML) are printed by the same code as
interpolations in plain template literals, so an interpolation written on one line is kept on one line,
and one that spans lines is indented the same way in both.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Where embedded interpolations are printed | One shared `printTemplateExpression` in `template-literal.js`, used by `printTemplateLiteral` and by the css, graphql and html embeds through `printTemplateExpressions`. | user-answered | intent |
| D-2 | When an interpolation may break | Only when it already contains a newline in the source, or when its printed form contains one anyway, the rule plain template literals used. | user-answered | intent |
| D-3 | How a broken interpolation is indented | From the indentation of the quasi it follows, computed once per template literal. | user-answered | intent |
| D-4 | Embed signatures | The css, graphql and html embed printers take `options` and pass it to `printTemplateExpressions`. | user-answered | intent |
| D-5 | What the tests cover | `expression-break.js` for html templates, `styled-components.js` and `template-literals.js` for CSS templates. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2 AC-3

AC-1: a styled-jsx CSS template whose one-line interpolation runs past printWidth prints that interpolation on one line
AC-2: an html template with a long one-line interpolation prints it on one line inside the div
AC-3: a styled.div template whose interpolation starts on a new line prints it broken at the braces and indented one level
