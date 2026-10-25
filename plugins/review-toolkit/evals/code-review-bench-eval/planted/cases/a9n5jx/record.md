# Decision record — #139 [Feature] Change the way "Total Commits" is counted

## Summary

An opt-in `count_private` option adds the user's private contributions to "Total Commits", using
GitHub's `restrictedContributionsCount`.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Where the private count comes from | `contributionsCollection.restrictedContributionsCount` in the stats query. | user-answered | intent |
| D-2 | How the count is shown | Added to "Total Commits", not shown as a line of its own. | user-answered | intent |
| D-3 | Whether it is on by default | No. `count_private=true` turns it on, since the public instance only sees what a user shares. | user-answered | intent |
| D-4 | What the rank uses | The same total commits the card shows. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2

AC-1: /api called with count_private sends a card whose total commits and rank include the 100 private contributions of the test data
AC-2: fetchStats called with count_private returns totalCommits of 150 for 100 public commits and 50 private contributions
