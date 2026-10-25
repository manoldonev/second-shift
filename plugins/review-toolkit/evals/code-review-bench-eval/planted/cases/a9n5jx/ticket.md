# [Feature] Change the way "Total Commits" is counted

**Is your feature request related to a problem? Please describe.**
The "Total Commits" on the readme card is usually very small to my frequency of using github since many of my repositories are private projects.

**Describe the solution you'd like**
Add a new section in the widget to says the number of commits in private repositories or include this number in "Total Commits".

**Describe alternatives you've considered**
No other real alternatives.

**Additional context**
I'm not sure about how such a feature could be implemented as I don't know if there is such a feature in the github api. Perhaps I was thinking, to use the number of "contributions" a user has since that includes commits to private repositories and follows a strict counting guideline.

## Acceptance criteria

- AC-1: `/api?count_private=true` adds the user's private contributions to the stats card's total commits, and the rank counts them too.
- AC-2: `fetchStats(username, true)` returns `totalCommits` as the public commits plus `restrictedContributionsCount`. Without the flag, `totalCommits` stays the public commit count.
