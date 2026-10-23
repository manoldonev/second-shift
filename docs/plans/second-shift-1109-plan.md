# Plan — the BUILD's hook allows `chmod +x` on a worktree file

## 1. The hook allow

- [ ] 1.1 Hook cases: `chmod +x` is allowed on a relative and an absolute worktree path; it is withheld on a path outside the worktree and through a symlink that leads out of it; it is denied in a `.claude/` subdirectory, in the scratch dir and in any other form (plugins/dev-pipeline/tools/lane-permission-hook-selftest.sh) [AC-1] [AC-3]
- [ ] 1.2 The hook allows `chmod +x` when every operand resolves inside the worktree and outside its `.claude/` subdirectories (plugins/dev-pipeline/tools/lane-permission-hook.sh)

## 2. The build reaches the review

- [ ] 2.1 Scenario: a fake-claude build runs `chmod +x` on a new script, commits it, leaves a clean tree and reaches the review with `100755` on the branch; the BUILD's hook, run as its `--settings` writes it, allows `chmod +x` on a worktree file (plugins/dev-pipeline/skills/run/run-claim-selftest.sh) [AC-2]
- [ ] 2.2 The fake `claude` gains a build behavior that makes a new script executable and commits it (plugins/dev-pipeline/skills/run/run-selftest-lib.sh)
