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
- Skills: `run-lean` (the default ticket→PR lane, invoked as `/dev-pipeline:run-lean`, gated by five artifact milestones), `review-lean` (the review half of that lane, invoked as `/dev-pipeline:review-lean <pr>` from its own session — a build run cannot author its own verdict), `run` (the 10-stage ticket→PR state machine, invoked as `/dev-pipeline:run`, deprecated — kept as an ablation/rollback lane), `pipeline-retro`, `perf-retro`, `pr-revision` — loaded only when invoked.
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
- **Its gate strength depends on your tracker.** Under `tracker.type: github` the build run's
  identity comes from a bot-authored marker comment the harness posts on the PR, and the
  verdict's independence is checked against it. Under `tracker.type: jira`, `config-lint` forbids
  `tracker.bot`, so there is no authenticated writer for that marker: the identity arm reports
  itself unavailable at reduced strength — printed on every run, never silently skipped — while
  every other arm still gates. The tracker/source-control axis split that would close this gap
  is a schema change and ships separately.

## Opting out (sanctioned, personal)

Put `"<plugin>@second-shift": false` in `.claude/settings.local.json` (NOT user settings —
project precedence wins; and never edit the shared `.claude/settings.json` for a personal
preference). The uninstall dialog's "disable for you alone" writes exactly this.
`/second-shift:doctor` will note what you gave up, once, and stop there.

## Support boundary

The full suite at the pinned tag is the supported artifact. A review-only subset
(review-toolkit alone) is documented but community-supported. Any other subset: possible
via `enabledPlugins: false`, yours to own.
