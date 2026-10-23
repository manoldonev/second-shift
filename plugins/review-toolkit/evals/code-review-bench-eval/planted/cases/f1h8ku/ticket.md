# Bug: word wrapping

**Describe the bug**
Reopen #921, non-english characters go outside the card, same goes with looooong repo name.

**Screenshots / Live demo link (paste the github-readme-stats link as markdown image)**
![](https://github-readme-stats.vercel.app/api/pin/?username=chefyuan&repo=algorithm-base)
![](https://github-readme-stats.vercel.app/api/pin/?username=tylermcginnis&repo=react-flux-gulp-browserify-reactrouter-firebase-starterkit)

## Acceptance criteria

- AC-1: On the repo card, a header longer than 35 characters is cut to its first 35 characters followed by `...`.
- AC-2: A description in Chinese wraps at its full-width commas (`，`), into at most three lines.
