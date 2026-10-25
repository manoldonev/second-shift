# Review context — GitHub Readme Stats

GitHub Readme Stats renders SVG cards for GitHub profiles. `api/` holds one serverless endpoint
per card. `src/cards/` renders each card: the stats card, the repo pin card, the top languages
card and the WakaTime card. `src/common/` holds what the cards share: `Card.js` (the frame, the
title and the colors) and `utils.js` (text wrapping, HTML encoding, option parsing).

## Conventions

- An endpoint reads its query options through `parseBoolean`, `parseArray` and `clampValue` from
  `src/common/utils.js`.
- User text that reaches the SVG goes through `encodeHTML`.
- Prettier formatting, double quotes, trailing commas.

## Tests

Jest, under `tests/`, one file per card or module. Card tests render into `document.body` and
query the SVG. Each test a plan names runs through the jest runner, named as `file::describe > it`.
