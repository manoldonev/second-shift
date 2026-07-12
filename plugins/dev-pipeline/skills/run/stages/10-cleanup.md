# Stage 10. Cleanup

**Cleanup policy:**

- **On success (PR opened) — single-repo (`standalone`/`monorepo`):** `cd` to repo root and remove the worktree at the **persisted `worktreePath`** — the exact repo-relative path Stage 2 wrote via `worktree-set`, resolved against repo root: `git worktree remove "$(git rev-parse --show-toplevel)/$(statectl.sh get "$ISSUE_NUMBER" '.worktreePath')"` — code is on remote. Do **NOT** reconstruct the path from a naming literal (`acme-${ISSUE_NUMBER}…`): the worktree dir name is the branch basename `${BRANCH##*/}`, which tracks `tracker.branchPrefix` per consumer, so a hardcoded `acme-` would orphan the worktree for any non-default consumer. For stacked-PR runs, each slice's worktree is cleaned up after its PR is opened (the active slice's `worktreePath` is the one in state).
- **On success — be-fe-pair (#4):** remove EACH target repo's worktree from ITS OWN checkout (the `worktrees` map, keyed by `.targetRepos`):
  ```bash
  MAIN_ROOT="$(git rev-parse --show-toplevel)"
  for r in $(statectl.sh get "$ISSUE_NUMBER" '.targetRepos // [] | join(" ")'); do
    RP=$(jq -r --arg r "$r" '.topology.repos[$r].path' "$SECOND_SHIFT_CONFIG")
    WT=$(statectl.sh get "$ISSUE_NUMBER" ".worktrees[\"$r\"].worktreePath // empty")
    [[ -n "$WT" ]] && git -C "$(cd "$MAIN_ROOT/$RP" && pwd)" worktree remove "$MAIN_ROOT/$WT" 2>/dev/null || true
  done
  ```
- **Intake pin worktree (#59, all topologies):** remove the Stage-1 read-pin worktree if it survived (Step 1.P already removes it best-effort after Stage 1; this is the crash backstop): `git worktree remove --force "${WORKTREES_DIR}/intake-pin-${ISSUE_NUMBER}" 2>/dev/null || true`. Runs on success AND on the recoverable-failure path below — the pin holds no work product, so it is always safe to drop.
- **On recoverable failure (spec/plan/verify stopped):** keep worktree, include worktree path in the failure comment for manual rescue.
- **On CI:** workspace dies with the runner — no explicit cleanup needed.

---

_Stage 10 of the [dev-pipeline](../SKILL.md) flow. Return to the router for cross-stage contracts (Invocation Routing, Failure Contract, State Persistence, etc.)._
