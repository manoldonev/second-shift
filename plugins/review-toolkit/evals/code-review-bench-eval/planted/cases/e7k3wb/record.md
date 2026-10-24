# Decision record — #7256 [Bug] When `slot` is used with `v-if`, the slot content is not displayed as expected

## Summary

A slot's content and its fallback come from two different templates, so their fragments cannot
share the optimized patch path. The renderer replaces the slot's fragment when it switches
between content and fallback.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | How the renderer tells the two fragments apart | renderSlot marks the fragment it returns, and processFragment reads the mark of the old and the new fragment. | user-answered | intent |
| D-2 | What the renderer does on a switch | It unmounts the old fragment and mounts the new one, so neither the fast path nor a full diff runs across the two templates. | user-answered | intent |
| D-3 | Fragments that renderSlot did not create | Their patch path does not change. | user-answered | intent |
| D-4 | What the test covers | A compiled-style slot with a fallback in `rendererOptimizedMode.spec.ts`, toggled to the fallback and back. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2

AC-1: the slot shows its content, then the fallback after the toggle, then the content again
AC-2: the content's nodes come back in full after the fallback, with the comment and the hoisted div
