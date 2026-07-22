# Stage 9. Open PR

> **Tracker delta (config `tracker.type: jira`).** PR creation is GitHub for both
> trackers (`gh pr create --draft`), but under the jira adapter: **no tracker
> writes** — do NOT transition the ticket or add a JIRA comment (the ticket stays put;
> the operator moves it after promoting the PR). The PR ties back to the ticket by
> filling the repo's `pull_request_template.md` `### Jira Items` with `Closes [<KEY>]`
> (github default: `Closes #<issue>`). JIRA repos have no bot claim, so the push/PR
> use regular `gh` (no `$GH_BOT`). A **be-fe-pair** run opens one draft PR per target
> repo with cross-repo companion links. See [`tools/tracker/jira/`](../tools/tracker/jira/README.md).

**First, mark the stage started** — per the global Stage write convention (SKILL.md), Stage 9 begins with `statectl set-stage "$ISSUE_NUMBER" 9 --status started` BEFORE the stale-branch freshness check below. This is load-bearing for Stage 9 specifically: the file leads with a fail-fast path (the stale-branch check can `mark-failed --stage 9`), so if the started-write is deferred, an abort lands with `stages.9.startedAt` unwritten — and on the success path the later `set-stage 9 --status completed` then errors with "cannot complete stage 9 with no startedAt", leaving `currentStage` stuck at 8 with no recoverable backfill (the terminal guard blocks it). Marking `started` first closes both branches: on a stale-branch abort, `mark-failed --stage 9` overwrites `stages.9` to a terminal `failed` lifecycle with `completedAt` set (same convergence as the Stage 2 worktree-failure precedent), so there is never a dangling `in_progress`. Write `started` first.

**All PRs open as draft.** The human reviewer flips to ready-for-review after a manual eyes-on pass. Clean drafts and exhausted-review drafts are distinguished by the `needs-deep-review` label and the `codeReviewExhausted` state field — not by draft status.

**Stale-branch freshness check (autonomous default):** Before pushing, check whether opening the PR risks a **real** merge conflict — whether the branch and its PR base (`origin/<baseBranch>`, or the prior slice for a stacked run) changed an **overlapping set of files** since their merge base. Raw distance does not matter: a branch far "behind" a fast-moving base branch still merges cleanly when the two changed-file sets are disjoint (disjoint sets cannot produce a merge conflict). Only a genuine file overlap is worth stopping for:

```bash
# Effective PR base: persisted prBase (a stacked slice targets its prior slice) else the
# host repo's configured baseBranch — never a hardcoded "main" (a develop/alpha-based
# consumer's freshness check and PR target would otherwise both point at the wrong ref).
# Single source of truth with the `--base` target at PR creation below.
CFG="${SECOND_SHIFT_CONFIG:-.claude/second-shift.config.json}"
PR_BASE_EFF=$(statectl.sh get "$ISSUE_NUMBER" '.prBase // empty')
if [[ -z "$PR_BASE_EFF" || "$PR_BASE_EFF" == "null" ]]; then
  PR_BASE_EFF=$(jq -r '(.topology.repos | to_entries[] | select(.value.path==".") | .key) as $h | .topology.repos[$h].baseBranch // "main"' "$CFG" 2>/dev/null || echo main)
fi
git fetch origin "$PR_BASE_EFF" --quiet
# Conflict gate keyed on overlapping changed files since the merge base. Uses only
# deny-safe plumbing — `git merge*` (which covers both the in-place `git merge` freshen
# AND `git merge-tree`), `git rebase*`, and `git reset*` are denied, so the autonomous
# path has no in-place freshen. Prevention (Stage 2 cuts the branch from a fresh
# `origin/<baseBranch>`) plus this gate is the recovery story; a genuine overlap needs a human.
MERGE_BASE=$(git merge-base "origin/$PR_BASE_EFF" "$BRANCH")
OURS=$(git diff --name-only "$MERGE_BASE" "$BRANCH" | sort -u)
THEIRS=$(git diff --name-only "$MERGE_BASE" "origin/$PR_BASE_EFF" | sort -u)
OVERLAP_FILES=$(comm -12 <(printf '%s\n' "$OURS") <(printf '%s\n' "$THEIRS"))
OVERLAP_COUNT=$(printf '%s' "$OVERLAP_FILES" | grep -c .)

if [[ "$OVERLAP_COUNT" -gt 0 ]]; then
  statectl.sh mark-failed "$ISSUE_NUMBER" \
    --reason stale-branch-autonomous --stage 9 \
    --json "$(statectl.sh build-failure-context \
      --reason stale-branch-autonomous --stage 9 \
      --kv-num overlapCount="$OVERLAP_COUNT" \
      --kv-lines overlapFiles="$OVERLAP_FILES")"
  # Build the failure comment in a fresh per-post temp file (mktemp — NEVER a fixed /tmp
  # name; concurrent runs collide on shared names — see SKILL.md "Multi-line comments").
  # printf (not a heredoc) writes the body, for parity with the Stage-8 failure comment.
  BODY=$(mktemp -t dev-pipeline-stale-branch.XXXXXX)
  printf '%s\n' \
    '<!-- dev-pipeline -->' \
    "<!-- run_id: $RUN_ID -->" \
    '<!-- stage: pr -->' \
    '<!-- status: failed -->' \
    '' \
    "Stage 9 stopped: branch \`$BRANCH\` and \`origin/$PR_BASE_EFF\` both changed $OVERLAP_COUNT file(s) since their merge base, so opening the PR risks a real merge conflict. \`git merge\`/\`rebase\`/\`reset\` are denied, so the autonomous path cannot freshen the branch in place — a human must resolve (merge \`origin/$PR_BASE_EFF\` or re-cut from it), then re-run. Overlapping files:" \
    "$OVERLAP_FILES" \
    > "$BODY"
  $GH_BOT issue comment "$ISSUE_NUMBER" --body-file "$BODY"
  rm -f "$BODY"
  # Exit cleanly (rc=0). A human resolves the overlap; there is no deny-safe in-place freshen.
fi
# Empty overlap → disjoint file sets → guaranteed clean merge → fall through and open the PR.
```

