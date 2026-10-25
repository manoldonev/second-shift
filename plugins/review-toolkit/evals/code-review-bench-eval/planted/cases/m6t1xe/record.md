# Decision record — #10929 Radio input element's checked value not synced with props checked.

## Summary

The renderer writes an element's `checked` prop the way it writes `value`: after the other props
on mount, and on every patch, so the DOM state follows the prop even when the prop's value did
not change.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | When the renderer writes `checked` | On mount, after the element's other props, and on every patch even when the vnode value is unchanged, the same way as `value`. | user-answered | intent |
| D-2 | Where the fix lives | In the renderer in runtime-core, not in runtime-dom's `patchProp`, since only the renderer knows that the value did not change. | user-answered | intent |
| D-3 | What the test covers | A radio group in `@vue/runtime-test` whose two options swap on change, in `rendererComponent.spec.ts`. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2

AC-1: after the second radio's change swaps the options, each radio serializes with the checked value of its prop
AC-2: the re-render writes checked=true to the first radio although its checked prop stayed true
