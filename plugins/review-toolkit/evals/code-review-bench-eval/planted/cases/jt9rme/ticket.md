# getFileInfo() does not accept a URL as ignorePath

`prettier.resolveConfig()`, `prettier.resolveConfigFile()` and `prettier.getFileInfo()` accept a
file `URL` or a `file://` URL string for the file they are asked about, but the `ignorePath`
option of `prettier.getFileInfo()` still only works with a plain path. Code that builds its paths
from `import.meta.url` has to convert the ignore file back to a path first:

```js
await prettier.getFileInfo("/path/to/file", {
  ignorePath: new URL("./.eslintignore", import.meta.url),
});

await prettier.getFileInfo("/path/to/file", {
  ignorePath: "file:///path/to/.eslintignore",
});
```

Today the first call rejects with a `TypeError` about the `path` argument, and the second never
finds the ignore file, so a file it lists is reported as not ignored.

## Acceptance criteria

- AC-1: `prettier.getFileInfo(file, { ignorePath })` reports `{ ignored: true, inferredParser: null }` for a file the ignore file lists when `ignorePath` is a `URL`, a `file://` URL string or an absolute path, given alone or in an array.
- AC-2: The patterns of an ignore file given as a `URL` match relative to that ignore file's folder, as they do for a path, and `resolveConfig` still infers the parser from the file's config.