**Under `DEV_PIPELINE_MODE=interactive`:** skip the `mark-failed` write; present the overlapping files to the user and ask whether to resolve them manually (merge the PR base `origin/<baseBranch>` / re-cut from it) and re-run, abort, or proceed anyway.

**be-fe-pair (config `topology.type: be-fe-pair`) — one PR per target repo (#4).** Run push + PR creation **per repo in the `worktrees` map** (`.targetRepos`), each in its own repo, from its own base, to its own owner. The single-repo flow below (duplicate guard → push → create → `pr-add`) is the **`standalone`/`monorepo`** path; a be-fe-pair run uses this loop instead:

```bash
if [[ "$(jq -r '.topology.type // "standalone"' "$SECOND_SHIFT_CONFIG" 2>/dev/null || echo standalone)" == "be-fe-pair" ]]; then
  MAIN_ROOT="$(git rev-parse --show-toplevel)"
  for r in $(statectl.sh get "$ISSUE_NUMBER" '.targetRepos // [] | join(" ")'); do
    WT="$MAIN_ROOT/$(statectl.sh get "$ISSUE_NUMBER" ".worktrees[\"$r\"].worktreePath")"
    BR=$(statectl.sh get "$ISSUE_NUMBER" ".worktrees[\"$r\"].branch")
    BASE=$(statectl.sh get "$ISSUE_NUMBER" ".worktrees[\"$r\"].base")
    # owner/name for `gh pr create --repo`, from THIS repo's origin remote.
    OWNER=$(git -C "$WT" remote get-url origin | sed -E 's#(git@[^:]+:|https?://[^/]+/)##; s#\.git$##')
    # Freshness gate (per repo): overlap of THIS branch vs its own base — same
    # deny-safe logic as the single-repo gate above; a genuine overlap fails closed.
    git -C "$WT" fetch origin "$BASE" --quiet
    OVL=$(comm -12 <(git -C "$WT" diff --name-only "$(git -C "$WT" merge-base "origin/$BASE" "$BR")" "$BR" | sort -u) \
                   <(git -C "$WT" diff --name-only "$(git -C "$WT" merge-base "origin/$BASE" "$BR")" "origin/$BASE" | sort -u) | grep -c .)
    if [[ "$OVL" -gt 0 ]]; then
      statectl.sh mark-failed "$ISSUE_NUMBER" --reason stale-branch-autonomous --stage 9 \
        --json "$(statectl.sh build-failure-context --reason stale-branch-autonomous --stage 9 --kv repo="$r" --kv-num overlapCount="$OVL")"
      exit 0
    fi
    git -C "$WT" push -u origin "$BR"
    EXISTING=$(gh pr list --repo "$OWNER" --head "$BR" --json number --jq '.[0].number' 2>/dev/null)
    if [[ -n "$EXISTING" ]]; then
      URL=$(gh pr view "$EXISTING" --repo "$OWNER" --json url --jq '.url')
    else
      # Cross-repo title carries the repo prefix (feat(be)/feat(fe)); body from the
      # repo's own .github/pull_request_template.md when present, Closes/link filled.
      URL=$($GH_BOT pr create --draft --repo "$OWNER" --head "$BR" --base "$BASE" \
        --title "<type>(${r}): <summary> (${ISSUE_NUMBER})" --body-file "$BODY_FILE")  # $BODY_FILE = a fresh mktemp built per repo from its PR template
    fi
    statectl.sh pr-add "$ISSUE_NUMBER" --repo "$r" --branch "$BR" --url "$URL"
  done
  # Cross-repo companion links (best-effort): after all PRs exist, amend each body
  # to reference the others' URLs from `.prs` (fresh mktemp per amend — never a
  # fixed /tmp name; see SKILL.md "Multi-line comments"). Then run the cost block
  # once, `set-stage 9 --status completed`, and mark-completed as below.
fi
```

`pr-add --repo` records `prs.<id> = {url, branch, repo}` (the branch is shared across repos, so `.prs` is keyed by repo id, not branch). Each PR targets ITS repo's base (BE `alpha` / FE `main`). Everything else in this stage (cost block, completion write) runs once after the loop.

**Guard against duplicates (single-repo — `standalone`/`monorepo` only; be-fe-pair used the per-repo loop above):**

```bash
EXISTING_PR=$(gh pr list --head "$BRANCH" --json number --jq '.[0].number')
```

- **If PR already exists:** push updates, comment on existing PR via `$GH_BOT pr comment` with `run_id`, skip creation.
- **If no existing PR:**

```bash
git push -u origin "$BRANCH"

# Read PR base + priorSliceBranch from state (written by Stage 1 outer-loop
# preamble for stacked-PR runs; absent for single-PR runs). Persisted prBase
# is the source of truth — do not recompute from SLICE_NUMBER here.
PR_BASE=$(statectl.sh get "$ISSUE_NUMBER" '.prBase // empty')
PRIOR_BRANCH=$(statectl.sh get "$ISSUE_NUMBER" '.priorSliceBranch // empty')

# Single-PR fallback: no slice fields → the host repo's configured baseBranch (not a
# hardcoded "main"). CFG resolved in the freshness gate above; re-resolve defensively
# in case this block runs in a separate shell.
CFG="${SECOND_SHIFT_CONFIG:-.claude/second-shift.config.json}"
if [[ -z "$PR_BASE" || "$PR_BASE" == "null" ]]; then
  TARGET=$(jq -r '(.topology.repos | to_entries[] | select(.value.path==".") | .key) as $h | .topology.repos[$h].baseBranch // "main"' "$CFG" 2>/dev/null || echo main)
else
  TARGET="$PR_BASE"
fi

# For stacked-PR slice N>1, resolve the prior slice's PR number for the
# "Stacked on PR #XYZ" prose. Best-effort: if the prior PR isn't open yet,
# the prose section is omitted.
STACKED_ON_LINE=""
if [[ -n "$PRIOR_BRANCH" && "$PRIOR_BRANCH" != "null" ]]; then
  PRIOR_PR_NUM=$(gh pr list --head "$PRIOR_BRANCH" --json number --jq '.[0].number' 2>/dev/null)
  [[ -n "$PRIOR_PR_NUM" ]] && STACKED_ON_LINE="Stacked on #${PRIOR_PR_NUM} (\`${PRIOR_BRANCH}\`)."
fi

# Always --draft. The Outstanding Review Blockers section is included
# only when codeReviewExhausted == true. The Stacked-PR body template
# (below) inserts $STACKED_ON_LINE at the top of the body when set.
#
# Pass --head "$BRANCH" EXPLICITLY: through the $GH_BOT wrapper, `gh pr create`
# cannot infer the head branch from the worktree and aborts with "could not
# determine the current branch: not on any branch". The explicit --head is also
# correct for stacked-PR slices, where the current branch and the slice branch
# can differ. (--base is already explicit.)
# --title defaults to "$ISSUE_TITLE", but use a conventional-commit title scoped to
# the ACTUAL deliverable when the raw issue title would mislead — e.g. a `.claude/`-only
# change uses `chore(<scope>): …` (never `feat:`), and a single-item delivery off a
# multi-item issue names just that item, not the issue's broad heading. The PR title
# becomes the squash-merge title, so it follows the same convention as the commit.
PR_URL=$($GH_BOT pr create \
  --draft \
  --base "$TARGET" \
  --head "$BRANCH" \
  --title "$ISSUE_TITLE" \
  --body "$BODY")

# Persist the URL so the cost-tracking sub-step (below) can amend this PR's body.
statectl.sh pr-add "$ISSUE_NUMBER" \
  --branch "$BRANCH" --url "$PR_URL"
# Ordering contract: pr-add MUST precede `set-stage 9 --status completed`
# (same rule as worktree-set at Stage 2 — stage completion implies the field).
```

**PR body template** (single, always-draft):

```markdown
Closes #{ISSUE_NUMBER}

> Opened as draft. Flip to ready-for-review after human eyes confirm.

## Summary

{generated summary of changes}

## Verification

- [x] format
- [x] lint
- [x] type-check
- [x] test

{If Stage 7 visual capture ran (render-surface trigger matched and no skip), include:}

## Visual Verification

Screenshots: `.claude/pipeline-state/{ISSUE_NUMBER}-screenshots/` ({N} files)

<details>
<summary>Inline screenshots</summary>

{One markdown image embed per captured file, e.g. `![root @ 375](./.claude/pipeline-state/{ISSUE_NUMBER}-screenshots/root-375.png)`}

</details>

{End conditional.}

## Code Review

{N} rounds, all blockers resolved.

{If codeReviewExhausted == true, also include:}

## Outstanding Review Blockers

{unresolved findings from final round, with severity}

## Review History

- Round 1: {N} findings, {M} fixed
- Round 2: {N} findings, {M} fixed
- Round 3: {N} findings — exhausted

## Suggested Next Actions

{what the human reviewer should focus on}

{End conditional block.}

---

dev-pipeline run: ${RUN_ID}
```

**Stacked-PR body template** (use when `currentSlice` is set in state; same always-draft + conditional Outstanding Blockers structure). When `$STACKED_ON_LINE` is non-empty (slice N>1), insert it as the second prose line — under the "Part of" line and above the "Opened as draft" notice.

```markdown
Part of #{ISSUE_NUMBER} — PR {SLICE_NUMBER} of {TOTAL_SLICES}

{STACKED_ON_LINE if set: e.g. "Stacked on #123 (`claude/acme-42`)."}

> Opened as draft. Flip to ready-for-review after human eyes confirm.

## Summary

{what this slice delivers}

## Decomposition Context

{link to intake comment with full decomposition plan}

## Verification

- [x] format
- [x] lint
- [x] type-check
- [x] test

{If Stage 7 visual capture ran (render-surface trigger matched and no skip), include the same `## Visual Verification` section as the single-PR template above, scoped to this slice's screenshots.}

## Code Review

{N} rounds, all blockers resolved.

{If codeReviewExhausted == true, include the Outstanding Review Blockers / Review History / Suggested Next Actions sections from the single-PR template above.}

---

dev-pipeline run: ${RUN_ID}
```

- **If `codeReviewExhausted == true`:** after `gh pr create` returns, add the `needs-deep-review` label: `$GH_BOT pr edit "$PR_URL" --add-label needs-deep-review`.
- Comment on issue via `$GH_BOT issue comment`: `stage: pr`, `status: opened-as-draft` for clean runs and `status: opened-as-draft (review exhausted)` for the unhappy path. The exhausted comment also includes the marker `<!-- review-exhausted -->` for resume disambiguation. Record the receipt: `"$STATECTL" comment-add "$ISSUE_NUMBER" --marker pr --url <html_url>` — Stage-9 completion refuses without it.
- For single-PR runs: `$GH_BOT issue edit $ISSUE_NUMBER --remove-label in-progress` (use regular `gh` for `--remove-assignee @me` separately)
- For stacked-PR runs: do NOT remove `in-progress` until all slices are done (handled by the outer loop completion step).

**State:** `prs[BRANCH] = { url: "<PR URL>" }` is recorded for every PR opened in this stage via `statectl pr-add` (see the create block above) — ordered BEFORE the Stage 9 completion write.

## Cost-block sub-step (in-band, opt-in)

After every PR in `prs` has its URL recorded, invoke the cost-block sub-step to amend each PR body with the cost block. It is idempotent on the `<!-- pipeline-cost-block -->` marker. The sub-step always exits 0 — it never blocks Stage 9 completion. It records its own outcome to `costBlockApplied` in the state file.

```bash
bash pipeline-cost-block.sh "$ISSUE_NUMBER"
```

What it does:

- Reads `pipelineSessions[]` (populated by Stage 2 / Stage 8 `pipeline-session-add` calls).
- Queries `~/.claude/otel-metrics/metrics.jsonl` for cost + token datapoints whose `session.id` is in that set, clamped to the run's wall-clock fence (`[startedAt, max(stage completedAt) // lastUpdatedAt]`) so a co-resident sequential run/retro under the same `session.id` is excluded.
- Buckets the in-fence metrics per stage using each row's timestamp and the `stages.{N}.startedAt/completedAt` windows; in-fence datapoints in no stage window land in an explicit "Other" bucket. Degrades to a single "Session total" row if windows are missing.
- For stacked-PR runs (`len(prs) > 1`), splits total cost evenly across slices.
- Renders a Markdown cost block with the `<!-- pipeline-cost-block -->` sentinel marker for idempotent detection.
- Reads each PR body via plain `gh pr view`, appends the cost block, and writes back with the identity config selects: `$GH_BOT pr edit` when `tracker.bot.enabled` is true, plain `gh pr edit` (operator identity) when the bot is disabled or the config is absent/unreadable. Re-runs detect the marker and skip.

If any prerequisite is missing (no `pipelineSessions[]`, no metrics file, no `gh` CLI, or — **on a bot-enabled repo only** — no bot wrapper), the sub-step records a descriptive `costBlockApplied` string (`"skipped-no-sessions"`, `"skipped-telemetry-off"`, `"skipped-no-gh-cli"`, `"skipped-no-bot-wrapper"`, etc.) and exits 0. The pipeline continues regardless.

**Recovering a `"skipped-otel-error"`:** this stage is already complete when the cost block fails, so the pipeline does not retry it. The operator fixes the precondition (collector reachable / `OTEL_*` exported) and re-runs just the sub-step — `bash pipeline-cost-block.sh "$ISSUE_NUMBER"` — which is idempotent on the `<!-- pipeline-cost-block -->` marker. Full procedure: [`cost-tracking-setup.md` → "Manual re-run after an OTel query failure"](../cost-tracking-setup.md#manual-re-run-after-an-otel-query-failure).

**Setup:** see [`cost-tracking-setup.md`](../cost-tracking-setup.md) for OTel collector install + telemetry env vars. There is no per-engineer hook-wiring step.

**State:** After the sub-step returns, write the terminal top-level status via `statectl`: `statectl.sh mark-completed "$ISSUE_NUMBER"` (atomic `status: "completed"` + `lastUpdatedAt` bundle; refuses to overwrite an already-terminal state without `--force`). Order it AFTER `set-stage 9 --status completed` — `set-stage` rejects mutations once the top-level status is terminal.

`mark-completed` additionally enforces two terminal gates, **not** bypassed by `--force`: every stage 1–9 must be `completed`, and the Post-Run Eval file (`.claude/pipeline-state/{issue}-eval.json`, SKILL.md "Post-Run Eval") must exist with a plausible score — **so the eval write must precede `mark-completed`**.

**Stacked-PR runs:** call `mark-completed` **once, after the LAST slice** (as part of the outer loop's completion step in `stages/1-intake.md`, alongside the `all-prs-opened` comment) — never per slice; a mid-run terminal write would make every later slice's state mutation refuse. (Stacked-slice stage-machine semantics — how per-slice stage re-entries interact with the completion preconditions and re-start guards — are single-PR-scoped for now; a follow-up issue tracks the full model.)

---

_Stage 9 of the [dev-pipeline](../SKILL.md) flow. Return to the router for cross-stage contracts (Invocation Routing, Failure Contract, State Persistence, etc.)._
