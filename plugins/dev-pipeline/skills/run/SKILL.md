---
name: run
description: 'Fully autonomous pipeline: GitHub issue → branch → implement → review → PR'
---

# Dev Pipeline

Fully autonomous pipeline: GitHub issue → branch → implement → review → PR.

**Runtime:** Claude Code CLI with `--permission-mode auto`. Not designed for GitHub Actions — the pipeline depends on Claude Code's Agent tool for intake, planning, implementation, and code review. See issue #52 for the CI-native architecture design.

**How to run:**

One default mode plus a diagnostic escape hatch. The pipeline runs interactively in a Claude Code session (subscription-covered per ADR-015); the interactive escape hatch is for manual recovery and first-use priming, not a normal way to run the pipeline.

**Default — `/dev-pipeline:run <issue-number>`** in your existing Claude Code session. Runs all stages (1–10) in this one session with no prompts at the gates (autonomous fail-fast contract — see "Skill-body failure contract" below) and ends with a draft PR URL. Stage 8's reviewer fan-out runs as fresh `agent()` calls inside the `Workflow` script (`workflows/code-review.mjs`), so each reviewer gets clean context; synthesis runs in-session on the caller's model.

**Diagnostic fallback — `DEV_PIPELINE_MODE=interactive /dev-pipeline:run <issue-number>`.** Not a peer mode; a manual-recovery / first-use-priming escape hatch. Same single-session in-process flow as the default, but the per-stage gates **prompt** for a decision instead of taking the autonomous fail-fast write. Use only when an autonomous abort needs to be debugged interactively — e.g., stepping through after a `failureContext.reason` was written.

```bash
# Batch mode (processes issues until queue is empty), in an interactive session:
claude --permission-mode auto
# then type: /ralph-loop:ralph-loop "/dev-pipeline:run" --max-iterations 10 --completion-promise "No issues in queue"
```

Stage 8 is the highest-stakes synthesis in the pipeline (review-toolkit:review-lead dedup + Scope Completeness Gate). It gets clean context where it matters most — at the reviewer layer — because each reviewer runs as a fresh `agent()`.

**Design-driven runs (interactive only).** The **design-provider axis** (config `design.provider`) selects the design-fidelity adapter; a run is `designDriven` when the provider is set **and** the issue carries a provider-appropriate handoff link. Stage 1 detects + records it, Stage 3 produces a faithful FE spec via the selected engine, Stage 5 implements the screen in `apps/web` via the engine + a live-render verify gate, and Stage 8 routes the provider's fidelity reviewer + `review-toolkit:a11y-reviewer`. Two providers: **`claude-design`** — a `claude.ai/design/...` link read via the `design-sync.mjs` engine + **DesignSync** tool (reviewer `design-toolkit:design-faithful-reviewer`); **`figma`** — a `figma.com/...` link read via the `figma.mjs` engine + **Figma MCP**, dispatched from the BE session against the FE worktree (reviewer `design-toolkit:figma-faithful-reviewer`). Both reads need interactive auth (design scopes / MCP) — so **run a design-driven issue interactively, not headless**. A headless run fails closed `design-source-unreachable` at the first design read (it does not guess a contract). The mode is off by default: with `design.provider` absent, an issue runs exactly as before. Full state contract: state-schema.md **Design Mode**.

**Design docs:**

- `docs/plans/2026-03-24-dev-pipeline-design.md` (original pipeline design)
- `docs/plans/2026-03-28-intake-orchestrator-design.md` (intake orchestrator + decomposition)
- `docs/plans/2026-03-29-pr-revision-design.md` (PR revision companion skill)

**Companion skills:**

- `/pr-revision` — addresses human PR review comments after a PR is opened

## Tracker adapters

The pipeline is tracker-agnostic in its machinery (statectl, verifyctl, the stage
state-machine, keyed off `ticketKey`) and tracker-specific only at its edges. Config
**`tracker.type`** selects the adapter; the prose in this SKILL and the stage files is
the **github** default, with per-stage "Tracker delta (jira)" callouts marking what
changes under the JIRA adapter. Full contract + the operation-by-adapter table:
[`tools/tracker/README.md`](./tools/tracker/README.md).

- **github** (`tracker.type: github`, `tracker.writes: true`) — the queue-and-claim model:
  labelled work queue, atomic claim ([`tools/claim-issue.sh`](./tools/claim-issue.sh)),
  bot-authored status comments. This is what the Pre-flight, Bot Identity, and Stage
  1/8/9 sections below describe.
- **jira** (`tracker.type: jira`, `tracker.writes: false`) — the read-only
  model: operator supplies the JIRA key, the ticket is fetched **read-only** via the
  Atlassian MCP (`mcp__atlassian__getJiraIssue`), and **no stage writes to the tracker**
  (no transitions, no comments — the state file + draft-PR metadata are the audit
  trail). No bot claim; the Pre-flight bot/label gate below does not apply.
  See [`tools/tracker/jira/README.md`](./tools/tracker/jira/README.md).

Shared, tracker-independent config: `tracker.keyPattern` (statectl init validation)
and `tracker.branchPrefix` (branch namespace — `claude/acme-` github, `jdoe/` jira).

## Prerequisites

- Claude Code CLI installed (`claude --version`)
- `--permission-mode auto` — the auto-approval permission classifier the pipeline runs under
- `gh auth status` must succeed
- Repository must have the required labels (config `stageParams.requiredLabels`; default = `ready-for-dev`, `needs-spec-work`, `needs-plan-review`, `needs-intake-review`, `in-progress`, `epic`)
- Worktree base dir: config `topology.repos.<host>.worktreesDir`

**Verify all of the above in one shot with [`tools/pipeline-doctor.sh`](./tools/pipeline-doctor.sh)** — run it before the first pipeline run on a new machine and after any environment change (gh upgrade, key rotation, OS update). It checks core tools, gh auth + the two known gh feature breakages (Projects-classic GraphQL deprecation, missing `pr list --head`), bot-wrapper token minting, required labels, worktree dir, cost-tracking preconditions, AND runs the full statectl selftest so the state machine (including `mark-failed` failure paths) is proven on the machine that will depend on it, plus the `null-reviewer-selftest.mjs` that proves the Stage 8 dark-reviewer retry contract (and that `code-review.mjs` still carries its load-bearing tokens). Exit code = number of failed checks; WARN lines are degraded-but-runnable.

**Onboarding finish line — [`tools/preflight.sh`](./tools/preflight.sh) (read-only).** Where doctor verifies the *environment*, preflight verifies the *whole first contact* without a mutating run: it echoes the resolved targets (tracker/repos/branches + string-only worktree paths — no `statectl init`, no `git worktree add`), runs the config gates (`config-lint.sh`, `check-extensions.sh`), invokes `pipeline-doctor.sh` as its environment section, performs ONE tracker READ (no claim — `gh api issues/<key>` with a ticket key, the queue head via `gh issue list` without one; the jira adapter SKIPs with a note since its fetch is session-side MCP), executes every non-null command lane once in the current checkout (source-mutating lanes — `format` configured as a string, `lint` with `lintAutofixes: true` — are SKIPped with a note, never run), and writes `.claude/pipeline-state/preflight-report.md`. Zero tracker/git/remote mutations, proven by `preflight-selftest.sh`'s zero-write suite. `/second-shift:onboard` invokes it as its final step; run it manually with `bash "${CLAUDE_PLUGIN_ROOT}/skills/run/tools/preflight.sh" [<ticket-key>]`. Exit code = number of failed checks (doctor convention).

