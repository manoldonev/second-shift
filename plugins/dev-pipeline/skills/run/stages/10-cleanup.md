# Stage 10. Cleanup

**Cleanup policy:**

- **On success (PR opened):** `cd` to repo root and remove the worktree at the **persisted `worktreePath`** — the exact repo-relative path Stage 2 wrote via `worktree-set`, resolved against repo root: `git worktree remove "$(git rev-parse --show-toplevel)/$(statectl.sh get "$ISSUE_NUMBER" '.worktreePath')"` — code is on remote. Do **NOT** reconstruct the path from a naming literal (`acme-${ISSUE_NUMBER}…`): the worktree dir name is the branch basename `${BRANCH##*/}`, which tracks `tracker.branchPrefix` per consumer, so a hardcoded `acme-` would orphan the worktree for any non-default consumer. For stacked-PR runs, each slice's worktree is cleaned up after its PR is opened (the active slice's `worktreePath` is the one in state).
- **On recoverable failure (spec/plan/verify stopped):** keep worktree, include worktree path in the failure comment for manual rescue.
- **On CI:** workspace dies with the runner — no explicit cleanup needed.

---

_Stage 10 of the [dev-pipeline](../SKILL.md) flow. Return to the router for cross-stage contracts (Invocation Routing, Failure Contract, State Persistence, etc.)._
