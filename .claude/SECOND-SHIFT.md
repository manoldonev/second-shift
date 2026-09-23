# second-shift in this repo — what you're consenting to

This repo tracks the [second-shift](https://github.com/manoldonev/second-shift) plugin
marketplace at `main` (see `.claude/second-shift.lock.json`). **This is the canary
exception, on purpose:** this repo IS the marketplace, consuming itself to dogfood every
change — real consumers get a pinned release tag via `/second-shift:onboard`; only the
canary tracks latest. When you trust this workspace, Claude Code will ask to install the
marketplace and these plugins. The trust dialog says "arbitrary code with your
privileges" — this file is the inventory of what that actually is, so you can decide
BEFORE the prompt.

| plugin | version |
| --- | --- |
| dev-pipeline | latest (canary) |
| review-toolkit | latest (canary) |
| intake-toolkit | latest (canary) |
| audit-toolkit | latest (canary) |
| second-shift | latest (canary) |

## What each plugin installs and when its code runs

### dev-pipeline
- Skills: `/dev-pipeline:run` (the lane's front door), `/dev-pipeline:review` (the manual review), `pr-revision` — loaded only when invoked.
- `/dev-pipeline:run` drives `run.sh`: it claims the ticket, creates a worktree beside this repo, commits the intake record as the branch's first commit, and runs fresh `claude -p` build and review sessions (edits accepted, no prompts, an explicit tool allowlist) with the configured checks between them, until a review approves the current head or a budget is spent. It never merges.
- Hook: a PreToolUse gate on `git commit` commands (normal and bot-identity forms) that runs the repo's type-check on staged changes.
- Shell tools (`run.sh`, `config-lint.sh`, `gh-bot.sh`, `bot-commit.sh`, `claim-issue.sh`…) run only when the lane or a `/second-shift:*` command invokes them; run logs live in `.claude/pipeline-state/`.

### review-toolkit
- Skills: `review-lead`, `mutation-review`, `reviewer-baseline` — loaded only when invoked.
- Agents: the 17-strong reviewer panel (security, performance, maintainability, complexity, db, scope-completeness, test-coverage, a11y, spec, plan, mutation reviewers, review-lead synthesis, …) — dispatched only by review runs.
- Hooks: two PreToolUse gates on `git commit` commands — reviewer-reference drift check and model-tier lockstep check.

### intake-toolkit
- Skills: `intake` (front door), `intake-interviewer`, `intake-orchestrator`, `plan-interview` (Decision Ledger), `grill-me`, `decomposition-reviewer`, `interviewing-baseline` — loaded only when invoked.
- Hook: a PreToolUse gate on ExitPlanMode (checks a Decision Ledger exists when a plan is submitted).

### audit-toolkit
- Hooks: PostToolUse / PostToolUseFailure / SubagentStop / UserPromptExpansion → appends one JSONL line per tool call to the repo-local audit ledger (observability only; never blocks anything).
- Skills: `audit`, `audit-history` for querying the ledger — loaded only when invoked.

### second-shift
- Skills: `onboard`, `doctor`, `local-dev-refresh`. Zero hooks, zero agents — near-zero session cost.
- Committed CI file that **writes**: `.github/workflows/unclaim-on-close.yml` runs in **GitHub
  Actions, never in a Claude session**. When an issue closes it holds `issues: write` and removes
  the pipeline's two run-state labels (`tracker.labels.claimed` and `tracker.labels.queue`,
  defaulting to `in-progress` / `ready-for-dev` here because this repo's config is gitignored)
  from that one issue. Never `tracker.labels.blockers` — those are permanent classifications. That
  label removal is the whole of the grant; the job runs the shipped template script
  (`plugins/second-shift/templates/consumer/second-shift-unclaim.sh`) in place.

## Opting out (sanctioned, personal)

Put `"<plugin>@second-shift": false` in `.claude/settings.local.json` (NOT user settings —
project precedence wins; and never edit the shared `.claude/settings.json` for a personal
preference). The uninstall dialog's "disable for you alone" writes exactly this.
`/second-shift:doctor` will note what you gave up, once, and stop there.

## Support boundary

The full suite at the pinned tag is the supported artifact. A review-only subset
(review-toolkit alone) is documented but community-supported. Any other subset: possible
via `enabledPlugins: false`, yours to own.
