# Decision record — #11326 Hydration mismatch when using v-if="false" in nested <slot> of external component

## Summary

The server renderer checks a slot's vnode content the way the client's `renderSlot` does: content
that holds only comments is not valid, so the server renders the fallback, or an empty slot
fragment when there is none, instead of the `<!--v-if-->` placeholder the client never creates.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | How the server decides that vnode slot content is empty | It reuses the runtime's own content check, exported from runtime-core through `ssrUtils`, so the server and the client cannot disagree. | user-answered | intent |
| D-2 | What the server renders for empty vnode slot content | The slot's fallback when it has one, else nothing inside the slot fragment, as the client does. | user-answered | intent |
| D-3 | The SSR-compiled slot path | Unchanged: it keeps its own check on the pushed buffer for comment-only output. | user-answered | intent |
| D-4 | What the tests cover | `ssrSlot.spec.ts`: a dynamic component slot whose nested component slot holds a `v-if="false"` element, the same with `v-if="true"`, and a `<template v-if="false">` passed straight to the dynamic component. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2

AC-1: renderToString of a dynamic component slot holding a nested slot with v-if="false" content renders an empty slot fragment with no v-if comment
AC-2: renderToString of the same slot with v-if="true" content renders the content inside the slot fragment
