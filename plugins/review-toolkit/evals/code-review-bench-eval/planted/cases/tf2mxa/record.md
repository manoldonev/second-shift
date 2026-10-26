# Decision record — #16146 CLI: Exit code is 0 when --check is specified and "no parser could be inferred" (since version 3.1)

## Summary

When the CLI cannot infer a parser for a matched file, it reports the error and the run fails with exit
code 2 under `--check`, `--list-different` and `--write` alike, and the `--check` summary says that an
error occurred. Unknown files found by expanding a directory stay silent, as before.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Exit code for a file with no inferable parser | 2, the same as any other formatting error, whatever the mode (`--check`, `--list-different`, `--write`). | user-answered | intent |
| D-2 | The `--check` summary when files errored | "Error occurred when checking code style in the above file." or "in N files.", printed instead of the success or unformatted-files summary. | user-answered | intent |
| D-3 | How formatFiles knows which errors to count | `handleError` returns `true` when it skipped an unknown file, and formatFiles counts every other error. | user-answered | intent |
| D-4 | Unknown files found by expanding a directory | Still skipped silently, not counted, and they do not change the exit code. | user-answered | intent |
| D-5 | What the tests cover | `infer-parser.js` for the exit codes and the summary, `patterns-dirs.js` for directory and glob patterns. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2 AC-3

AC-1: prettier --check FOO, --list-different FOO and the same with --write exit with status 2 when FOO has no inferable parser
AC-2: prettier --check on such a file prints "Error occurred when checking code style in the above file."
AC-3: prettier -l dir1 dir2/**/* skips the unknown file inside dir1 and fails only for the unknown file the glob matched
