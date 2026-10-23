# Review context — Day.js

Day.js is a 2 kB date library with a Moment.js-compatible API. The core is `src/index.js`, with
helpers in `src/utils.js` and constants in `src/constant.js`. Each plugin lives in
`src/plugin/<name>/index.js` and is built and published as its own file.

## Conventions

- The core (`src/index.js`, `src/utils.js`) names a unit through the constants in
  `src/constant.js` (`C.M`, `C.D`, `C.Y`, …), never as a string literal such as `'month'`.
- A plugin reaches the core helpers through `this.$utils()` or the `dayjs` argument it is
  installed with. A plugin never imports `src/utils.js`: each plugin is bundled alone, and an
  import would ship a second copy of the helpers.
- Code follows the repo's eslint config (airbnb-base, no semicolons, no trailing commas).
- A behavior shared with Moment.js is tested against Moment.js in the same test.

## Tests

Jest, under `test/`, one file per module or plugin (`test/plugin/<name>.test.js`).
