---
name: pr-revision
description: Address human PR review comments — classify, auto-fix, clarify, or push back with evidence
---

# PR Revision

Companion skill to the dev-pipeline. Addresses human PR review comments after a PR is opened.

**Runtime:** Same as dev-pipeline — Claude Code CLI or IDE. See dev-pipeline SKILL.md for runtime details.

**Design doc:** `docs/plans/2026-03-29-pr-revision-design.md`

**Invocation:** `/pr-revision <PR_NUMBER>`

## Prerequisites

- `gh auth status` must succeed
- Repository must have label: `in-progress`
- The PR must be open (not closed or merged)
- Worktree base dir: config `topology.repos.<host>.worktreesDir`

## Bot Identity

All GitHub **write** operations (comments, labels, thread resolution) MUST use the bot wrapper:

```bash
# When config `tracker.bot.enabled`, use the bot wrapper installed by
# `../dev-pipeline/tools/install-gh-bot.sh`, exported as the env var named by
# `tracker.bot.envVar` (default GH_BOT).
# Use $GH_BOT instead of gh for: api POST/PATCH/PUT, pr comment, issue comment, issue edit
# Use regular gh for: reads (pr view, api GET)
```

**Known limitation:** `--add-assignee @me` does not work via the bot wrapper. Use regular `gh` for assignee operations.

Git commits use the bot identity via flags:

```bash
# Commit identity comes from the installed bot (config `tracker.bot`); the wrapper
# sets user.name / user.email. When the bot is disabled, commit as the repo default.
git commit -m "..."
```

## State Tracking

Uses the same marker contract as the main pipeline:

```
<!-- dev-pipeline -->
<!-- run_id: {RUN_ID} -->
<!-- stage: pr-revision -->
<!-- status: {status} -->

Human-readable message here.
```

Generate `RUN_ID` at the start of the run: `{ISO timestamp}-{hostname}-{random 8 hex chars}`.
Include `run_id` in every comment for traceability.

---

## Pipeline Checklist

