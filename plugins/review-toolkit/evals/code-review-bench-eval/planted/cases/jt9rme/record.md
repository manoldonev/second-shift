# Decision record — #15364 getFileInfo() does not accept a URL as ignorePath

## Summary

`prettier.getFileInfo()` accepts its `ignorePath` option as a `URL`, a `file://` URL string or a
path, alone or in an array, the same forms it already accepts for the file itself.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Which forms `ignorePath` accepts | A `URL`, a `file://` URL string or a path, alone or in an array. | user-answered | intent |
| D-2 | Which folder the patterns of an ignore file are relative to | The folder that holds the ignore file, whatever form named it; with no ignore file, the working directory. | user-answered | intent |
| D-3 | The documented type | `string \| URL \| (string \| URL)[]` in `docs/api.md`, `index.d.ts` and the `FileInfoOptions` JSDoc. | user-answered | intent |
| D-4 | What the tests cover | `file-info.js`: the existing ignorePath tests switched to URLs, and a new test over a URL, a URL string and a path, each alone and in an array. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2

AC-1: getFileInfo on ignored-by-customignore.js returns ignored true for ignorePath as a URL, its href and its path, alone and in an array
AC-2: getFileInfo with a URL ignorePath leaves shouldNotBeFormat.js unignored and infers parser-for-config-dir under resolveConfig
