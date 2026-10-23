# Review context — Dark Reader

Dark Reader is a browser extension that generates dark themes for web sites. Site fixes are
plain-text config files (`src/config/*.config`) of blocks separated by a line of `=` signs. Each
block starts with its URL patterns, then its commands. `src/generators/utils/parse.ts` indexes
and parses these files; the generators in `src/generators/` turn the parsed fixes into a theme.

## Conventions

- TypeScript, strict. Four-space indent and single quotes.
- The parsers in `src/generators/utils/` are pure: they read the config text they are given and
  return values. They never read browser state.
- A fix whose URL pattern is `*` is the generic fix. It applies to every site, and a site's own
  fixes are merged over it.

## Tests

Jest, under `tests/`, mirroring the `src/` tree (`tests/generators/utils/parse.tests.ts`).
