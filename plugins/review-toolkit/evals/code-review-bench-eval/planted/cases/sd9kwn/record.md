# Decision record — #15363 Config file search treats the given file path as a directory

## Summary

The config file search for a file path starts at the folder that holds the file, in
`resolveConfig`, `resolveConfigFile` and `--find-config-path`, so a directory that happens to
share the file's name is never searched.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Where the search for a file path starts | At the folder that holds the file, then upward, in both `loadPrettierConfig` and `resolveConfigFile`. | user-answered | intent |
| D-2 | Where the search starts with no path | At the working directory, as before. | user-answered | intent |
| D-3 | The invalid configuration message with no file path | `Invalid configuration:` followed by the error, with no file part. | user-answered | intent |
| D-4 | What the tests cover | `config-resolution.js`: the API and `--find-config-path` at two folder levels that each hold a config file, and the not-found error. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2

AC-1: resolveConfigFile and --find-config-path return .prettierrc for file.js and directory/.prettierrc for a file under directory/
AC-2: --find-config-path on a path with no config file above it prints the not-found error and exits 1
