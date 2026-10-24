# Review context — Vue.js core

Vue's core is a monorepo of packages under `packages/`. `reactivity` is the reactivity system.
`runtime-core` is the platform-agnostic renderer, the component model and the JavaScript APIs
such as `watch`. `runtime-dom` targets the browser: DOM props, attributes, events and the
built-in directives. `compiler-core`, `compiler-dom`, `compiler-sfc` and `compiler-ssr` compile
templates and single-file components. `shared` holds the utilities that the runtime and the
compiler both use.

## Conventions

- A package imports another package by its package name, such as `@vue/runtime-core`, never by
  a relative path.
- Compiler packages never import from the runtime, and the runtime never imports from a
  compiler. Code that both need lives in `@vue/shared`.
- Dev-only warnings and checks sit behind `__DEV__`.
- Prettier formatting as the repo's `.prettierrc` sets it: no semicolons, single quotes.
- Commit messages follow the repo's commit convention: `fix(runtime-core): ...`.

## Tests

Vitest. Unit tests sit beside the code in each package's `__tests__` directory. A test that
asserts virtual DOM operations or platform-agnostic behavior uses `@vue/runtime-test`.
