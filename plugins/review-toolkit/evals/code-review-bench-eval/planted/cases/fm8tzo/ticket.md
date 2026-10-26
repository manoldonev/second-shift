# Query parsing on every module id slows down transforms

Several plugins split a module id at its query and build an object from the whole query
string with `URLSearchParams`, only to check whether `worker`, `sharedworker`, `worker_file`,
`inline`, `url` or `raw` is present, or to read one value. The worker plugin does this in its
`load`, `shouldTransformCachedModule` and `transform` hooks, so the cost is paid for every
module, and a benchmark over typical ids shows the parsing itself as the expensive part.

The parsed objects also leak into generated code: a dynamic import such as
``import(`./mods/${name}.js?foo=bar`)`` turns into an `import.meta.glob` call whose `query`
option is an object rather than the query string the user wrote.

## Acceptance criteria

- AC-1: A dynamic import with a variable path and a `?raw`, `?url` or `?worker` query compiles to an `import.meta.glob` call with that query as a string with its leading `?` and `import: '*'`, and any other query is passed through as the query string, such as `?foo=bar`.
- AC-2: In dev, a module worker's script is requested with `?worker_file&type=module`, and the source map of the served script keeps its boundary.
