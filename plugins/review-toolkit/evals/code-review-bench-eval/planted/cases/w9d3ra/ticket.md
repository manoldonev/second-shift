# Extra pins tab has the language overlapping with stars/other stats

**Describe the bug**
The extra pins tab has the language overlapping with the number of github stars.

**Screenshots / Live demo link (paste the github-readme-stats link as markdown image)**
![test](https://github-readme-stats.vercel.app/api/pin/?username=pblpbl1024&repo=escape&theme=gotham&show_owner=true)

'Game maker language' is overlapping with the star symbol.

## Acceptance criteria

- AC-1: On the repo card, the stars and the forks start after the language name, so a long language name such as `Game Maker Language` no longer overlaps the star icon.
- AC-2: On the compact top languages card, the second column of languages starts after the longest name in the first column, so the two columns no longer overlap.
