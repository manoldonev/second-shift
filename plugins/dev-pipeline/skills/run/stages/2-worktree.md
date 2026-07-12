# Stage 2. Create Worktree + Branch

> **Tracker delta (config `tracker.type: jira`).** Branch naming is config-driven:
> the work branch is `<tracker.branchPrefix><ticketKey>` — `claude/acme-42`
> (github default) or `jdoe/gh-540` (jira, `branchPrefix` a per-user `jdoe/`). When
> `tracker.branchPrefix` is unset in a jira repo, detect the identifier once from
> existing `*/gh-*` branches (`git branch -r --sort=-committerdate`), confirm with
> the operator, and cache it (`userIdentifier` in state); config is the durable home.
> For a **be-fe-pair** topology (common with JIRA) create one worktree per target
> repo (`git -C <repoPath> worktree add`), each branching from that repo's configured
> `baseBranch` (which may differ, e.g. BE `alpha` / FE `main`). See
> [`tools/tracker/jira/`](../tools/tracker/jira/README.md).

**First, mark the stage started** — per the global Stage write convention (SKILL.md), Stage 2 begins with `statectl set-stage "$ISSUE_NUMBER" 2 --status started` BEFORE the worktree creation below. This stage leads with `git worktree add`, so the started-write is easy to defer until the closing state writes; doing so leaves `stages.2.startedAt` unwritten (`set-stage ... --status completed` then errors with "cannot complete stage 2 with no startedAt"), and even if recovered after the fact, the real work is mis-attributed to the Stage 1→2 gap (a state-discipline deviation `/pipeline-retro` flags). Write `started` first. (`git worktree add` is genuinely sub-second, so this stage's window is honestly ~0 even when marked correctly — the point is correct attribution, not a non-zero number.)

**Dynamic context before worktree creation:**

```
!`git worktree list`
!`git branch --list "claude/*"`
```

```bash
# Read slice-derived fields from state (written by Stage 1 outer-loop preamble
# for stacked-PR runs; absent for single-PR runs).
SLICE_BRANCH=$(statectl.sh get "$ISSUE_NUMBER" '.sliceBranch // empty')
WORKTREE_BASE=$(statectl.sh get "$ISSUE_NUMBER" '.worktreeBase // empty')

# Single-PR fallback: no stacked-PR fields in state.
if [[ -z "$SLICE_BRANCH" || "$SLICE_BRANCH" == "null" ]]; then
  BRANCH="claude/acme-${ISSUE_NUMBER}"
  BASE_BRANCH="main"
  SLICE_SUFFIX=""
else
  BRANCH="$SLICE_BRANCH"
  BASE_BRANCH="$WORKTREE_BASE"
  # Slice 1's branch is unsuffixed; slice N>1 has -prN suffix.
  if [[ "$BRANCH" == "claude/acme-${ISSUE_NUMBER}" ]]; then
    SLICE_SUFFIX=""
  else
    SLICE_SUFFIX="-${BRANCH##*-}"  # e.g. -pr2
  fi
fi

# Stacked-PR resume sanity guard (stacked runs only — SLICE_BRANCH was set above).
# Read-only assertion, NOT a re-derivation: the precedence rule (state-schema.md
# "Stacked-PR slice state") keeps persisted currentSlice authoritative. We only
# STOP on a structurally impossible state — persisted currentSlice points past the
# end of the real work (one or more intermediate slices were never pushed).
# Normal advancement only raises M; post-merge branch deletion lowers the pushed
# set only below currentSlice — neither can make currentSlice > M+1. So this never
# false-positives on a legitimate resume.
if [[ -n "$SLICE_BRANCH" && "$SLICE_BRANCH" != "null" ]]; then
  CURRENT_SLICE=$(statectl.sh get "$ISSUE_NUMBER" '.currentSlice // empty')
  git fetch origin --quiet 2>/dev/null || true
  # Highest pushed slice from the remote, via the shared tested derivation helper
  # (single source of truth with Stage 1 seeding — see tools/max-pushed-slice.sh).
  MAX_PUSHED=$(git ls-remote --heads origin "claude/acme-${ISSUE_NUMBER}*" 2>/dev/null \
    | awk '{print $2}' \
    | bash "${CLAUDE_PLUGIN_ROOT}/skills/run/tools/max-pushed-slice.sh" "$ISSUE_NUMBER")
  if [[ -n "$CURRENT_SLICE" && "$CURRENT_SLICE" != "null" && "$CURRENT_SLICE" -gt $((MAX_PUSHED + 1)) ]]; then
    echo "[stage-2] STOP: persisted currentSlice=$CURRENT_SLICE is inconsistent with the remote branch set (highest pushed slice=$MAX_PUSHED). Slices $((MAX_PUSHED + 1))..$((CURRENT_SLICE - 1)) were never pushed — the state file is corrupt or hand-edited. Not overwriting slice state. Inspect .claude/pipeline-state/${ISSUE_NUMBER}.json and the open PR set, then re-run." >&2
    # Autonomous abort: do not claim/overwrite; stop emitting tool calls (rc=0).
    # Under DEV_PIPELINE_MODE=interactive: present the facts and ask whether to
    # repair currentSlice or abort.
    exit 0
  fi
fi

# For slice N>1, ensure the prior slice's branch is available locally so
# `git worktree add -b <new> <base>` can resolve <base>. Best-effort fetch;
# fall through if the branch is already local.
if [[ "$BASE_BRANCH" != "main" ]]; then
  git fetch origin "$BASE_BRANCH:$BASE_BRANCH" 2>/dev/null \
    || git fetch origin "$BASE_BRANCH" 2>/dev/null \
    || true
fi

# When basing on main (single-PR runs and stacked slice 1), cut the branch from the
# freshly-fetched remote-tracking ref `origin/main`, not a possibly-stale local `main`.
# A concurrent merge can advance `origin/main` mid-run; cutting from a transiently-stale
# local `main` starts the branch on stale files and silently implements against them.
# Slice N>1 bases on the prior slice's branch (fetched just above), never `main`, so this
# remaps only the `main` case and leaves stacking intact.
if [[ "$BASE_BRANCH" == "main" ]]; then
  git fetch origin main --quiet 2>/dev/null || true
  BASE_BRANCH="origin/main"
fi

# Resume support: reuse existing branch if it exists.
# Capture stderr so a failure can be recorded in failureContext.gitError.
# WORKTREES_DIR = the host repo's configured worktrees dir
# (config `topology.repos.<host>.worktreesDir`).
WT_PATH="${WORKTREES_DIR}/acme-${ISSUE_NUMBER}${SLICE_SUFFIX}"
if git branch --list "$BRANCH" | grep -q .; then
  WT_ERR=$(git worktree add "$WT_PATH" "$BRANCH" 2>&1)
else
  WT_ERR=$(git worktree add "$WT_PATH" -b "$BRANCH" "$BASE_BRANCH" 2>&1)
fi
WT_RC=$?

if [[ $WT_RC -ne 0 ]]; then
  echo "[stage-2] git worktree add failed (rc=$WT_RC): $WT_ERR" >&2
  # Autonomous default: record the failure atomically and STOP (rc=0).
  statectl.sh mark-failed "$ISSUE_NUMBER" \
    --reason worktree-creation-failed --stage 2 \
    --json "$(statectl.sh build-failure-context \
      --reason worktree-creation-failed --stage 2 \
      --kv gitError="$WT_ERR")"
  # No worktree was created — nothing to remove. Keep `in-progress` for manual
  # rescue (the issue is already claimed; reverting it would orphan the run).
  # No issue comment is posted (Stage 2 has no comment marker; see the Error
  # Handling Summary footer carve-out in SKILL.md) — the state file + the
  # autonomous-abort turn carry the reason. STOP emitting tool calls.
  #
  # Under DEV_PIPELINE_MODE=interactive: skip the mark-failed write; surface
  # $WT_ERR to the user and ask how to proceed (retry, abort, manual fix).
  exit 0
fi
```

- `cd` into the worktree for ALL subsequent work.
- All file paths in stages 3-9 are relative to the worktree root.
- For stacked-PR runs, `SLICE_SUFFIX` is `-pr${N}` (e.g., `-pr2`, `-pr3`). For slice 1 / single-PR runs it is empty (the worktree path is `${WORKTREES_DIR}/acme-${ISSUE_NUMBER}`).
- Do **NOT** run `yarn install` here. The Stage 6 verification matrix installs deps only when the diff actually requires the configured verify suite (~50s saved on inert diffs); the pre-commit type-check hook is staged-path-aware, so docs/shell-only commits don't need `node_modules` either.

**State:** Persist both boundary fields atomically via statectl:

```bash
statectl.sh worktree-set "$ISSUE_NUMBER" \
  --path "${WORKTREES_DIR}/acme-${ISSUE_NUMBER}${SLICE_SUFFIX}" \
  --branch "$BRANCH"
```

**Canonical path form:** `worktreePath` is persisted in **repo-relative** form (`${WORKTREES_DIR}/acme-${ISSUE_NUMBER}${SLICE_SUFFIX}`, as written above). This is the contract — `worktree-set` rejects an absolute path (leading `/`). The pipeline always runs with CWD at the repo root, so consumers resolve the value against the repo root (`git -C "$worktreePath" …` at the Stage 8 entry, `cd "$worktreePath"`); see state-schema.md "Worktree".

**Ordering contract:** this call MUST precede `set-stage 2 --status completed` — a completed Stage 2 then always implies the boundary fields are present, so a crash between the two writes leaves Stage 2 merely in-progress (resumable), never "complete but unresumable" (Stage 8's crash-recovery entry asserts `worktreePath` is valid). In stacked-PR mode both fields are overwritten per slice (by design — see state-schema.md "Worktree").

**Record pipeline session (for cost attribution at Stage 9):**

```bash
if [[ -n "${CLAUDE_CODE_SESSION_ID:-}" ]]; then
  bash statectl.sh pipeline-session-add "$ISSUE_NUMBER" \
    --session-id "$CLAUDE_CODE_SESSION_ID" \
    --source interactive
else
  echo "[stage-2] CLAUDE_CODE_SESSION_ID unset — skipping cost-attribution session record (Stage 9 will degrade to skipped-no-sessions)"
fi
```

The session id is the **native Claude Code session UUID** (`$CLAUDE_CODE_SESSION_ID`) — the exact value the OTel exporter tags datapoints with as `session.id`, so Stage 9's cost block can match it. The subcommand is idempotent on `sessionId`, so it records **one record per Claude session**: a single-PR run records one id; a stacked-PR run iterating slices within the same session collapses to that same one id; a crash-recovery Stage 8 resume runs in a fresh session and records its own (distinct) UUID. If `CLAUDE_CODE_SESSION_ID` is unset (e.g. a non-interactive environment), recording is skipped and cost tracking degrades gracefully to `skipped-no-sessions`.

---

_Stage 2 of the [dev-pipeline](../SKILL.md) flow. Return to the router for cross-stage contracts (Invocation Routing, Failure Contract, State Persistence, etc.)._
