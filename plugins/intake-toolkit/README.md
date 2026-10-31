# intake-toolkit

Asks the open design questions before anything is built, and writes each answer down with who decided it.

- `/intake-toolkit:intake` takes a GitHub issue, a JIRA key, a pasted description or a rough idea and runs one sequence: requirements, split, explore, interview, receipt. The receipt is the record that a `dev-pipeline` run starts from.
- `plan-interview` surfaces the load-bearing decisions while a plan is forming in plan mode.
- `grill-me` stress-tests a plan or design by interviewing you.
- The `implementability-probe` agent reads a finished spec cold and lists every point it would have to guess.

The explore stage runs a fan-out workflow that ships in `review-toolkit`, so install both.

## What it runs and sends

- Reads and comments on the ticket through `gh` (GitHub Issues) or the Atlassian MCP server you have connected (JIRA), and checks for duplicate tickets the same way.
- Runs `git`, `jq` and `node` on your machine.
- Hook: when you leave plan mode, checks that the plan carries a decision ledger.

## More

[The second-shift README](https://github.com/manoldonev/second-shift#get-started). License: MIT.
