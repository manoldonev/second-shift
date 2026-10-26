# Decision record — #10082 Providing a computed prop to child breaks the reactivity of the computed

## Summary

An effect that is running when one of its sources changes is now marked dirty instead of being
skipped, a computed is tracked by its reader only after it has evaluated, and the dirty levels
shrink to three, so a parent that renders a computed re-renders when a child changes the
computed's source during the parent's render.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | The dirty levels | `NotDirty`, `MaybeDirty` and `Dirty`; a computed signals `MaybeDirty` to its readers when a source changes and `Dirty` when its value changed. | user-answered | intent |
| D-2 | When a reader tracks a computed | After the computed has evaluated, so the computed's own first evaluation does not mark the reader dirty. | user-answered | intent |
| D-3 | A source change while its effect is running | The effect's dirty level is raised as for an idle effect; its scheduler is queued at once only if the effect allows recursion, and otherwise on the next trigger after the run. | user-answered | intent |
| D-4 | What the tests cover | `computed.spec.ts`: two chained computeds with `allowRecurse`, and a computed whose source is written while it evaluates; `effect.spec.ts`: the parent and child component case from the issue. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2 AC-3

AC-1: after reading the outer of two chained computeds with allowRecurse set on both, both effects report the NotDirty level
AC-2: the first read of the provider computed returns 0foo and leaves it at the Dirty level, and the second read returns 1foo
AC-3: rendering the parent whose child's setup increments the source renders 22 after the next tick, with two renders of the parent
