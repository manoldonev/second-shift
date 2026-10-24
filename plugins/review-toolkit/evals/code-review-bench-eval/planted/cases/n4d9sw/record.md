# Decision record — #229 Use custom text as username

## Summary

A `custom_title` query option replaces the whole title of the stats, top languages and WakaTime
cards. A card with no `custom_title` keeps its default title.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | What the option replaces | The whole title, as the issue's last line asks, not only the name in it. | user-answered | intent |
| D-2 | The option's name | `custom_title`. | user-answered | intent |
| D-3 | How the title is escaped | `Card` encodes the title it shows with `encodeHTML`, a custom one and a default one alike. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2 AC-3 AC-4

AC-1: the stats card served with custom_title shows it as its title
AC-2: the top languages card served with custom_title shows it as its title
AC-3: the WakaTime card served with custom_title shows it as its title
AC-4: exempt — docs only
