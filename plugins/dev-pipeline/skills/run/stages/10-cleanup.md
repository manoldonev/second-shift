# Stage 10. Cleanup

**Cleanup policy:**

- **On success (PR opened) — single-repo (`standalone`/`monorepo`):** `cd` to repo root and remove the worktree at the **persisted `worktreePath`** — the exact repo-relative path Stage 2 wrote via `worktree-set`, resolved against repo root: `git worktree remove "$(git rev-parse --show-toplevel)/$(statectl.sh get "$ISSUE_NUMBER" '.worktreePath')"` — code is on remote. Do **NOT** reconstruct the path from a naming literal (`acme-${ISSUE_NUMBER}…`): the worktree dir name is the branch basename `${BRANCH##*/}`, which tracks `tracker.branchPrefix` per consumer, so a hardcoded `acme-` would orphan the worktree for any non-default consumer.
- **On success — be-fe-pair (#4):** remove EACH target repo's worktree from ITS OWN checkout (the `worktrees` map, keyed by `.targetRepos`):
  ```bash
  MAIN_ROOT="$(git rev-parse --show-toplevel)"
  for r in $(statectl.sh get "$ISSUE_NUMBER" '.targetRepos // [] | join(" ")'); do
    RP=$(jq -r --arg r "$r" '.topology.repos[$r].path' "$SECOND_SHIFT_CONFIG")
    WT=$(statectl.sh get "$ISSUE_NUMBER" ".worktrees[\"$r\"].worktreePath // empty")
    [[ -n "$WT" ]] && git -C "$(cd "$MAIN_ROOT/$RP" && pwd)" worktree remove "$MAIN_ROOT/$WT" 2>/dev/null || true
  done
  ```
- **Intake pin worktree (all topologies):** remove the Stage-1 read-pin worktree if it survived (Step 1.P already removes it best-effort after Stage 1; this is the crash backstop). Runs on success AND on the recoverable-failure path below — the pin holds no work product, so it is always safe to drop:
  ```bash
  # WORKTREES_DIR resolves via tools/resolve-worktrees-dir.sh (issue #237) — the single
  # source of truth shared with Stage 1's pin and Stage 2. A resolution failure here is
  # REPORTED, never silently absorbed — the pre-#237 bug was routing an unset/empty
  # WORKTREES_DIR straight into `2>/dev/null || true`, which swallowed the resulting
  # root-path failure and left completed runs (e.g. #230) with a leaked
  # `intake-pin-<n>` worktree and zero signal.
  if WORKTREES_DIR=$(bash "${CLAUDE_PLUGIN_ROOT}/skills/run/tools/resolve-worktrees-dir.sh" "$SECOND_SHIFT_CONFIG" 2>&1); then
    git worktree remove --force "${WORKTREES_DIR}/intake-pin-${ISSUE_NUMBER}" 2>/dev/null || true
  else
    echo "[stage-10] could not resolve topology.repos.<host>.worktreesDir ($WORKTREES_DIR) — intake-pin-${ISSUE_NUMBER} cleanup skipped; note this in the run's completion report for manual follow-up." >&2
  fi
  ```
- **On recoverable failure (spec/plan/verify stopped):** keep worktree, include worktree path in the failure comment for manual rescue.
- **On CI:** workspace dies with the runner — no explicit cleanup needed.

---

_Stage 10 of the [dev-pipeline](../SKILL.md) flow. Return to the router for cross-stage contracts (Invocation Routing, Failure Contract, State Persistence, etc.)._
