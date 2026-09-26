# second-shift in this repo — what you're consenting to

This repo tracks the [second-shift](https://github.com/manoldonev/second-shift) plugin
marketplace at `main` (see `.claude/second-shift.lock.json`). **This is the canary
exception, on purpose:** this repo IS the marketplace, consuming itself to dogfood every
change — real consumers get a pinned release tag via `/second-shift:onboard`; only the
canary tracks latest. When you trust this workspace, Claude Code will ask to install the
marketplace and these plugins. The trust dialog says "arbitrary code with your
privileges" — this file is the inventory of what that actually is, so you can decide
BEFORE the prompt.

The exact plugin→version set is owned by `.claude/second-shift.lock.json` (single source; this
repo enables `dev-pipeline`, `review-toolkit`, `intake-toolkit`, `audit-toolkit`, `second-shift`) — `/second-shift:doctor` verifies the install against it.

## What each plugin installs and when its code runs

### dev-pipeline
- Skills: `run` (the lane's front door, invoked as `/dev-pipeline:run <ticket>`), `build` (the build in your own session, invoked as `/dev-pipeline:build <ticket>`: it makes the same claim, worktree and record-commit writes as `/dev-pipeline:run` below, posts a closing comment naming the handoff, then leaves the build, push and PR to your session), `review` (the manual review, invoked as `/dev-pipeline:review <pr>` from its own session), `pr-revision` — loaded only when invoked.
- What `/dev-pipeline:run` does when you invoke it: its scheduler (`run.sh`) swaps the ticket's queue label for the claimed one and posts a claim comment, creates a git worktree beside this repo (`../<repo>-worktrees/<ticket>`), commits the ticket's intake record as the branch's first commit and pushes it, then runs rounds of fresh `claude -p` sessions — a BUILD session that edits code, pushes and opens a ready PR, then a REVIEW session that posts one verdict comment on the PR. Sessions run with edits accepted, no permission prompts and an explicit tool allowlist derived from your config and the record. Between them the scheduler runs your configured checks (`commands.*`) and the record's `## Checks` in the worktree. Every session is bounded by wall-clock time, and every run by rounds, check reds and a cost ceiling (`run.*` in the config); the run's cost is posted in the PR body. It never merges.
- **Every decision names who made it.** The intake record is the build's binding input. A build that departs from a row edits that row in place — new resolution, who decided (`user-delegated` when the agent decided under your standing delegation), one-line reason — and the review scores it `departed`; a silent departure scores `violated` and blocks approval.
- Hook: a PreToolUse gate on `git commit` commands (normal and bot-identity forms) that runs the repo's type-check on staged changes.
- Shell tools (`run.sh`, `config-lint.sh`, `gh-bot.sh`, `bot-commit.sh`, `claim-issue.sh`…) run only when `/dev-pipeline:run`, `/dev-pipeline:build`, the lane's sessions or a `/second-shift:*` command invokes them; run logs live in `.claude/pipeline-state/`.

### review-toolkit
- Skills: `review-lead`, `mutation-review`, `reviewer-baseline` — loaded only when invoked.
- Agents: the reviewer panel (scope-completeness, security, performance, maintainability, complexity, db, pipeline, a11y, test-coverage, unit-test-mutation, spec, plan reviewers, …) — dispatched only by review runs. A pipeline review round dispatches scope-completeness only unless the config's `reviewers.default` or the ticket's Decision Ledger opts others in.
- Hooks: two PreToolUse gates on `git commit` commands — reviewer-reference drift check and model-tier lockstep check.

### intake-toolkit
- Skills: `intake` (front door), `intake-interviewer`, `intake-orchestrator`, `plan-interview` (Decision Ledger), `grill-me`, `decomposition-reviewer`, `interviewing-baseline` — loaded only when invoked.
- Hook: a PreToolUse gate on ExitPlanMode (checks a Decision Ledger exists when a plan is submitted).

### audit-toolkit
- Hooks: PostToolUse / PostToolUseFailure / SubagentStop / UserPromptExpansion → appends one JSONL line per tool call to the repo-local audit ledger (observability only; never blocks anything).
- Skills: `audit`, `audit-history` for querying the ledger — loaded only when invoked.

### second-shift
- Skills: `onboard`, `doctor`, `local-dev-refresh`. Zero session hooks, zero agents — near-zero session cost.
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
