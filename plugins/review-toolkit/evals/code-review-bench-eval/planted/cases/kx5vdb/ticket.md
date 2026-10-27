# JavaScript parsers ignore the source type that .cjs and .mjs file names fix

A `.cjs` file is always a CommonJS script and a `.mjs` file is always an ES module, but Prettier's
JavaScript parsers do not look at the file name. acorn, espree and meriyah parse every file as a
module first and fall back to a script, and babel parses everything as a module that may hold
`import` and `export` anywhere.

So code that the file's own extension makes invalid is formatted without complaint:

```js
// script.cjs: a script cannot import
import "foo"
```

```js
// module.mjs: module code is strict, so `with` is not allowed
with (foo) {}
```

And when such a file does fail to parse, the error shown is the one for the wrong goal, which
points at the wrong problem.

## Acceptance criteria

- AC-1: Formatting `import "foo"` in a file named `script.cjs` with the acorn, espree or meriyah parser fails with that parser's error for an import outside a module.
- AC-2: Formatting `with(foo) {}` in `module.mjs`, or `delete foo` in `module.mJs` (the extension is matched without case), fails with the parser's strict-mode error.
- AC-3: A file with any other extension, and input with no file path, still parses as a module first and then as a script.