## Pre-flight: Environment gate

Run this **first**, before generating `RUN_ID` and before Stage 1.A's claim sequence. It is issue-independent (it validates the host/repo, not a specific issue) and is a fast, load-bearing **subset** of `pipeline-doctor.sh` — the two prerequisites the pipeline cannot recover from mid-run: the bot wrapper (every GitHub write assumes it) and the required label set (claim, escalation, and decomposition all mutate these labels). The full doctor (gh-feature probes, token minting, selftest, cost preconditions) remains the recommended one-shot check on a new machine; this gate just guarantees the two essentials at every entry.

A failure here is an **abort-with-instructions**, not a `failureContext` write: no issue is claimed yet, so there is no state file and nothing to comment on. Print the onboarding error to stderr and exit non-zero — this is the one pipeline stop that legitimately exits non-zero (it precedes the autonomous fail-fast contract, which only governs post-claim stages). Under `DEV_PIPELINE_MODE=interactive` the behavior is identical (the gate never prompts; a missing prerequisite is unrecoverable in-session either way).

```bash
# (0) Config validation — tracker-agnostic, runs for BOTH adapters. config-lint
# ships INSIDE this plugin so an installed-cache consumer can run it. Fails fast
# on a malformed .claude/second-shift.config.json before any tracker work.
# config-lint validates the SHAPE of stageWorkflows[] (stage 1-10, non-empty
# name/workflow, unique names). The Pre-flight config gate additionally FAILS
# CLOSED on an UNRESOLVABLE stageWorkflows[].workflow reference — every workflow
# must resolve to a <plugin>:<relpath> in the plugin cache or an existing repo-
# relative path (a blocking extension gate must never silently skip). See the
# Stage write convention below.
CFG="${SECOND_SHIFT_CONFIG:-.claude/second-shift.config.json}"
if [[ -f "$CFG" ]]; then
  bash "${CLAUDE_PLUGIN_ROOT}/skills/run/tools/config-lint.sh" "$CFG" \
    || { echo "[pre-flight] FAIL: config-lint rejected $CFG (see errors above)" >&2; exit 1; }
fi

# (0b) Extension integrity — EP-3 manifest lint + EP-6/EP-7 reference resolution
# (check-extensions.sh). Runs REGARDLESS of config presence: (1) a typo'd
# extension file under .claude/second-shift/ (e.g. blocker-mutants.md.md) must be
# LOUD, not silently degraded to generic behavior — the EP-3 guarantee; and (2)
# every stageWorkflows[].workflow / implementDelegates[].agent reference must
# resolve on disk (a bare repo-relative path/agent) — a mis-referenced blocking
# extension must never degrade to a skipped dispatch. Fail closed. No-op (exit 0)
# when neither an extension dir nor config references exist.
bash "${CLAUDE_PLUGIN_ROOT}/skills/run/tools/check-extensions.sh" . \
  || { echo "[pre-flight] FAIL: check-extensions rejected the repo (a typo'd .claude/second-shift/ extension file or an unresolvable EP-6/EP-7 reference — see errors above)" >&2; exit 1; }

# The remaining github-adapter checks below apply only when config `tracker.type: github`
# (a jira repo has no bot wrapper / label queue — skip 1 and 2).
# When config `tracker.bot.enabled`, the bot wrapper is installed by
# `tools/install-gh-bot.sh` and exported as the env var named by
# `tracker.bot.envVar` (default GH_BOT). Reference it via $GH_BOT below.

# (1) Bot wrapper must exist and be executable.
if [[ ! -x "$GH_BOT" ]]; then
  echo "[pre-flight] FAIL: bot wrapper missing or non-executable at $GH_BOT" >&2
  echo "[pre-flight]   Bootstrap it with a freshly downloaded App private key:" >&2
  echo "[pre-flight]   bash \"${CLAUDE_PLUGIN_ROOT}/skills/run/tools/install-gh-bot.sh\" <private-key.pem>" >&2
  exit 1
fi

# (2) Required label set must exist in the repo (one read, then assert each).
# Precedence (#11): the tracker.labels role vocabulary (union of queue + claimed +
# blockers) is authoritative when set — the SAME labels the queue/claim/guard sites
# consume, so the existence check can never drift from the used set (F75's
# structural fix). Falls back to the legacy flat stageParams.requiredLabels, then
# the shipped six. An absent config / absent keys reproduce the six byte-for-byte.
# (while-read, not mapfile — macOS ships bash 3.2.)
REQUIRED_LABELS=()
if [[ -f "$CFG" ]]; then
  # tracker.labels union first (empty when tracker.labels absent).
  while IFS= read -r l; do REQUIRED_LABELS+=("$l"); done \
    < <(jq -r '(.tracker.labels // {}) | ([.queue, .claimed] + (.blockers // [])) | map(select(. != null and . != "")) | .[]' "$CFG" 2>/dev/null)
  # legacy stageParams.requiredLabels when tracker.labels gave nothing.
  if (( ${#REQUIRED_LABELS[@]} == 0 )); then
    while IFS= read -r l; do REQUIRED_LABELS+=("$l"); done \
      < <(jq -r '.stageParams.requiredLabels // empty | .[]' "$CFG" 2>/dev/null)
  fi
fi
if (( ${#REQUIRED_LABELS[@]} == 0 )); then
  REQUIRED_LABELS=(ready-for-dev needs-spec-work needs-plan-review needs-intake-review in-progress epic)
fi
HAVE_LABELS=$(gh api "repos/{owner}/{repo}/labels?per_page=100" --jq '.[].name' 2>/dev/null)
# Distinguish "gh call failed" (empty result → would mis-report ALL labels missing)
# from "labels genuinely absent". An empty read here means gh itself failed.
if [[ -z "$HAVE_LABELS" ]]; then
  echo "[pre-flight] FAIL: could not read repo labels (gh api returned nothing) — check 'gh auth status' and network." >&2
  exit 1
fi
MISSING=()
for l in "${REQUIRED_LABELS[@]}"; do
  grep -qx "$l" <<< "$HAVE_LABELS" || MISSING+=("$l")
done
if (( ${#MISSING[@]} > 0 )); then
  echo "[pre-flight] FAIL: required label(s) missing in repo: ${MISSING[*]}" >&2
  echo "[pre-flight]   Create them (gh label create <name>) or run \"${CLAUDE_PLUGIN_ROOT}/skills/run/tools/pipeline-doctor.sh\" for the full check." >&2
  exit 1
fi
echo "[pre-flight] OK: bot wrapper present, all required labels exist."
```

