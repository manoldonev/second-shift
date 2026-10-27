# Decision record — #7805 Vue 3 SFC Compiler function call with semicolon bug.

## Summary

`<script setup>` no longer removes the `defineProps` and `defineEmits` declarations and hoists
replacement assignments to the top of `setup`; it rewrites the macro calls in place, so the user's
statements keep their order and their semicolon style.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | How a `defineProps` declaration is compiled | The call is rewritten in place to `__props`, and the declaration stays where the user wrote it. | user-answered | intent |
| D-2 | How a `defineEmits` declaration is compiled | The call is rewritten in place to `__emit`, and `setup` destructures the emit function as `emit: __emit`. | user-answered | intent |
| D-3 | A destructure with a rest element | The pattern becomes the rest name and the call becomes the `createPropsRestProxy` call, in place. | user-answered | intent |
| D-4 | Using `props` before its `defineProps` line | No longer supported, since the assignment is not hoisted; flagged in the PR as a possible breaking change. | user-answered | intent |
| D-5 | What the tests cover | `compileScript.spec.ts` for the semicolon case, `defineEmits.spec.ts` for the emit name, and `definePropsDestructure.spec.ts` for multi-variable declarations, with the snapshots updated. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2 AC-3

AC-1: the compiled semicolon-less setup contains console.log('test'), const props = __props;, const emit = __emit; and (function () {})() in source order
AC-2: compiling const myEmit = defineEmits(['foo', 'bar']) gives setup(__props, { expose: __expose, emit: __emit }) and const myEmit = __emit
AC-3: compiling a destructured defineProps first, last or alone in a multi-variable declaration keeps the other declarators and declares the props option
