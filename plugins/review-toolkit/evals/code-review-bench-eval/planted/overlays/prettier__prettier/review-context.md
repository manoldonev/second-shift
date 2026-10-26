# Review context — Prettier

Prettier formats code in many languages. `src/main` parses a file, attaches comments and prints
the result through the document builders in `src/document`. Each language lives in its own
`src/language-*` directory with its parser adapters, its printer and its utilities;
`src/language-js` serves JavaScript, Flow and TypeScript. `src/cli` is the command line, and
`src/config` resolves the options and the config files.

## Conventions

- JavaScript ES modules. Prettier formats its own source.
- A printer returns a doc built from the builders in `src/document`, never a string it joined
  itself.
- A user-visible change adds an entry under `changelog_unreleased/`.

## Tests

Jest. A formatting test is a directory under `tests/format/` with input files, a
`format.test.js` or `jsfmt.spec.js` that runs them, and the output snapshots under
`__snapshots__/`. Unit tests live under `tests/unit/`, and CLI tests under `tests/integration/`.