## Pre-flight: Generate RUN_ID

Generate `RUN_ID` once for the entire run, BEFORE any other action — `statectl init` requires `--run-id`, so the value must already be set when Stage 1.A's claim sequence calls it:

```bash
RUN_ID="$(date -u +%Y-%m-%dT%H%M%SZ)-$(hostname -s)-$(openssl rand -hex 4)"
```

Format: `{ISO timestamp}-{hostname}-{random 8 hex chars}`. `RUN_ID` is persisted to top-level `.runId` in the state file by the first `statectl init --run-id "$RUN_ID"` call (Stage 1.A's claim sequence). On the normal path it stays in memory for the whole single-session run; if a **crash-recovery resume** re-enters mid-pipeline in a fresh session, the same `RUN_ID` is read back from state via `statectl get "$ISSUE" '.runId'` so comments from the original session and the resumed one share the same `<!-- run_id: ... -->` marker.

## Invocation Routing

All stages (1–10) run in a single Claude Code session, in-process. The skill routes on one thing only: whether the per-stage gates take the autonomous fail-fast write or **prompt** for a decision.

The mode is read from a single env var, `DEV_PIPELINE_MODE`, with values `auto | interactive` (default: `auto`):

- `auto` (default) — autonomous: gates take the fail-fast write and stop emitting tool calls. No input-requesting prompts on any code path.
- `interactive` — gates **prompt** for a decision instead. A debugging hatch for stepping through an abort; otherwise identical to `auto`.

### Mode resolution

Routing-gate sites read `DEV_PIPELINE_MODE` directly:

- `DEV_PIPELINE_MODE` set + valid (`auto` | `interactive`) → use it.
- `DEV_PIPELINE_MODE` set + invalid → exit 3 with stderr error.
- `DEV_PIPELINE_MODE` unset or empty → default to `auto`.

## Skill-body failure contract

**Universal invariant — no input-requesting prompts on any code path** (happy or failure) under the default `auto` mode. The pipeline runs in a Claude Code session but the skill body never blocks on user input. Input-requesting prompts are an explicit opt-in via `DEV_PIPELINE_MODE=interactive`.

Failure paths invoke the `statectl mark-failed` helper which writes the failure atomically:

```bash
statectl.sh mark-failed "$ISSUE" \
  --reason <documented-enum-value> [--stage N] [--json '<details>']
```

This single call writes `failureContext = { stage: N, reason, ...details }` + `status: "failed"` + `stages.{N}.status: "failed"` + `stages.{N}.completedAt` in one atomic write. `--stage` is omitted for pre-Stage-1 failures (routing rejects, Target Confirmation rejects) — for those the `failureContext` object has no `stage` field. After the call, exit cleanly with rc=0; the session stops emitting tool calls.

Per-stage failure points (Pre-Stage-1 routing reject, Stages 4, 6, 8 crash-recovery resume, 9) cite only the `failureContext.reason` string and any stage-specific payload at the call site. Resume from a `failed` state is also no-prompt: the in-session path reads state and exits. Operator clears the failed state manually (`rm .claude/pipeline-state/{issue}.json`, or reset `status: "in_progress"` + `currentStage` + clear `failureContext`) before re-running. **Authoritative index of all `failureContext.reason` values is in [`state-schema.md`](./state-schema.md#failurecontextreason-index); `statectl mark-failed` validates the reason against this closed enum at write time.**

**Helper-failure contract.** `statectl.sh` errors (validation rejects, precondition violations, JSON parse errors) are infrastructure-fatal: the helper prints `[statectl-error] ...` to stderr and exits non-zero. These do NOT route through `failureContext.reason` (would require a `statectl-error` enum value — out of scope until eval data shows the stderr-only path is too coarse for autonomous mode). The calling session presents the stderr text to the user (interactive) or follows the autonomous abort contract (final assistant turn cites the error and stops emitting tool calls). See `statectl.sh` header comments for the full contract.

### No one-way handoffs

The pipeline has **no** one-way handoff points: every stage flows in-process into the next within a single session. Introducing one would require documenting it here AND in `state-schema.md` so the eval ledger and resume logic stay in sync.

### Interactive mode

**Under `DEV_PIPELINE_MODE=interactive`:** per-stage interactive prompts (defined inline at each stage below) fire INSTEAD of the autonomous fail-fast write. The in-process stage flow is otherwise identical to `auto`, with one additional interactive-only affordance: the Stage 1 **lightweight inline intake** approval gate (see [`stages/1-intake.md`](./stages/1-intake.md) Step 1.B). That gate is an _approval_ prompt rather than a failure gate, and it exists only under interactive mode — `auto` always loads `intake-toolkit:intake-orchestrator` + the intake-toolkit:spec-reviewer/intake-toolkit:codebase-explorer fan-out. Both prompt kinds (failure gates and the inline-intake approval) are the var's effect; neither fires in `auto`.

**On any failure or uncertainty under interactive mode, present the situation to the user and ask how to proceed. Never silently stop.** (Autonomous mode replaces "present to user" with "write `failureContext` and exit" per the contract above.)

## Bot Identity

All GitHub **write** operations (comments, labels, PRs) MUST use the bot wrapper:

```bash
# When config `tracker.bot.enabled`, use the bot wrapper installed by
# `tools/install-gh-bot.sh`, exported as the env var named by `tracker.bot.envVar`
# (default GH_BOT).
# Use $GH_BOT instead of gh for: api POST/PATCH/PUT, pr comment, pr create, issue comment, issue edit
# Use regular gh for: reads (pr view, issue view, api GET)
```

If the wrapper is missing (fresh machine), bootstrap it with [`tools/install-gh-bot.sh`](./tools/install-gh-bot.sh) — it takes a freshly downloaded App private key, installs it to the bot config dir, and generates the wrapper. The pipeline itself never creates the wrapper; a missing wrapper is an abort-with-instructions prerequisite failure.

### Canonical REST forms for issue writes

`gh issue edit`, `gh issue comment`, and `gh issue view --json` hit the Projects-classic GraphQL deprecation on some gh-version + repo combinations (`pipeline-doctor.sh` detects this; it is currently the case in this repo) — the command prints a GraphQL error and **the mutation silently does not apply**. The REST forms below are canonical for all issue writes; use them everywhere the stage files say `$GH_BOT issue comment` / `$GH_BOT issue edit`:

```bash
# Comment (body built in a fresh per-post `mktemp` file first — see "Multi-line comments"
# below for the BODY=$(mktemp …) + rm -f "$BODY" pattern; never a fixed /tmp name):
$GH_BOT api -X POST "repos/{owner}/{repo}/issues/$ISSUE/comments" -F body=@"$BODY"

# Claim swap (ready-for-dev → in-progress): ADD in-progress, confirm the add applied
# from the response body, THEN DELETE ready-for-dev — aborting (exit 1) with
# ready-for-dev intact if the add did not apply (the silent-failed-add guard). Why
# both the order and the confirm are load-bearing: see the Label-swap ordering rule
# below. The helper takes the bot wrapper via $GH_BOT (so it is mockable — see
# tools/claim-selftest.sh). The helper ships in the plugin checkout, NOT the
# de-vendored consumer repo — resolve it via ${CLAUDE_PLUGIN_ROOT}, never CWD-relative:
bash "${CLAUDE_PLUGIN_ROOT}/skills/run/tools/claim-issue.sh" "$ISSUE"

# Label/assignee verification (read) — REST, since `gh issue view --json` may be broken:
gh api "repos/{owner}/{repo}/issues/$ISSUE" --jq '{labels: [.labels[].name], assignees: [.assignees[].login]}'
```

**PR writes hit the same breakage.** `gh pr edit` (body/label mutations) fails with the identical GraphQL error. The REST forms:

```bash
# PR body update (body built in a fresh per-post `mktemp` file — see "Multi-line comments"):
$GH_BOT api -X PATCH "repos/{owner}/{repo}/pulls/$PR_NUMBER" -F body=@"$BODY"

# PR labels — PRs are issues for labeling purposes; use the issues endpoints above with the PR number.
```

(`gh pr create` and `gh pr comment` are unaffected; only `pr edit`-class mutations route through the broken GraphQL path.)

**Label-swap ordering rule (claim safety):** when swapping `ready-for-dev` → `in-progress`, ADD `in-progress` first, THEN remove `ready-for-dev`. With that order, a crash between the two calls leaves the issue carrying both labels (visibly claimed, recoverable). The reverse order leaves a window where the issue has **neither** label — invisible to the `ready-for-dev` queue query AND unclaimed, i.e. silently lost. The same rule applies to any single-call `gh issue edit --add-label X --remove-label Y` fallback that gets split into two REST calls.

**Order alone is not sufficient — confirm the `in-progress` add applied before the `ready-for-dev` removal.** If the add _silently fails_ (e.g. a dropped `--input -` → HTTP 422) and the DELETE then succeeds, the issue lands in the same zero-label window even though the order was correct. **So for the claim swap: assert `in-progress` is present in the add-labels POST response body before issuing the `ready-for-dev` DELETE; if it is not, abort the claim with `ready-for-dev` intact** (`tools/claim-issue.sh` does this). This _confirm_ requirement is scoped to the **claim** swap (the one that drops the queue label `ready-for-dev`); the terminal `in-progress` removals at Stage 4 (`needs-plan-review`) and Stage 9 (completion) are not queue-visibility transitions and keep their single-call form.

### Non-gating writes run in the background

Stage-progress comments and post-claim label edits are **observability, not gates** — nothing downstream reads them in-session. Posting them synchronously costs a REST round-trip per stage boundary (~2–3 min per run in aggregate). Run them in the background (`run_in_background`) and continue to the next step immediately.

**A backgrounded post must own its `mktemp` body cleanup — never `rm` the `--body-file` from the foreground.** Background the _whole_ post-then-`rm` as one unit via the Bash tool's `run_in_background`, so the temp file outlives the post. Do **not** background only the post with a trailing shell `&` and then `rm -f "$BODY"` in the foreground: the `rm` races ahead of the still-reading background job and the post fails with `open … no such file or directory` (observed: a Stage-3 plan comment failed this way and had to be re-posted synchronously). If you cannot background the cleanup with the post, post synchronously.

**Never background** (these ARE load-bearing, in order of appearance): the claim-sequence mutations + verification (Step 1.A — the race guard depends on read-after-write), `statectl` state writes (always synchronous), failure comments + `mark-failed` (the failure contract requires the comment to exist before the session stops), `gh pr create` (Stage 9 reads the URL), and the `pr-add`/label/comment calls in Stage 9's completion sequence when a later step in the same run consumes their result. If a backgrounded post fails, surface it at the end of the run — never silently drop a comment.

**Known limitation:** `--add-assignee @me` does not work via the bot wrapper (the bot is not a GitHub user that can be assigned). Use regular `gh` for assignee operations, or skip assignee management.

### Multi-line comments: build the body, then post (no idempotency guard)

The bot wrapper has no idempotency guard — every invocation posts a fresh comment. For any multi-line issue/PR comment, **build the body in a fresh per-post temp file (`mktemp`), then post via `--body-file`** as two separate steps:

```bash
# Build the body in a fresh per-post temp file — mktemp, NEVER a fixed /tmp name.
BODY=$(mktemp -t dev-pipeline-comment.XXXXXX)
sed "s|__RUN_ID__|$RUN_ID|" <<'EOF' > "$BODY"
<!-- dev-pipeline -->
<!-- run_id: __RUN_ID__ -->
...
EOF

# Then post, and clean up.
$GH_BOT issue comment "$ISSUE" --body-file "$BODY"
rm -f "$BODY"
```

**Use a fresh `mktemp` file per post — never a fixed name like `/tmp/comment-body.md`.** Two pipeline runs on the same machine share a fixed temp name, and even within a single run the non-gating stage-progress comments post in the background (see "Non-gating writes run in the background" above), so two posts can be in flight at once. A shared name means last-writer-wins: one post clobbers another's body and you publish the wrong run's comment under this issue — observed in practice when a concurrent run's code-review summary landed on the wrong thread. A fresh `mktemp` per post (not one file reused per run, and not a `$RUN_ID`-embedded name — `$RUN_ID` is constant within a run and still collides across backgrounded intra-run posts) gives every post its own file. Note the bot wrapper returns the new comment's URL, so `--jq .html_url` confirms the post **landed** — but it does NOT confirm the post's **content**; the per-post temp file is the only real guard against a clobbered body.

**Permission-classifier fallback (same contract, different writer).** Some `auto`-mode permission classifiers deny the compound `mktemp` + heredoc + post command as a single Bash call (observed on a canary run). When that happens, keep the two-step contract but swap the writer: build the body with the harness file-write tool (Write/Edit) at a **unique per-post path** in the session scratchpad, then post it as its own small command — `$GH_BOT api -X POST "repos/{owner}/{repo}/issues/$ISSUE/comments" -F body=@"$FILE"`. The fresh-file-per-post rule is unchanged; only the file author moves from the shell to the harness.

**Never** combine the heredoc and the post in one inline construct like:

```bash
# WRONG — posts immediately, then sed processes the bot's stdout (the URL), not the body.
$GH_BOT issue comment "$ISSUE" --body "$(cat <<EOF
...
EOF
)" | sed "s|__RUN_ID__|$RUN_ID|" > /tmp/comment-body.md
```

Combining them is how duplicate-post bugs happen: the inline `--body "$(...)"` posts the comment first, the downstream `sed | tee` only captures the bot's stdout (the comment URL) into a junk file, and the operator — thinking they were "preparing a body" — re-runs the post a second time. If you find yourself piping `$GH_BOT ... | sed`, you've already posted; cancel and redo as two steps.

Git commits use the bot identity via [`tools/bot-commit.sh`](./tools/bot-commit.sh) — the gh wrapper covers API writes only and does NOT set git `user.name`/`user.email`, so a bare `git commit` silently commits as the operator (observed in a retro — 4 of 5 PR commits carried the user identity). The helper resolves `<appName>[bot]` + the bot's noreply email from config `tracker.bot` (caching the bot user id in the git common dir) and falls through to the repo default when the bot is disabled:

```bash
# EVERY pipeline commit (plan, docs, implement fixes, quality pass) goes through this
# (helper ships in the plugin checkout — resolve via ${CLAUDE_PLUGIN_ROOT}, never CWD-relative):
bash "${CLAUDE_PLUGIN_ROOT}/skills/run/tools/bot-commit.sh" -C "$WT" -m "..."
```

## State Tracking

Every issue comment from this pipeline includes machine-readable markers:

```
<!-- dev-pipeline -->
<!-- run_id: {RUN_ID} -->
<!-- stage: {stage-name} -->
<!-- status: {status} -->

Human-readable message here.
```

`RUN_ID` is generated in the **Pre-flight: Generate RUN_ID** step (top of this file) — once per run, before Invocation Routing. It is persisted to top-level `.runId` in the state file via `statectl init --run-id "$RUN_ID"`, and re-read from state if a crash-recovery resume re-enters in a fresh session so the original session and the resumed one share the same `<!-- run_id: ... -->` marker. Include `run_id` in every comment for traceability across retries.

---

## Dynamic Context

Before starting, gather situational context:

```
!`git status --short`
!`git log --oneline -5`
!`git branch --show-current`
!`git stash list`
```

Use this to detect dirty working trees, in-progress work, or stash conflicts before creating worktrees.

**Non-base-branch posture (#59):** a current branch other than the configured base is **not** a reject — Stage-1 reads are pinned to `origin/<baseBranch>` (stages/1-intake.md Step 1.P) and Stage 2 cuts the work branch from the same remote ref, so the checkout's branch cannot leak into the run. The predicates: pin established + clean tree → proceed silently; **dirty working tree** (any branch) → surface a WARN — "a human appears to be mid-work in this checkout" — in the run's final report and proceed; **pin not establishable** (fetch/worktree-add failure) → fail closed via `mark-failed --reason non-main-base-autonomous` (interactive mode presents the failure instead). Wrong-target detection (wrong repo, wrong issue, wrong diff base) is unchanged and still aborts.

---

## Model Tier Mapping

Each LLM-dispatching stage uses a capability tier; this table maps tiers to concrete models. The tier each agent actually runs at lives in two places that must stay in lockstep: each agent's `model:` frontmatter (the `agents/<name>.md` in whichever plugin ships that agent) and the six `.mjs` dispatch tables that re-state it (`REVIEWER_MODEL`, `INTAKE_MODEL`, `DESIGN_MODEL`, `UNIT_TEST_MODEL`, `PLAN_REVIEWER_MODEL`, `EXECUTOR_MODEL` under `workflows/`). `check-model-tiers.sh` (shipped in review-toolkit at `scripts/check-model-tiers.sh`) enforces that lockstep at commit time.

| Tier      | Model             | Rationale                                       |
| --------- | ----------------- | ----------------------------------------------- |
| reasoning | claude-opus-4-8   | Architectural reasoning, multi-domain synthesis |
| code      | claude-sonnet-4-6 | Fast, capable code generation                   |

## Model Tiering

Each stage has a recommended tier. Follow these unless overridden by the user:

| Stage                       | Tier      | Rationale                                                                           |
| --------------------------- | --------- | ----------------------------------------------------------------------------------- |
| 1. Intake + Decomposition   | reasoning | Atomic issue pickup (no-dispatch sub-step) + architectural reasoning, spec analysis |
| 2. Create Worktree + Branch | —         | Mechanical — no LLM dispatch                                                        |
| 3. Write Plan               | reasoning | Design decisions, trade-off analysis                                                |
| 4. Plan Review              | reasoning | Reviewing reasoning quality (plan-review.mjs sequencer; `PLAN_REVIEWER_MODEL`)      |
| 5. Implement                | code      | Code generation — fast and capable (mutation-gate executors: sonnet, `EXECUTOR_MODEL`) |
| 6. Verify                   | —         | verifyctl script execution + in-session advisory quality pass + visual capture (inherits caller) |
| 7. Doc Update               | —         | In-session reasoning over the diff + `.project/` docs (inherits caller)             |
| 8. Code Review              | reasoning | Multi-domain judgment                                                               |
| 9. Open PR                  | —         | Templated output + gh CLI calls — runs in-session on the caller's model             |
| 10. Cleanup                 | —         | Mechanical — no LLM dispatch                                                        |

---

## Pipeline State Persistence

Every stage transition writes state to `.claude/pipeline-state/{issue-number}.json` for crash recovery — if the pipeline is interrupted, re-invoking it with the same issue resumes from the last completed stage. Full JSON schema + field reference: see [`state-schema.md`](./state-schema.md) (sibling).

**Load-bearing state mutations are owned by [`statectl.sh`](./statectl.sh)** — a sibling Bash helper that enforces atomic field bundles, closed-enum validation, and server-clock timestamps. CLI surface:

```
statectl.sh init <issue> --run-id <id>
statectl.sh get <issue> <jq-path>
statectl.sh set-stage <issue> <N> --status started|completed [--force]
statectl.sh checkpoint <issue> <N> --json <payload>
statectl.sh worktree-set <issue> --path <worktreePath> --branch <branch>
statectl.sh pr-add <issue> --branch <branch> --url <pr-url>
statectl.sh review-rounds <issue> --set <1-3> [--exhausted]
statectl.sh intake-brief <issue> --brief-path <path|null> --acceptance-criteria '<json-array>'
statectl.sh plan-review-set <issue> --overall <pass|fix-and-go>
statectl.sh verify-summary-set <issue> --json <verifySummary>
statectl.sh quality-pass-set <issue> --json <payload>
statectl.sh pause-add <issue> --reason <r> [--force]
statectl.sh deviations-add <issue> --kind <enum> --note <s> [--plan-section <s>] [--file <f>] [--line <n>] [--stage <N>]
statectl.sh mark-failed <issue> --reason <enum> [--stage <N>] [--json <details>] [--force]
statectl.sh mark-completed <issue> [--force]
statectl.sh build-failure-context --reason <enum> [--stage <N>] [--kv k=v]... [--kv-num k=v]... [--kv-lines k=v]...
statectl.sh build-checkpoint-7 --issue <N> --branch <B> --head <H> --worktree <W> [--plan <P>] [--changed-files <json>] [--verify-summary <json>] [--deviations <json>] [--free-note <s>] [--plan-risks <json>] [--doc-updater-findings <md>] [--quality-pass-summary <json>]
```

The two `build-*` subcommands are pure stdout builders (no state-file IO) used to construct validated state-payload JSON. Callers compose them: `mark-failed --json "$(build-failure-context ...)"` and `checkpoint 7 --json "$(build-checkpoint-7 ...)"`. The builders validate eagerly at construction; the consumers re-validate at write (defense in depth).

The `--kv*` flag family on `build-failure-context` encodes JSON shape at the call site: `--kv k=v` emits a string field, `--kv-num k=v` emits a numeric field (value must parse as a JSON number), and `--kv-lines k="a\nb"` splits the value on `\n` into a JSON string array. Callers should pick the variant that matches the receiving schema field's type in [`state-schema.md`](./state-schema.md); flag-key duplication across variants is rejected at parse time.

**Every load-bearing state write goes through `statectl`** — the skill body has no prose-`jq` writes. The per-stage files carry the exact call sites and ordering contracts (e.g. `worktree-set` at Stage 2 and `pr-add` at Stage 9 are written BEFORE their stage-completion write, so a completed stage always implies its boundary fields). The only field written outside `statectl` is `costBlockApplied` (owned by `pipeline-cost-block.sh`, intentionally external — see `state-schema.md`). `statectl` is verified by [`statectl-selftest.sh`](./statectl-selftest.sh), whose drift-check asserts the closed-enum validators byte-match a regeneration from `state-schema.md` via [`tools/gen-statectl-validators.sh`](./tools/gen-statectl-validators.sh).

**Stage write convention (applies to every stage):**

- At start: write `currentStage: N`, `status: "in_progress"`, `stages.N.startedAt: <ISO timestamp>`, and `lastUpdatedAt: <ISO timestamp>`.
- At end: write `stages.N.status: "completed"`, `stages.N.completedAt: <ISO timestamp>`, and `lastUpdatedAt: <ISO timestamp>`.
- On failure: write `status: "failed"`, `stages.N.status: "failed"`, `stages.N.completedAt: <ISO timestamp>`, and a `failureContext` field BEFORE surfacing errors to the user.

**The two writes happen at different times — `started` at stage entry, `completed` at stage exit — never batched.** Worked example for a stage:

```bash
statectl.sh set-stage "$ISSUE_NUMBER" N --status started     # FIRST — before any stage work
# ... the stage's actual work runs here (the wall-clock the window should capture) ...
statectl.sh set-stage "$ISSUE_NUMBER" N --status completed    # LAST — after the work
```

Issuing both in one closing call (or doing the work before the `started` write) collapses the window to `0:00` and mis-attributes the work to the prior inter-stage gap. The mechanical/quick-scripting stages are where this slips — each carries an inline "mark started first" reminder (stages 2, 3, 5, 6, 7). A genuinely sub-second stage (e.g. Stage 2's `git worktree add`) will still show ~0 even when marked correctly; the convention is about correct _attribution_, not forcing a non-zero number.

**Gate-owned extension workflows (config `stageWorkflows`) — dispatched just before the stage-completion write.** This is part of the completion protocol above and applies to **every** stage — when config carries a `stageWorkflows: [{stage, name, workflow}]` entry for stage N, the referenced workflow is dispatched **after** stage N's built-in sub-steps finish but **BEFORE** the `set-stage N --status completed` write. It applies to any stage N with a matching entry (there is no per-stage opt-in beyond the config entry itself).

- **Always blocking.** There is no `blocking` field and no advisory lane — extensions ADD blocking checks, they never waive a gate or downgrade to advisory. A stage with a `stageWorkflows` entry does not reach its `completed` write until the workflow passes.
- **Invocation contract.** The workflow is dispatched with `{ issueKey, statePath, configPath }`. It may write state **only** via statectl `checkpoint` payloads namespaced `ext:`; it never mutates load-bearing pipeline fields.
- **Success → record, then complete.** On a passing workflow, record the result under `stageCheckpoint[N].extWorkflows["<name>"] = { status, summary }` (free-shape, `ext:`-namespaced, additive — schema in [`state-schema.md`](./state-schema.md)), then proceed to the normal `set-stage N --status completed` write.
- **Failure → the stage's STANDARD fail-fast write.** A nonzero / failed workflow takes stage N's ordinary gate-failure path — the workflow name rides in the `failureContext` detail field via `--kv extWorkflow=<name>`:

  ```bash
  statectl.sh mark-failed "$ISSUE" \
    --json "$(statectl.sh build-failure-context --reason ext-workflow-failed --stage N --kv extWorkflow=<name>)"
  ```

  Then STOP: under autonomous mode exit rc=0 and stop emitting tool calls; under interactive mode present the situation — same posture as every other gate. The `ext-workflow-failed` reason is a single value for the whole class (see the `failureContext.reason` index in `state-schema.md`), with the specific workflow disambiguated by the `extWorkflow` detail — never a per-workflow enum value.

**Pre-flight reference resolution (fail closed).** Every `stageWorkflows[].workflow` reference must resolve at pre-flight — either a `<plugin>:<relpath>` present in the plugin cache, or a repo-relative path that exists on disk. An unresolvable reference is a **config-lint / pre-flight FAIL CLOSED**: `config-lint.sh` validates the entry's shape at Pre-flight step (0), and the Pre-flight config gate additionally resolves each reference and aborts before any issue is claimed if one does not resolve. A mis-referenced blocking workflow never degrades to a skipped or advisory dispatch — fail-closed is the only safe posture, since a silently-skipped blocking gate would waive a check the config demanded.

Per-stage `startedAt` and `completedAt` are required by the in-band Stage 9 `pipeline-cost-block.sh` sub-step to bucket OTel metrics into stage windows; they are also useful for general run analytics. That sub-step degrades to a single-row "Session total" cost table if these are missing.

Stages that write additional stage-specific fields carry an inline **State:** line noting them (see Stages 1, 2, 6, 8, 9 below). Stage checkpoint writes (after Stages 1, 5, 7) are governed by the Stage Checkpoints section, not by per-stage State lines.

**Resume logic:** On pipeline start, check for an existing state file:

1. If `status: "completed"` — inform user this issue was already delivered. Ask: re-run from scratch or skip?
2. If `status: "in_progress"` — resume from the `currentStage`. Print a one-line summary of what was already completed.
3. If `status: "failed"` — reads state and exits (no-prompt, per the failure contract above); print the failure context. Re-running requires the operator to first clear the local state file (`rm .claude/pipeline-state/{issue}.json`, or reset `status: "in_progress"` + `currentStage` + clear `failureContext`) — `statectl init` is idempotent and will NOT reset a `failed` file. This covers the Stage-1 intake stops (no worktree to keep), where the fix-spec → relabel `ready-for-dev` → re-run flow needs the originating machine's state file cleared.

**Location:** the pipeline-state dir (config `paths.pipelineStateDir`, default `.claude/pipeline-state`) is gitignored. It is local-only crash-recovery data, not a version-controlled artifact.

---

## Stage Checkpoints (crash recovery)

Stage checkpoints exist for **crash recovery (always-on):** persist the salient outputs of completed stages to disk so a fresh session can resume mid-pipeline after an interruption. On the normal path the whole pipeline runs in one session and never reads a checkpoint back; checkpoints are read only when a re-invocation resumes an interrupted run.

The checkpoint write happens at three points. The Stage 7 checkpoint additionally hydrates Stage 8's review context (in-process on the happy path; from disk on a crash-recovery resume); the others are crash-recovery only:

- **After Stage 1 (Intake):** crash-recovery only. Carry forward: issue number, verdict, decomposition decision, slice scope (stacked-PR), key file paths from codebase-explorer.
- **After Stage 5 (Implement):** crash-recovery only. Carry forward: list of changed files, commit SHAs, plan file path, verification commands, any known risks from the plan.
- **After Stage 7 (Doc Update):** hydrates Stage 8 (review context) AND crash-recovery. Carry forward: branch + headSha, worktreePath, planPath, changedFiles, verifySummary (from Stage 6), **structured `deviations[]`** (any plan deviations that Stage 8 should know about), optional `freeNote`, planRisks, **`docUpdaterFindings`** (free-form markdown report from Stage 7; `""` for no findings), and **`qualityPassSummary`** (the Stage-6 advisory quality-pass disclosure, composed from `stages.6.qualityPass`; `{}` when the pass did not run). Schema in `state-schema.md` under `stageCheckpoint["7"]`.

Checkpoints are persisted under `stageCheckpoint["{N}"]` in `.claude/pipeline-state/{issue}.json`. On a crash-recovery resume, the skill body reads only the relevant checkpoint(s); it does NOT replay the conversation transcript.

**Where clean Stage 8 context comes from.** Stages 1–7 form a single cognitive unit (intake → plan → implement → verify → doc-update) where the parent's accumulated context is _signal_. Stage 8 review synthesis is the one place prior context could turn to noise — and it gets clean context where it matters: each reviewer runs as a fresh `agent()` in the `Workflow` script, so reviewer reasoning starts clean. Synthesis runs in-session on the caller's model over those structured findings.

---

## Pipeline Checklist

**Reminder:** ALL GitHub write operations (comments, label changes, PR creation, issue edits) MUST use `$GH_BOT` instead of bare `gh`. Only reads (`gh issue view`, `gh pr view`, `gh issue list`, `gh api GET`) use regular `gh`. The only exception is `--add-assignee @me` / `--remove-assignee @me` which must use regular `gh` (bot can't manage assignees).

Per-stage instructions live in `stages/{N}-{name}.md`. Read only the file for the stage you are executing.

| Stage | File                                                   | Purpose                                               |
| ----- | ------------------------------------------------------ | ----------------------------------------------------- |
| 1     | [`stages/1-intake.md`](./stages/1-intake.md)           | Intake + Decomposition (with atomic pickup)           |
| 2     | [`stages/2-worktree.md`](./stages/2-worktree.md)       | Create Worktree + Branch                              |
| 3     | [`stages/3-write-plan.md`](./stages/3-write-plan.md)   | Write Implementation Plan                             |
| 4     | [`stages/4-plan-review.md`](./stages/4-plan-review.md) | Plan Review                                           |
| 5     | [`stages/5-implement.md`](./stages/5-implement.md)     | Implement                                             |
| 6     | [`stages/6-verify.md`](./stages/6-verify.md)           | Verify (with failure classification + visual capture) |
| 7     | [`stages/7-doc-update.md`](./stages/7-doc-update.md)   | Doc Update (checkpoint → in-process to Stage 8)       |
| 8     | [`stages/8-code-review.md`](./stages/8-code-review.md) | Code Review Loop                                      |
| 9     | [`stages/9-open-pr.md`](./stages/9-open-pr.md)         | Open PR                                               |
| 10    | [`stages/10-cleanup.md`](./stages/10-cleanup.md)       | Cleanup                                               |

---

## Resume / Idempotency

If the pipeline is re-run after interruption:

| State Found                                                                                          | Behavior                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| ---------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Issue has `in-progress` + existing claim comment                                                     | Check if branch + PR exist. Resume from last completed stage (inferred from `<!-- stage: X -->` markers).                                                                                                                                                                                                                                                                                                                                         |
| Issue has `epic` label                                                                               | Do not pick up — tracking issue for sub-issues                                                                                                                                                                                                                                                                                                                                                                                                    |
| Issue has `needs-intake-review`                                                                      | Do not pick up — waiting for human input                                                                                                                                                                                                                                                                                                                                                                                                          |
| Issue has `needs-spec-work` or `needs-plan-review`                                                   | Do not pick up — these labels block auto-pickup                                                                                                                                                                                                                                                                                                                                                                                                   |
| Branch exists, no worktree                                                                           | Re-add worktree from existing branch                                                                                                                                                                                                                                                                                                                                                                                                              |
| Plan file exists                                                                                     | Skip plan writing, go to plan review                                                                                                                                                                                                                                                                                                                                                                                                              |
| PR already exists for branch                                                                         | Push updates + comment, don't create duplicate                                                                                                                                                                                                                                                                                                                                                                                                    |
| Stacked PR: decomposition comment + some PRs open                                                    | Resume from next unstarted slice                                                                                                                                                                                                                                                                                                                                                                                                                  |
| Stacked PR: branch for slice N exists but no worktree                                                | Re-add worktree: `git worktree add "${WORKTREES_DIR}/acme-{ISSUE}-pr{N}" "claude/acme-{ISSUE}-pr{N}"` (WORKTREES_DIR = config `topology.repos.<host>.worktreesDir`)                                                                                                                                                                                                                                                                                                                                      |
| Stacked PR: slice N-1 merged to the base branch before N started                                     | Create N's worktree from the host's configured base branch (config `topology.repos.<host>.baseBranch`) (includes merged changes)                                                                                                                                                                                                                                                                                                                                                                                         |
| Stacked PR: slice N has a clean draft PR (no `needs-deep-review`, `codeReviewExhausted` not set)     | Resume from slice N+1 — clean drafts are the new normal under always-draft.                                                                                                                                                                                                                                                                                                                                                                       |
| Stacked PR: slice N has a draft PR with `needs-deep-review` label (or `codeReviewExhausted == true`) | Do not resume — review exhaustion indicates unresolved blockers. `in-progress` stays for manual rescue.                                                                                                                                                                                                                                                                                                                                           |
| `currentStage == 7` AND `stages.7.status == "completed"`                                             | Crash-recovery resume only (an interrupted run re-invoked in a fresh session — the happy path flows in-process from Stage 7 into Stage 8). Skill enters the Stage 8 crash-recovery resume entry: record a pause span (`pause-add`, the first state write), validate worktree, hydrate from `stageCheckpoint["7"]`, dispatch reviewers via the Stage 8 `Workflow` script (`workflows/code-review.mjs`), then run review-toolkit:review-lead synthesis in-session. |

---

## Error Handling Summary

| Failure                                                | Action                                                                   | Worktree    | Labels                                                                       |
| ------------------------------------------------------ | ------------------------------------------------------------------------ | ----------- | ---------------------------------------------------------------------------- |
| Pre-flight gate fails (no bot wrapper / missing label) | Print onboarding error, exit non-zero — no claim                         | N/A         | N/A                                                                          |
| No `ready-for-dev` issues                              | Print message, exit                                                      | N/A         | N/A                                                                          |
| Claim race lost                                        | Undo mutations, exit                                                     | N/A         | N/A                                                                          |
| Worktree creation fails (Stage 2)                      | `mark-failed` (`worktree-creation-failed`) + stop — **no issue comment** | Not created | `in-progress` stays                                                          |
| Bug/chore with true spec blockers                      | Comment + `mark-failed(intake-spec-blocked)` + stop                      | Not created | → `needs-spec-work`                                                          |
| Orchestrator uncertain / threshold exceeded            | Comment analysis + `mark-failed(intake-needs-human-input)` + stop        | Not created | → `needs-intake-review`                                                      |
| Sub-issues: decomposition complete                     | Create sub-issues, stop (state carve-out: no `mark-failed`, stays `in_progress` — follow-up) | Not created | Parent → `epic` (remove `in-progress`, unassign), children → `ready-for-dev` |
| Spec has resolvable gaps only (≤5)                     | Resolve gaps, continue                                                   | Created     | `in-progress` stays                                                          |
| Too many resolvable gaps (>5)                          | Comment + `mark-failed(intake-spec-blocked, gap-overflow)` + stop        | Not created | → `needs-spec-work`                                                          |
| Spec has true blockers                                 | Comment + `mark-failed(intake-spec-blocked)` + stop                      | Not created | → `needs-spec-work`                                                          |
| Plan review fails 3x                                   | Comment + stop                                                           | Kept        | → `needs-plan-review`                                                        |
| Build/test fails 2x                                    | Comment + stop                                                           | Kept        | `in-progress` stays                                                          |
| Code review fails 3x                                   | Draft PR with `needs-deep-review` label + Outstanding Blockers section   | Removed     | `in-progress` removed                                                        |
| Stacked PRs: slice N fails or `codeReviewExhausted`    | `needs-deep-review` label on slice N draft, stop loop                    | Removed     | `in-progress` stays                                                          |
| Stacked PRs: all slices succeed                        | All draft PRs opened                                                     | Removed     | `in-progress` removed                                                        |
| Success (single PR)                                    | Draft PR opened                                                          | Removed     | `in-progress` removed                                                        |

All failures leave a comment on the issue with `run_id`. No silent failures. Two deliberate, state-recorded carve-outs are **comment-less, not silent** (the failure is captured in `failureContext` and cited by the autonomous-abort turn): the **Stage-2 worktree-creation failure** (Stage 2 has no comment marker — adding one would expand the closed marker enum; same comment-light posture as the Stage-6 non-circuit-breaker exhaustion path) and the **pre-flight gate** (fails before any issue is claimed, so there is no issue to comment on — it prints an onboarding error to stderr and exits non-zero). The three failure-shaped Stage-1 intake stops (spec blockers, >5 resolvable gaps, escalation) are **not** carve-outs — they comment AND record state via `mark-failed(intake-spec-blocked | intake-needs-human-input)`. One state-less carve-out remains: the **`sub-issues` split verdict** — success-shaped (the ticket decomposed), tracker-recorded on github (children `ready-for-dev`, parent `epic`), but not yet state-terminated; a success-shaped statectl terminal mechanism is a tracked follow-up, so the gap is declared rather than silent.

---

## Hooks

The pipeline expects two hooks in `.claude/settings.json`: a blocking pre-commit `type-check` gate (`PreToolUse`) and an informational session-end `tsc --noEmit` sweep (`Stop`). Configuration, scripts, and scope notes: see [`hooks.md`](./hooks.md) (sibling file).

If the pre-commit hook denies a commit during Stage 6, fix the type error before retrying. Do not remove the hook to work around failures.

---

## Post-Run Eval

After Stage 9 (or any pipeline abort), score the run against [`eval-criteria.md`](./eval-criteria.md) and write results to `.claude/pipeline-state/{issue-number}-eval.json`. Every run produces a score — this data feeds the next optimization iteration of the skill.

**Required file shape** (`mark-completed` refuses a terminal write without it — write the eval BEFORE `mark-completed`): parseable JSON with `ticketKey` = the issue key **as a string** (e.g. `"98"`) and a non-empty `criteria` object (the five criterion scores). Everything else (outcome, notes, evidence) is free-shape. When self-scoring `scope_compliance`, cross-check the **committed file list** against the plan's Affected files — not just the AC verdict (a retro FAIL class: out-of-plan commits graded PASS off the scope-reviewer alone).

**This self-score is a floor, not the record.** The executor grading its own run is structurally generous; the operator should follow up with **`/dev-pipeline:pipeline-retro <issue-number>`** (sibling skill, [`../pipeline-retro/SKILL.md`](../pipeline-retro/SKILL.md)) — it re-scores the five criteria with a fresh-context agent from artifacts only (evidence quotes required), audits the run for contract deviations (silent deviations are the headline metric), logs environment friction, and routes every finding to a skill edit, issue, doctor check, or criteria proposal.

---

## Known Limitations

- **The Stage-6 quality pass is advisory.** It applies at most one behavior-preserving `refactor:` commit over the branch diff, safety-net re-verifies with `--no-attempt`, and resets on red — it never blocks completion and never prompts. A missed cleanup is a Stage-8 reviewer suggestion, not a pipeline failure.
- **All PRs are opened as draft by default.** Engineers flip to ready-for-review after a manual eyes-on pass. The `needs-deep-review` label and the `codeReviewExhausted` state field distinguish review-exhausted drafts from clean drafts; draft status alone is not a failure signal.
- **Eval criteria 3 (implementation_resilience) and 5 (review_precision) can only be scored on real pipeline runs** — dry-run optimization loops cannot exercise these paths. Scores accumulate organically with actual issue runs.
- **Single-repo only.** Unlike some sibling forks of this skill, the acme pipeline has no cross-repo orchestration (no `targetRepos`, no per-repo `worktrees` map). All work happens in this repo.
- **Stacked-PR mode overwrites `worktreePath` / `branch`** per slice. Historical slice state is not preserved in the JSON — it is inferable only from the decomposition plan on disk plus the set of already-opened PRs.
- **Single-session, in-process flow.** All stages (1–10) run in one session, end to end; the Stage 8 review loop iterates in place (up to 3 rounds).
- **Stage 8 skill loadout.** Stage 8 does NOT load `intake-toolkit:intake-orchestrator` (Stage 2 is past). It dispatches the reviewer fan-out via the `Workflow` script (`workflows/code-review.mjs`) and loads `review-toolkit:review-lead` for **synthesis only**, plus the `$GH_BOT` wrapper. On a crash-recovery resume in a fresh session, the state file plus `stageCheckpoint["7"]` is the entire context contract.
