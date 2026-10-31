# dev-pipeline

Takes a ticket whose open questions are already answered and turns it into a reviewed pull request. A separate session that did not write the code reviews it and leaves its verdict as a PR comment. Merging stays with you.

- `/dev-pipeline:run` drives a scheduler that claims the ticket, starts fresh build and review sessions, runs your configured checks itself, and stops when a review approves the current head or a budget runs out.
- `/dev-pipeline:build` runs the build in your own session so you can steer it.
- `/dev-pipeline:review` reviews a pipeline PR by hand.

A run needs the intake record that `intake-toolkit` writes, and the repo config that `/second-shift:onboard` writes (`.claude/second-shift.config.json`).

## What it runs and sends

- Starts `claude` sessions on your machine and your subscription.
- Runs `git` (branches, worktrees, commits, pushes) and `gh` (issues, labels, pull requests, comments) against your repo. Under JIRA it uses the Atlassian MCP server you have connected.
- Runs the install, lint, typecheck and test commands from your config.
- If configured: polls a readiness URL you set with `curl`, and mints a GitHub App token at `api.github.com` for an optional bot identity.
- Hook: before `git commit`, runs your configured typecheck when JS/TS files are staged.

## More

[The second-shift README](https://github.com/manoldonev/second-shift#get-started). License: MIT.
