# review-toolkit

Parallel code review by specialist reviewers, for any pull request or local diff.

- `/review-toolkit:review-lead` picks the reviewers a change needs, runs them in parallel and merges their findings into one report.
- Reviewer agents: scope completeness against the ticket, security, performance, maintainability, complexity, database, async pipelines, accessibility, test coverage, unit-test mutation, and plan and spec reviewers.
- `mutation-review` and `reviewer-baseline` are the shared protocols the reviewers follow.

Per-repo reviewer choices and model tiers come from `.claude/second-shift.config.json`; domain rules come from optional extension files in the repo.

## What it runs and sends

- Reads the diff with `git` and the pull request and linked issue with `gh`. Under JIRA it reads the ticket through the Atlassian MCP server you have connected.
- Runs its review fan-out as a Claude Code workflow under `node`, on your machine and your subscription.
- Hooks: before a commit, checks that reviewer references and model tiers in the repo point at real files and valid tiers.
- The `evals/` folder holds maintainer-run benchmarks. Nothing in it runs unless you start it.

## More

[The second-shift README](https://github.com/manoldonev/second-shift#get-started). License: MIT.
