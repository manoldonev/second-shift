# Decision record — #9440 SSR Rendering of select input with slot is breaking

## Summary

The SSR `v-model` transform on `<select>` adds its ` selected` check to `<option>` children only and
looks inside `<optgroup>` for more options, so a `<slot/>` or another non-option child no longer
breaks the compile.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Which select children get the selected check | `<option>` elements only; a slot outlet, a component or any other element is left as it is. | user-answered | intent |
| D-2 | Options inside an `<optgroup>` | The transform descends into each `<optgroup>` and gives its options the same check as direct options. | user-answered | intent |
| D-3 | An option that already has a static `selected` attribute | It keeps its own attribute and gets no model check, as before. | user-answered | intent |
| D-4 | What the tests cover | `ssrVModel.spec.ts`: a slot directly in a multiple select, an option in an optgroup, and a slot in an optgroup. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2

AC-1: compiling a multiple select v-model with a slot child, and with a slot inside an optgroup, renders the slot with ssrRenderSlot inside the select
AC-2: compiling a multiple select v-model with an option in an optgroup renders that option with the ssrLooseContain or ssrLooseEqual selected expression
