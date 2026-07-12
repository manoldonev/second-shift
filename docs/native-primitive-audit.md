# Native-primitive audit (D-14)

The pipeline machinery predates several Claude Code native capabilities. This table records, per hand-rolled mechanic, whether v1 keeps it, replaces it with the native primitive, or defers the swap to v2 — so the public plugin doesn't fossilize 2025-era workarounds. "Verify live" = needs a runtime check in a real session before the verdict is final.

| Hand-rolled mechanic | Native primitive (2026) | Verdict | Rationale |
| --- | --- | --- | --- |
| Stage-2 worktree plumbing (`../<repo>-worktrees`, branch naming, cross-repo pairs) | Native worktree isolation (EnterWorktree / `isolation: worktree`) | **Defer (v2), verify live** | Native worktrees are session-scoped and auto-cleaned; the pipeline needs named, persistent, resumable worktrees shared across sessions and repo pairs. Re-evaluate once native worktrees support naming/persistence. |
| `statectl` state machine (typed stages, checkpoints, mark-failed reasons, migrate, validators) | Native Tasks (TaskCreate/TaskUpdate + deps), plan files | **Keep** | Crash-recoverable, schema-validated, greppable JSON state with failure taxonomy is the pipeline's core contract; native Tasks are session-scoped progress UX, not durable machine state. Use Tasks *in addition* for operator visibility. |
| `.mjs` Workflow scripts (code-review, plan-review, mutation-gate…) | Workflow tool | **Keep (already native)** | These *are* the native deterministic-orchestration primitive; only agent references change (namespacing). |
| `review-lead` orchestration | Built-in `/code-review` (incl. ultra) | **Keep, positioned as a layer** | `/code-review` is a generalist pass; review-lead adds the domain reviewer panel, confidence protocol, registry/config, model-tier control, and audit trail. Docs must say "use /code-review for quick checks; review-lead for the gated pipeline review". Ultra/cloud review stays out of the core path (subscription-first, D-13). |
| `exitplan-ledger-gate.sh` hook on ExitPlanMode | Plan mode + plan files | **Keep (already layered)** | The gate builds on native plan mode; nothing to replace. |
| `pre-commit-typecheck.sh` PreToolUse hook | Native `/verify` skill, hooks system | **Keep** | Hooks are the native mechanism; the script just becomes config-driven (typecheck command per repo). `/verify` complements Stage 6, doesn't replace commit gating. |
| `audit-tool-calls.sh` ledger + `/audit` skills | Harness telemetry / OTel | **Keep** | No native user-owned, per-repo, greppable tool-call ledger exists; OTel is operator-level. |
| `pipeline-cost-block.sh` OTel estimate | Native cost surfaces (`/cost`, OTel metrics) | **Keep, verify live** | Per-run cost attribution across sessions still isn't native; revisit if the harness grows per-task cost APIs. |
| Hand-rolled subagent dispatch conventions in stage files | Agent tool + SendMessage (agent continuation), background agents | **Defer (v2)** | SendMessage-based continuation could simplify multi-round review loops; not load-bearing for extraction. |
| `findings.md` session-start read | Native per-user memory | **Keep both** | findings.md is team-shared repo knowledge (committed); native memory is per-user. Complementary, not redundant. |
| Skill/agent file formats | Agent Skills standard, AGENTS.md | **Keep (compliance check at extraction)** | D-15: frontmatter stays standard-compliant; Claude-Code-specific mechanics confined to dev-pipeline. |

**v2 backlog seeds:** native-worktree swap; SendMessage review loops; per-task cost APIs.
