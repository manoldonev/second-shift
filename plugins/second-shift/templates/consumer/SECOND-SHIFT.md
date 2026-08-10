# second-shift in this repo — what you're consenting to

This repo pins the [second-shift](https://github.com/manoldonev/second-shift) plugin
marketplace at `{{REF}}` (see `.claude/second-shift.lock.json`). When you trust this
workspace, Claude Code will ask to install the marketplace and these plugins. The trust
dialog says "arbitrary code with your privileges" — this file is the inventory of what
that actually is, so you can decide BEFORE the prompt.

The exact plugin→version set is owned by `.claude/second-shift.lock.json` (single source; this
repo enables {{PLUGIN_LIST}}) — `/second-shift:doctor` verifies the install against it.

## What each plugin installs and when its code runs

### dev-pipeline
- Skills: `run-lean` (the default lane's front door, invoked as `/dev-pipeline:run-lean` — a scheduler that spawns the two blocks below in fresh sessions and authors nothing), `build-lean` (the build half, invoked as `/dev-pipeline:build-lean <ticket>`, gated by five artifact milestones), `review-lean` (the review half, invoked as `/dev-pipeline:review-lean <pr>` from its own session — a build run cannot author its own verdict), `run` (the 10-stage ticket→PR state machine, invoked as `/dev-pipeline:run`, deprecated — kept as an ablation/rollback lane), `pipeline-retro`, `perf-retro`, `pr-revision` — loaded only when invoked.
- Hook: a PreToolUse gate on `git commit` commands (normal and bot-identity forms) that runs the repo's type-check on staged changes during pipeline commits.
- Shell tools (statectl, verifyctl, config-lint, pipeline-doctor…) run only inside pipeline stages; run state lives in `.claude/pipeline-state/`.

### review-toolkit
- Skills: `review-lead`, `mutation-review`, `reviewer-baseline` — loaded only when invoked.
- Agents: the 17-strong reviewer panel (security, performance, maintainability, complexity, db, scope-completeness, test-coverage, a11y, spec, plan, mutation reviewers, review-lead synthesis, …) — dispatched only by review runs.
- Hooks: two PreToolUse gates on `git commit` commands — reviewer-reference drift check and model-tier lockstep check.

### intake-toolkit
- Skills: `intake` (front door), `intake-interviewer`, `intake-orchestrator`, `plan-interview` (Decision Ledger), `grill-me`, `decomposition-reviewer`, `interviewing-baseline` — loaded only when invoked.
- Hook: a PreToolUse gate on ExitPlanMode (checks a Decision Ledger exists when a plan is submitted).

### design-toolkit (only present if this repo enabled it)
- Skills: `design-faithful` / `design-faithful-spec`, `figma-faithful` / `figma-faithful-spec`, and `figma-iterate`; six design/figma reviewer + translation agents. The active provider is selected by this repo's config (`design.provider`: `figma` needs a Figma MCP connection; `claude-design` does not). No hooks.

### audit-toolkit
- Hooks: PostToolUse / PostToolUseFailure / SubagentStop / UserPromptExpansion → appends one JSONL line per tool call to the repo-local audit ledger (observability only; never blocks anything).
- Skills: `audit`, `audit-history` for querying the ledger — loaded only when invoked.

### second-shift
- Skills: `onboard`, `doctor`, `local-dev-refresh`. Zero session hooks, zero agents — near-zero session cost.
- Optional committed CI files (present only if you enabled the evidence workflow at onboard):
  `.github/workflows/second-shift-ci.yml` + `.claude/tools/second-shift-ci-check.sh`. These run
  in **GitHub Actions on your PRs** (not in a Claude session — no session cost). Three checks:
  config-lint the committed config at the pinned marketplace ref; assert the settings ref and
  lockfile ref agree; and, on a `/dev-pipeline:run-lean` PR, assert the merge-boundary evidence
  the lean lane is supposed to leave — a committed approve-verdict carrying reconciliation keys,
  a review identity distinct from the build run's, a verdict covering *this* head, and no
  unratified intent-gap record. The workflow only reports a check; it blocks a merge only if you
  mark it a required status check in branch protection.
- **The lean evidence check is fail-closed.** Missing evidence is a failure, and so is a check
  that could not run: a moved script path at your pinned ref (HTTP 404) or a shallow checkout is
  reported as drift, never waved through green. Only a network/auth blip fetching the script is
  a non-fatal warning. Nothing about it is model-driven and it makes no API-billed calls.
- **If you hand-maintain that workflow, keep its `permissions:` block intact.** The identity arm
  reads the PR's comment trail, so the job needs `contents: read` **plus `issues: read` and
  `pull-requests: read`**. A `permissions:` key replaces the workflow defaults wholesale — any
  scope you leave out is `none`, with no public-repo exception — so dropping either read denies
  that call and reds every lean PR with an environment error. Read scopes only: the job executes
  a script fetched from the marketplace repo at your pinned ref, which inherits this token.
- **Its gate strength depends on your bot, not on your tracker.** The build run's identity
  comes from a bot-authored marker comment the harness posts on the PR, and the verdict's
  independence is checked against it. Configure `tracker.bot` — legal under **either**
  `tracker.type`, because source control is GitHub for every adapter — and that arm gates at
  full strength. Without one there is no authenticated writer for the marker, so the identity
  arm reports itself unavailable at reduced strength, printed on every run and never silently
  skipped, while every other arm still gates.
- Optional committed CI files (emitted by the same acceptance as the pair above):
  `.github/workflows/second-shift-unclaim.yml` + `.claude/tools/second-shift-unclaim.sh`. Also
  **GitHub Actions, not a Claude session**, but unlike the pair above this one **writes**: when an
  issue closes it removes the pipeline's two run-state labels (`tracker.labels.claimed` and
  `tracker.labels.queue`, resolved from your committed config) from that one issue. Never
  `tracker.labels.blockers` — those are permanent classifications, not run state. That is the
  entire `issues: write` grant, and it needs your repo's Actions workflow permissions set to
  read-and-write. Nothing else releases those labels, so without this a merged ticket stays
  labelled in-progress forever.

## Opting out (sanctioned, personal)

Put `"<plugin>@second-shift": false` in `.claude/settings.local.json` (NOT user settings —
project precedence wins; and never edit the shared `.claude/settings.json` for a personal
preference). The uninstall dialog's "disable for you alone" writes exactly this.
`/second-shift:doctor` will note what you gave up, once, and stop there.

## Support boundary

The full suite at the pinned tag is the supported artifact. A review-only subset
(review-toolkit alone) is documented but community-supported. Any other subset: possible
via `enabledPlugins: false`, yours to own.
