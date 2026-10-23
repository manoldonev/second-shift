# Decision record — #5844 Tests No Longer Passing since Upgrading to v1.5.0

## Summary

The default adapter becomes the list `['xhr', 'http']`, and `getAdapter` takes the first adapter
of a list that is available, so an environment with an XMLHttpRequest uses `xhr` even on Node.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | The default adapter | `['xhr', 'http']`: `xhr` where an XMLHttpRequest exists, such as a test runner with Pretender, else `http`. | user-answered | intent |
| D-2 | An unknown name | Fails at once with `Unknown adapter '<name>'`, before any later entry is tried. | user-answered | intent |
| D-3 | The error when none is available | One `AxiosError` with code `ERR_NOT_SUPPORT` that lists each rejected adapter and its reason. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2 AC-3

AC-1: getAdapter returns a function handle unchanged, and a named adapter by a mixed-case name
AC-2: getAdapter on ['foo', 'bar', 'baz'] with foo false and bar null returns baz
AC-3: getAdapter throws 'is not available in the build' for null and 'is not supported by the environment' for false
