# Decision record — #8048 Multiple files for --ignore-path

## Summary

`--ignore-path` accepts several values. A file is ignored when any of the given ignore files
ignores it, each file's patterns read relative to that file's folder. `getFileInfo()` accepts one
`ignorePath` or a list.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | How several ignore files combine | One matcher per ignore file; a path is ignored when any matcher ignores it. | user-answered | intent |
| D-2 | An ignore file that does not exist | Skipped, with no error, as a single missing ignore file is today. | user-answered | intent |
| D-3 | The CLI default | `[".prettierignore"]`, shown in `--help` as `[.prettierignore]`. | user-answered | intent |
| D-4 | `getFileInfo()` in the API | Keeps accepting a single `ignorePath` string, and also takes a list. | user-answered | intent |
| D-5 | What the tests cover | `ignore-path.js`: three ignore files, one of them missing, with `--debug-check`; the existing ignore tests assert empty stderr; the help snapshots. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2

AC-1: prettier "**/*.js" --debug-check with three --ignore-path values, one missing, exits 0 with empty stdout and stderr
AC-2: --help ignore-path prints "Multiple values are accepted." and "Default: [.prettierignore]"
