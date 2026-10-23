# [Feature request] Add "Other" to top-lang card

**Describe the solution you'd like**
An option for the **Language Card** that specifically allows showing an "Other" percentage when limiting the amount of languages shown via `langs_count`. Additionally, it may be useful for it to be the 10th "language" when someone has used more than 10 languages in their GitHub account.

**Describe alternatives you've considered**
There's really no alternative within the current functionality for the top-lang card.

**Additional context**
Add any other context or screenshots about the feature request here.

## Acceptance criteria

- AC-1: For a user with more than `n` languages, `/api/top-langs?username=<user>&langs_count=<n>&merge_others=true` serves a card with the top `n - 1` languages and an `Others` entry whose size is the sum of the rest.
- AC-2: With `merge_others=true` and no more than `langs_count` languages, the card shows every language and no `Others` entry.
- AC-3: The readme lists `merge_others` under the top languages card's options.
