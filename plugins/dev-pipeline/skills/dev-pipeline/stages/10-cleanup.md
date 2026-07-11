# Stage 10. Cleanup

**Cleanup policy:**

- **On success (PR opened):** `cd` to repo root, `git worktree remove "${WORKTREES_DIR}/acme-${ISSUE_NUMBER}${SLICE_SUFFIX}"` (WORKTREES_DIR = config `topology.repos.<host>.worktreesDir`) — code is on remote. For stacked-PR runs, each slice's worktree is cleaned up after its PR is opened.
- **On recoverable failure (spec/plan/verify stopped):** keep worktree, include worktree path in the failure comment for manual rescue.
- **On CI:** workspace dies with the runner — no explicit cleanup needed.

---

_Stage 10 of the [dev-pipeline](../SKILL.md) flow. Return to the router for cross-stage contracts (Invocation Routing, Failure Contract, State Persistence, etc.)._
