# Decision record — #6739 [Bug] Incorrect `*` checking

## Summary

`getSitesFixesFor` returns the generic fix first, and the dynamic theme reads it from the start
of the list. The CSS filter already read it from the start, so it now gets the generic fix too.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | The order getSitesFixesFor returns | The generic fix, then the domain-pattern fixes, then the fully qualified domain's fixes. A record that matches twice appears once. | user-answered | intent |
| D-2 | Which callers change | `getDynamicThemeFixesFor` reads index 0 and sorts the rest. The CSS filter's `getInversionFixesFor` already reads index 0 and is unchanged. | user-answered | intent |
| D-3 | The existing parse tests | Their expected arrays move the generic fix to the front. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2 AC-3

AC-1: getSitesFixesFor on a nested domain returns the generic fix, then the pattern fix, then the domain's fix
AC-2: exempt — the dynamic theme generator has no unit suite at this base; AC-1's test pins the list it reads
AC-3: the reordered expectations of the existing parse tests pass
