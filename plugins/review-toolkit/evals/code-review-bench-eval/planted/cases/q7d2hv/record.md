# Decision record — #8482 Can't use generic prop type when definition includes intersection with generic params?

## Summary

The type resolver of compiler-sfc binds a generic alias's or interface's type parameters to the
arguments of the reference that names it, and resolves those parameters wherever the alias's
body uses them.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | How a parameter reaches its uses | The resolver passes a map from parameter name to argument node down through the alias, the interface and their members. | user-answered | intent |
| D-2 | Which generic declarations bind | Type aliases and interfaces with type parameters, local or imported. Generic functions and classes stay out of scope. | user-answered | intent |
| D-3 | An argument that names an outer parameter | It resolves to the outer argument, so `type Props<T> = Aliased<T>` passes the caller's argument on. | user-answered | intent |
| D-4 | What the tests cover | A `generics` block in `resolveType.spec.ts`, one test per declaration shape. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2

AC-1: an intersection of two generic parameters and a literal resolves to the props of all three
AC-2: a generic literal, an alias of an alias, an interface and an imported alias each resolve their parameter to its argument
