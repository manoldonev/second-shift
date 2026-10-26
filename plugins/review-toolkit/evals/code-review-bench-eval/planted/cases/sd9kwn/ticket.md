# Config file search treats the given file path as a directory

When `prettier.resolveConfigFile()`, `prettier.resolveConfig()` or `prettier --find-config-path`
is given the path of a file, the search for a config file starts inside that path, as though the
path were a directory. If the path happens to be a directory that holds a config file, that config
file is used by mistake, instead of the one that applies to the folder the path sits in.

```text
├─ .prettierrc
└─ test.js         (a directory)
  ├─ .prettierrc
  └─ index.min.js
```

```js
await prettier.resolveConfigFile(new URL("./test.js", import.meta.url));
// Today:    <CWD>/test.js/.prettierrc
// Expected: <CWD>/.prettierrc
```

## Acceptance criteria

- AC-1: For a file path, `prettier.resolveConfigFile()` and `prettier --find-config-path` return the config file found from the folder that holds the file upward: `file.js` gets the `.prettierrc` beside it, and `directory/<file>` gets `directory/.prettierrc`.
- AC-2: `prettier --find-config-path` on a path with no config file in its folder or above still prints `Can not find configure file for "<path>".` and exits with status 1.