**Reminder:** ALL GitHub write operations (comments, label changes, thread replies, thread resolution) MUST use `$GH_BOT` instead of bare `gh`. Only reads (`gh pr view`, `gh api GET`, `gh issue view`) use regular `gh`. The only exception is `--add-assignee @me` / `--remove-assignee @me` which must use regular `gh` (bot can't manage assignees).

### 1. Validate & Fetch PR

```bash
# Validate PR exists and is open
PR_DATA=$(gh pr view $PR_NUMBER --json number,headRefName,body,title,state)
STATE=$(echo "$PR_DATA" | jq -r '.state')
if [ "$STATE" != "OPEN" ]; then
  echo "PR #$PR_NUMBER is $STATE — skipping revision."
  exit 0
fi
```

- Generate `RUN_ID`.
- Extract `BRANCH` from `headRefName`.
- Extract `ISSUE_NUMBER` from PR body (match `Closes #N`, `Part of #N`, or `Fixes #N`).
  - If not found: warn — post to PR only, skip issue comments for the rest of the run.
- Add `in-progress` label to issue (if issue found): `$GH_BOT issue edit $ISSUE_NUMBER --add-label in-progress`

### 2. Fetch All Comments

Three separate API calls to cover all GitHub comment types:

```bash
# Inline review comments (line-level)
INLINE_COMMENTS=$(gh api repos/{owner}/{repo}/pulls/$PR_NUMBER/comments)

# Review bodies (summary text submitted with Approve/Request Changes/Comment)
REVIEW_BODIES=$(gh api repos/{owner}/{repo}/pulls/$PR_NUMBER/reviews)

# PR conversation comments (issue-level)
PR_COMMENTS=$(gh pr view $PR_NUMBER --json comments --jq '.comments')
```

**Resume guard:** Before classifying, filter out already-handled comments:

- Skip threads the agent has already replied to (match by `<!-- dev-pipeline -->` markers in replies)
- Skip resolved threads
- If zero unresolved/unhandled comments remain: post "No new comments to address" on PR, clean up worktree (if exists), stop

**Comment volume guard:**

| Count                    | Action                                                                                                                                                                  |
| ------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| ≤ 20 unresolved comments | Process normally                                                                                                                                                        |
| 21–50                    | Warn: "Found {N} unresolved comments. Proceeding, but this is unusually high — consider whether the PR needs a larger rework instead of point fixes." Process normally. |
| > 50                     | **Stop.** Post comment on PR and issue: `stage: pr-revision`, `status: too-many-comments`. Do not process.                                                              |

### 3. Classify Comments

#### Comment sources

| Source                   | API                          | Role                                        |
| ------------------------ | ---------------------------- | ------------------------------------------- |
| Inline review comments   | `pulls/$N/comments`          | Primary — always classified                 |
| Review bodies            | `pulls/$N/reviews`           | Classified if actionable, context otherwise |
| PR conversation comments | `gh pr view --json comments` | Classified if actionable, context otherwise |

#### Classification tiers

Each **unresolved** comment is classified into one of three tiers:

| Tier                 | Criteria                                                                                                                                  | Examples                                                                                           | Action                                              |
| -------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- | --------------------------------------------------- |
| **Auto-fix**         | Clear, unambiguous, mechanical change. Single correct interpretation.                                                                     | Typo, naming, missing null check, add a log line, fix formatting, add missing type annotation      | Implement immediately                               |
| **Clarify-then-fix** | Intent is clear but implementation has multiple valid paths, OR touches architecture/behavior                                             | "Refactor this to use the existing service pattern", "This should handle the edge case where X"    | Reply with proposed approach, wait for confirmation |
| **Pushback**         | Agent disagrees — comment is based on misunderstanding, would introduce regression, contradicts spec/ADR, or is already handled elsewhere | "Add auth check here" (when no auth system exists), "This should be sync" (when async is required) | Reply with evidence, leave thread open              |

#### Actionable signals for non-inline comments

Review bodies and PR conversation comments are context by default. They get classified into the three tiers only if they contain an obviously actionable signal:

- **Bug/correctness warnings:** "This would break...", "This could cause an endless loop...", "This has a race condition..."
- **Direct instructions:** "This must be fixed...", "Please add...", "Remove the..."
- **Regression flags:** "This used to work because...", "After this change, X no longer..."

Non-actionable comments (general praise, questions about intent, style preferences without specific locations) remain context-only. The agent may reply to acknowledge but takes no code action.

#### Classification guard

When in doubt between Auto-fix and Clarify-then-fix → choose Clarify-then-fix.
When in doubt between Clarify-then-fix and Pushback → choose Clarify-then-fix.
Bias toward asking, not assuming.

#### Output

Print classification table to console:

```
Comment Classification:
  #1  [Auto-fix]         @user on src/service.ts:42 — "rename to camelCase"
  #2  [Clarify-then-fix] @user on src/worker.ts:88 — "refactor to use existing pattern"
  #3  [Pushback]         @user (review body) — "this would break the upload flow"
  #4  [Auto-fix]         @user on src/dto.ts:15 — "add missing @ApiProperty"
```

### 4. Worktree & Branch Setup

Reuses the existing PR branch — no new branch created.

```bash
BRANCH=$(gh pr view $PR_NUMBER --json headRefName --jq '.headRefName')

# Pull latest from remote
git fetch origin "$BRANCH"

# WORKTREES_DIR = config topology.repos.<host>.worktreesDir
WORKTREE_PATH="${WORKTREES_DIR}/pr-${PR_NUMBER}"

if git worktree list | grep -q "$WORKTREE_PATH"; then
  cd "$WORKTREE_PATH"
  git pull origin "$BRANCH"
else
  git worktree add "$WORKTREE_PATH" "origin/$BRANCH"
  cd "$WORKTREE_PATH"
fi

# Capture pre-revision state for scoped review later
PRE_REVISION_SHA=$(git rev-parse HEAD)
```

- `cd` into the worktree for ALL subsequent work.
- All file paths in steps 5-8 are relative to the worktree root.
- Read the existing plan file from the worktree (if any) to understand original implementation context.

**Stacked-PR base check:** If the PR's base branch is not the host's configured base branch (config `topology.repos.<host>.baseBranch`), verify the base branch tip matches `origin/<base>`:

```bash
BASE_BRANCH=$(gh pr view $PR_NUMBER --json baseRefName --jq '.baseRefName')
# HOST_BASE_BRANCH = config topology.repos.<host>.baseBranch
if [ "$BASE_BRANCH" != "$HOST_BASE_BRANCH" ]; then
  git fetch origin "$BASE_BRANCH"
  LOCAL_BASE=$(git merge-base HEAD "origin/$BASE_BRANCH")
  REMOTE_BASE=$(git rev-parse "origin/$BASE_BRANCH")
  if [ "$LOCAL_BASE" != "$REMOTE_BASE" ]; then
    echo "WARNING: Base branch $BASE_BRANCH has been updated since this PR was created."
    echo "Consider rebasing before addressing review comments."
    # Post warning on PR, continue but note it in the summary
  fi
fi
```

### 5. Post Replies (before any code changes)

**All replies are posted before any commits are made.** This ensures pushback references and clarification questions reference the code as the reviewer saw it.

**Pushbacks:** Reply on the PR thread with evidence:

- Structure: _what the comment suggests → why the current approach is correct → evidence_
- Must cite at least one of: test output, spec/ADR reference, existing codebase pattern, or concrete code reference
- Leave the thread open

**Clarify-then-fix:** Reply with the proposed approach and stop processing that comment. It enters a "waiting" state.

**Reply format:**

```
<!-- dev-pipeline -->
<!-- run_id: {RUN_ID} -->

[Reply content here]
```

### 6. Implement Auto-fixes

Group auto-fixes by file where possible for clean commits. For each fix:

1. Make the change
2. Commit with conventional commit: `fix(scope): address PR review feedback` with `#ISSUE_NUMBER` in the commit body
3. Reply on the thread confirming the fix with a brief note of what changed
4. Resolve the thread

**Reply format for fixes:**

```
<!-- dev-pipeline -->
<!-- run_id: {RUN_ID} -->

Fixed in {COMMIT_SHA}: {brief description of change}
```

Clarify-then-fix comments are NOT implemented in this pass. They are addressed in a subsequent invocation after the human confirms the approach.

### 7. Verify

Same commands as the main pipeline Stage 7: run the configured format, lint, type-check, and test commands from the config `commands` table.

- **If any command fails:** attempt to fix (max 2 tries per failure).
- **If still failing after 2 fix attempts:**
  - Do NOT push.
  - Reply on PR with error output.
  - Post comment on issue: `stage: pr-revision`, `status: verify-failed`.
  - Keep `in-progress` label on issue (signals broken state).
  - Keep worktree for manual rescue.
  - **STOP.**

### 8. Scoped Code Review + Push

**Step 1: Scoped review**

Run `review-toolkit:review-lead` on only the files changed by this revision. review-toolkit:review-lead dispatches its reviewer fan-out through the `code-review.mjs` Workflow (the single dispatch substrate); pass this revision's worktree + committed range as the script args:

```
Workflow({ scriptPath: "../dev-pipeline/workflows/code-review.mjs",
           // The caller also passes args.config = the parsed second-shift.config.json
           // (plugin reviewers qualified `review-toolkit:`; repo-local reviewers bare).
           args: { worktree: "$WORKTREE_PATH", base: "$PRE_REVISION_SHA", head: "HEAD",
                   config: CONFIG,
                   reviewers: [<selected per review-toolkit:review-lead Routing>],
                   changedFiles: [<files changed by this revision>] } })
```

Pass `worktree=$WORKTREE_PATH` explicitly (`${WORKTREES_DIR}/pr-${PR_NUMBER}`) rather than relying on `--show-toplevel`. No `issue` arg — scope-completeness is skipped for a revision. Then run review-toolkit:review-lead's Synthesis Rules over the returned findings.

Review contract:

- Max 1 round (these are small targeted fixes, not full implementation)
- If blockers found: fix them, re-run verify (step 7), but do NOT re-run review-toolkit:review-lead (avoid infinite loop)
- If blockers remain after one fix attempt: include them in the push summary as known issues

**Rationale for not blocking:** The revision is already on an open PR under human review. Converting to draft would confuse the reviewer. Known issues are surfaced transparently in the summary.

**Step 2: Push**

```bash
git push origin "$BRANCH"
```

### 9. Completion & Cleanup

**Post summary comment on both the PR and the issue** (dual-post, consistent with main pipeline):

```
<!-- dev-pipeline -->
<!-- run_id: {RUN_ID} -->
<!-- stage: pr-revision -->
<!-- status: completed -->

## PR Revision Summary

**Auto-fixed ({N}):**
- `file:line` — description

**Pushed back ({N}):**
- `file:line` — reason (see thread)

**Awaiting clarification ({N}):**
- `file:line` — proposed approach posted, waiting for confirmation

**Verification:** format ✅ lint ✅ type-check ✅ test ✅
**Scoped review:** {verdict from review-toolkit:review-lead, or "no issues found"}
```

If scoped review had known issues, append: `**Known issues:** {list}`
If stacked-PR base was stale, append: `**Warning:** Base branch X has been updated — consider rebasing.`

**Thread resolution:**

| Tier                   | Thread state                    |
| ---------------------- | ------------------------------- |
| Auto-fix (implemented) | Resolved                        |
| Pushback               | Open (human decides)            |
| Clarify-then-fix       | Open (waiting for confirmation) |

**Label management:**

| Event                                                   | Label action                                |
| ------------------------------------------------------- | ------------------------------------------- |
| Revision completes (success, no pending clarifications) | Remove `in-progress` from issue             |
| Revision completes (Clarify-then-fix pending)           | Keep `in-progress` (signals work in flight) |
| Revision fails (verify)                                 | Keep `in-progress` (signals broken state)   |

**Worktree cleanup:**

| State                                               | Worktree                                                                     |
| --------------------------------------------------- | ---------------------------------------------------------------------------- |
| All comments addressed, no Clarify-then-fix pending | `cd` to repo root, `git worktree remove "${WORKTREES_DIR}/pr-${PR_NUMBER}"` |
| Clarify-then-fix comments pending                   | Keep (re-invocation will resume)                                             |
| Verify failed                                       | Keep (manual rescue)                                                         |

### 10. Resume / Idempotency

When the skill is re-invoked on the same PR:

| State Found                                                                   | Behavior                                                           |
| ----------------------------------------------------------------------------- | ------------------------------------------------------------------ |
| Worktree exists at `${WORKTREES_DIR}/pr-{N}`                                 | Reuse it, pull latest from remote                                  |
| No worktree, branch exists on remote                                          | Create worktree from remote branch                                 |
| Previous revision comments exist (matched by `<!-- dev-pipeline -->` markers) | Skip already-replied threads, process only new/unresolved comments |
| All threads resolved, no new comments                                         | Post "No new comments to address", clean up, stop                  |
| PR is closed or merged                                                        | Post "PR is no longer open — skipping revision", stop              |
| Clarify-then-fix threads have human replies (confirmation)                    | Reclassify confirmed threads as Auto-fix, process normally         |
| Worktree exists but is stale (>7 days since last commit)                      | Remove stale worktree, re-create from remote branch                |

---

## Error Handling Summary

| Failure                                   | Action                                                | Worktree    | Labels                              |
| ----------------------------------------- | ----------------------------------------------------- | ----------- | ----------------------------------- |
| PR not found or closed/merged             | Print message, stop                                   | Not created | No change                           |
| > 50 unresolved comments                  | Post status on PR + issue, stop                       | Not created | No change                           |
| Issue number not extractable from PR body | Warn (post to PR only, skip issue comments), continue | Created     | No label change (no issue to label) |
| Verify fails after 2 fix attempts         | Post error on PR + issue, stop                        | Kept        | `in-progress` stays                 |
| Scoped review blockers after fix attempt  | Include as known issues in summary, push anyway       | Removed     | `in-progress` removed               |
| Stacked-PR base branch stale              | Warn in summary, continue                             | Created     | Normal flow                         |
| `git push` fails                          | Post error on PR + issue, stop                        | Kept        | `in-progress` stays                 |

All failures post a comment with `run_id`. No silent failures.
