# Review context — axios

axios is a promise-based HTTP client for the browser and Node.js. `lib/core/` holds the
request pipeline and `AxiosHeaders`, `lib/adapters/` the `xhr` and `http` adapters, and
`lib/utils.js` the shared helpers. `index.d.ts` is the public typing.

## Conventions

- Outside `lib/utils.js`, new code in `lib/` checks whether a value is an array, a string, a
  function, a plain object or a FormData with the helpers in `lib/utils.js` (`utils.isArray`,
  `utils.isString`, `utils.isFunction`, `utils.isPlainObject`, `utils.isFormData`), never with
  `Array.isArray` or `typeof`. The helpers are the one place where cross-realm and polyfilled
  values are handled. The `typeof config.on…Progress === 'function'` checks in the adapters
  predate the helpers and are not copied.
- `lib/` is ES modules, with the `.js` extension on every relative import.

## Tests

Mocha, under `test/unit/`, with Node's `assert`.
