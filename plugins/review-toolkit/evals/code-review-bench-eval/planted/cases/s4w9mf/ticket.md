# Automatic Resizing Fit to Content

**Is your feature request related to a problem? Please describe.**
Upon using and customizing the github-readme-stats card, I realized that the card is **unable to resize based on its content**. More specifically, when we set the ```hide_rank``` property to true, the actual card size remains unchanged, leaving the **space originally occupied by the ranking circle still part of the card**. In this case, the **extra white space on the right of the card** appears weird and unnecessary.

**Describe the solution you'd like**
I expect the card to be **resizable in accordance to its content**. In other words, the card no longer occupies white space when certain elements are set to hidden.

**Describe alternatives you've considered**
A simpler approach could be distributing a new view size that does not contain rating circle from start.

**Additional context**
With more people making use of this repo with the new feature of GitHub Account README, the handling of details could significantly improve the user experience delivered to everyone.

## Acceptance criteria

- AC-1: With `hide_rank=true`, the stats card is as wide as the title it shows plus 25 px of padding on each side, for any user name, and never narrower than 270 px.
- AC-2: With `hide_rank=true` and a `custom_title`, the width follows the custom title instead of the default one.
