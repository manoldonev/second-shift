# Review context — Vite

Vite is a pnpm monorepo. `packages/vite` is the published package. Its `src/node` holds the dev
server (`server/`), the production build (`build.ts`), the config loader (`config.ts`), the
dependency optimizer (`optimizer/`), SSR (`ssr/`) and the built-in plugins (`plugins/`).
`src/client` is the browser client of the dev server, and `src/module-runner` runs modules
outside the browser. `playground/` holds the end-to-end fixtures.

## Conventions

- TypeScript throughout. Prettier formatting as the repo's config sets it: no semicolons,
  single quotes.
- A built-in plugin is a factory in `src/node/plugins/` that returns a Rollup-compatible plugin
  object.
- Commit messages follow the repo's commit convention: `fix(ssr): ...`.

## Tests

Vitest. Unit tests sit in `__tests__` directories beside the code. End-to-end tests run against
the fixtures under `playground/`.
