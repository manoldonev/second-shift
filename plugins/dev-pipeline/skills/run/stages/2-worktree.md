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

**First, mark the stage started** — per the global Stage write convention (SKILL.md), Stage 2 begins with `statectl set-stage "$ISSUE_NUMBER" 2 --status started` BEFORE the worktree creation below. This stage leads with `git worktree add`, so the started-write is easy to defer until the closing state writes; doing so leaves `stages.2.startedAt` unwritten (`set-stage ... --status completed` then errors with "cannot complete stage 2 with no startedAt"), and even if recovered after the fact, the real work is mis-attributed to the Stage 1→2 gap (a state-discipline deviation `/pipeline-retro` flags). Write `started` first. (`git worktree add` is genuinely sub-second, so this stage's window is honestly ~0 even when marked correctly — the point is correct attribution, not a non-zero number.) **And record the stage-file receipt in the same breath** — `statectl stage-file-read "$ISSUE_NUMBER" --stage 2 --file 2-worktree.md` (#243 §3): `set-stage 2 --status completed` refuses unless stage 2's own file is recorded as read.

**Dynamic context before worktree creation:**

```
!`git worktree list`
!`git branch --list "claude/*"`
```

```bash
# Branch namespace + base are config-driven (single source of truth with Stage 1):
#   BRANCH_PREFIX   = tracker.branchPrefix                 // "claude/acme-"
#   BASE_BRANCH_CFG = host repo (path ".") baseBranch      // "main"
BRANCH_PREFIX=$(jq -r '.tracker.branchPrefix // "claude/acme-"' "$SECOND_SHIFT_CONFIG" 2>/dev/null || echo "claude/acme-")
BASE_BRANCH_CFG=$(jq -r '(.topology.repos | to_entries[] | select(.value.path==".") | .key) as $h | .topology.repos[$h].baseBranch // "main"' "$SECOND_SHIFT_CONFIG" 2>/dev/null || echo "main")

# Every run is a single PR branched from the configured base branch.
BRANCH="${BRANCH_PREFIX}${ISSUE_NUMBER}"
BASE_BRANCH="$BASE_BRANCH_CFG"

# ---- be-fe-pair (#4): one worktree PER target repo ----
# Each target repo (routed in Stage 1 Step 1.T, persisted as .targetRepos) gets a
# worktree in ITS OWN checkout, cut from ITS OWN base branch (BE `alpha` / FE
# `main` may differ), persisted per-repo via `worktree-set --repo`. The single-repo
# block that follows is then skipped. A standalone/monorepo run (TOPO != be-fe-pair)
# falls straight through to that block, unchanged.
TOPO=$(jq -r '.topology.type // "standalone"' "$SECOND_SHIFT_CONFIG" 2>/dev/null || echo standalone)
if [[ "$TOPO" == "be-fe-pair" ]]; then
  MAIN_ROOT="$(git rev-parse --show-toplevel)"
  for r in $(statectl.sh get "$ISSUE_NUMBER" '.targetRepos // [] | join(" ")'); do
    RP=$(jq -r --arg r "$r" '.topology.repos[$r].path' "$SECOND_SHIFT_CONFIG")
    REPO_ABS="$(cd "$MAIN_ROOT/$RP" && pwd)"
    REPO_BASE=$(jq -r --arg r "$r" '.topology.repos[$r].baseBranch // "main"' "$SECOND_SHIFT_CONFIG")
    WTDIR=$(jq -r --arg r "$r" '.topology.repos[$r].worktreesDir // empty' "$SECOND_SHIFT_CONFIG")
    [[ -n "$WTDIR" ]] || WTDIR="../${r}-worktrees"
    WT_REL="${WTDIR}/${BRANCH##*/}"              # host-root-relative — the state canonical form
    git -C "$REPO_ABS" fetch origin "$REPO_BASE" --quiet 2>/dev/null || true
    if git -C "$REPO_ABS" branch --list "$BRANCH" | grep -q .; then
      WT_ERR=$(git -C "$REPO_ABS" worktree add "$MAIN_ROOT/$WT_REL" "$BRANCH" 2>&1); WT_RC=$?
    else
      WT_ERR=$(git -C "$REPO_ABS" worktree add "$MAIN_ROOT/$WT_REL" -b "$BRANCH" "origin/$REPO_BASE" 2>&1); WT_RC=$?
    fi
    if [[ $WT_RC -ne 0 ]]; then
      echo "[stage-2] git worktree add failed for repo '$r' (rc=$WT_RC): $WT_ERR" >&2
      statectl.sh mark-failed "$ISSUE_NUMBER" --reason worktree-creation-failed --stage 2 \
        --json "$(statectl.sh build-failure-context --reason worktree-creation-failed --stage 2 --kv repo="$r" --kv gitError="$WT_ERR")"
      exit 0
    fi
    statectl.sh worktree-set "$ISSUE_NUMBER" --repo "$r" --path "$WT_REL" --branch "$BRANCH" --base "$REPO_BASE"
    echo "[stage-2] be-fe-pair worktree: repo='$r' path='$WT_REL' base='$REPO_BASE'"
  done

  # Flat-mirror the PRIMARY target into the flat worktreePath / branch / worktreeBase
  # so the MIDDLE stages (3/4/5/7/8) — which still read the flat fields — operate on
  # it. A single-target ([FE]-only / [BE]-only) pair run thus flows end-to-end
  # unchanged; Stage 6/9/10 keep using the per-repo `worktrees` map. Primary = the
  # host repo (path ".") when it is a target, else the first target. (Dual-target,
  # where the middle stages must handle BOTH worktrees, is the tracked follow-up.)
  HOST_ID=$(jq -r '.topology.repos | to_entries[] | select(.value.path==".") | .key' "$SECOND_SHIFT_CONFIG" 2>/dev/null | head -n1)
  TR="$(statectl.sh get "$ISSUE_NUMBER" '.targetRepos // [] | join(" ")')"
  PRIMARY=""
  for r in $TR; do [[ "$r" == "$HOST_ID" ]] && PRIMARY="$r"; done
  [[ -n "$PRIMARY" ]] || PRIMARY="${TR%% *}"   # first target when the host isn't one
  P_WT=$(statectl.sh get "$ISSUE_NUMBER" ".worktrees[\"$PRIMARY\"].worktreePath")
  P_BASE=$(statectl.sh get "$ISSUE_NUMBER" ".worktrees[\"$PRIMARY\"].base")
  statectl.sh worktree-set "$ISSUE_NUMBER" --path "$P_WT" --branch "$BRANCH" --base "$P_BASE"
  echo "[stage-2] be-fe-pair flat-mirror: primary='$PRIMARY' worktreePath='$P_WT' base='$P_BASE'"
fi

# Single-repo (standalone/monorepo) worktree creation — SKIPPED for be-fe-pair
# (the per-repo loop above already created + persisted every target's worktree).
if [[ "$TOPO" != "be-fe-pair" ]]; then

# Cut the branch from the freshly-fetched remote-tracking ref `origin/<baseBranch>`,
# not a possibly-stale local ref. A concurrent merge can advance the base mid-run;
# cutting from a transiently-stale local ref starts the branch on stale files and
# silently implements against them.
git fetch origin "$BASE_BRANCH_CFG" --quiet 2>/dev/null || true
BASE_BRANCH="origin/$BASE_BRANCH_CFG"

# Resume support: reuse existing branch if it exists.
# Capture stderr so a failure can be recorded in failureContext.gitError.
# WORKTREES_DIR = the host repo's configured worktrees dir
# (config `topology.repos.<host>.worktreesDir`). The worktree dir name is the
# branch basename (`${BRANCH##*/}` — strips the `tracker.branchPrefix` namespace,
# e.g. `claude/acme-42` -> `acme-42`, `team/gh-42` -> `gh-42`), so it is
# config-derived, never a hardcoded `acme-` literal.
WT_PATH="${WORKTREES_DIR}/${BRANCH##*/}"
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
fi   # end single-repo (TOPO != be-fe-pair) worktree creation
```

- `cd` into the worktree for ALL subsequent work.
- All file paths in stages 3-9 are relative to the worktree root.
- The worktree dir name is the branch basename `${BRANCH##*/}` — for the github default that is `acme-${ISSUE_NUMBER}`, but it tracks `tracker.branchPrefix` for any consumer.
- Do **NOT** run `yarn install` here. The Stage 6 verification matrix installs deps only when the diff actually requires the configured verify suite (~50s saved on inert diffs); the pre-commit type-check hook is staged-path-aware, so docs/shell-only commits don't need `node_modules` either.

**State:** Persist both boundary fields atomically via statectl. **be-fe-pair runs skip this block** — the per-repo `worktree-set --repo <id>` calls in the loop above already persisted every target's boundary fields into the `worktrees` map; only the single-repo path writes the flat top-level fields here:

```bash
if [[ "$(jq -r '.topology.type // "standalone"' "$SECOND_SHIFT_CONFIG" 2>/dev/null || echo standalone)" != "be-fe-pair" ]]; then
  statectl.sh worktree-set "$ISSUE_NUMBER" \
    --path "${WORKTREES_DIR}/${BRANCH##*/}" \
    --branch "$BRANCH"
fi
```

**Canonical path form:** `worktreePath` is persisted in **repo-relative** form (`${WORKTREES_DIR}/${BRANCH##*/}` for single-repo; `worktrees.<id>.worktreePath` host-root-relative for be-fe-pair, as written above). This is the contract — `worktree-set` rejects an absolute path (leading `/`). The pipeline always runs with CWD at the repo root, so consumers resolve the value against the repo root (`git -C "$worktreePath" …` at the Stage 8 entry, `cd "$worktreePath"`); see state-schema.md "Worktree".

**Ordering contract:** this call MUST precede `set-stage 2 --status completed` — a completed Stage 2 then always implies the boundary fields are present, so a crash between the two writes leaves Stage 2 merely in-progress (resumable), never "complete but unresumable" (Stage 8's crash-recovery entry asserts `worktreePath` is valid).

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

The session id is the **native Claude Code session UUID** (`$CLAUDE_CODE_SESSION_ID`) — the exact value the OTel exporter tags datapoints with as `session.id`, so Stage 9's cost block can match it. The subcommand is idempotent on `sessionId`, so it records **one record per Claude session**: a normal run records one id; a crash-recovery Stage 8 resume runs in a fresh session and records its own (distinct) UUID. If `CLAUDE_CODE_SESSION_ID` is unset (e.g. a non-interactive environment), recording is skipped and cost tracking degrades gracefully to `skipped-no-sessions`.

---

_Stage 2 of the [dev-pipeline](../SKILL.md) flow. Return to the router for cross-stage contracts (Invocation Routing, Failure Contract, State Persistence, etc.)._
