# CLI: Exit code is 0 when --check is specified and "no parser could be inferred" (since version 3.1)

**Environments:**

- Prettier Version: 3.1.0, 3.2.5, 3.0.3
- Running Prettier via: CLI
- Runtime: Node 20
- Operating System: MacOs
- Prettier plugins (if any): none

**Steps to reproduce:**

```Bash
➜  atswui git:(ci_setup) ✗ yarn add prettier@3.0.3
➤ YN0000: · Yarn 4.1.1
➤ YN0000: ┌ Resolution step
➤ YN0085: │ + prettier@npm:3.0.3
➤ YN0085: │ - prettier@npm:3.1.0
➤ YN0000: └ Completed
➤ YN0000: ┌ Fetch step
➤ YN0000: └ Completed in 0s 345ms
➤ YN0000: ┌ Link step
➤ YN0000: └ Completed in 0s 244ms
➤ YN0000: · Done in 0s 778ms
➜  atswui git:(ci_setup) ✗ yarn check:formatting
Checking formatting...
[warn] src/app/app.component.html
yarn.lock
[error] No parser could be inferred for file "/Users/adam/Documents/Projects/github.com/crewlinker/atswui/yarn.lock".
[warn] Code style issues found in the above file. Run Prettier to fix.
➜  atswui git:(ci_setup) ✗ echo $?
1
➜  atswui git:(ci_setup) ✗ yarn add prettier@3.1.0
➤ YN0000: · Yarn 4.1.1
➤ YN0000: ┌ Resolution step
➤ YN0085: │ + prettier@npm:3.1.0
➤ YN0085: │ - prettier@npm:3.0.3
➤ YN0000: └ Completed
➤ YN0000: ┌ Fetch step
➤ YN0000: └ Completed in 0s 300ms
➤ YN0000: ┌ Link step
➤ YN0000: └ Completed in 0s 219ms
➤ YN0000: · Done in 0s 706ms
➜  atswui git:(ci_setup) ✗ yarn check:formatting
Checking formatting...
yarn.lock
[error] No parser could be inferred for file "/Users/adam/Documents/Projects/github.com/crewlinker/atswui/yarn.lock".
All matched files use Prettier code style!
➜  atswui git:(ci_setup) ✗ echo $?
0
```

The command "check:formatting" runs: `"check:formatting": "prettier --check \"**/*\""`
Note: it is also an issue in the latest version

**Expected behavior:**
Should exit with status code 1
**Actual behavior:**
Exits with status code 0 since version 3.1.0

## Acceptance criteria

- AC-1: `prettier --check` and `prettier --list-different`, with or without `--write`, exit with code 2 when a matched file has no inferable parser.
- AC-2: Under `--check`, the summary after such an error reads "Error occurred when checking code style in the above file." (or "in N files.") instead of "All matched files use Prettier code style!".
- AC-3: A file with no inferable parser that was found by expanding a directory pattern is still skipped silently and does not change the exit code.
