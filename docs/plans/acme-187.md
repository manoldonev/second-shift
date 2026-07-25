# Plan — #187: scope-completeness-reviewer's hardcoded MCP prefix makes the scope gate unsatisfiable

## Context / problem framing

`scope-completeness-reviewer` reaches the tracker (JIRA) through a **hardcoded MCP tool prefix**, `mcp__atlassian__*`, declared statically in its agent frontmatter `tools:` line and hard-named in its Step 1 protocol. When a session registers the Atlassian MCP under a different namespace — a plugin-bundled server (`mcp__plugin_atlassian_atlassian__*`) or the claude.ai Rovo integration (`mcp__claude_ai_Atlassian_Rovo__*`) — the declared tools are absent from the reviewer's surface, the fetch returns `BLOCKED`, and because `BLOCKED` is treated as `FAIL` on a hard gate, the Scope Completeness Gate is **permanently unsatisfiable** for that consumer.

`figma.mjs` already solved the identical problem for the Figma MCP: it `select:`-ToolSearches **both** namespace variants and uses whichever resolves (`figma.mjs:20-31`). `scope-completeness-reviewer` never got the same treatment.

Empirical grounding (observed on this machine's session): the bare `mcp__atlassian__*` namespace exposes only `authenticate` / `complete_authentication`; the actual Jira tools (`getJiraIssue`, `getJiraIssueRemoteIssueLinks`, `getAccessibleAtlassianResources`) are present **only** under `mcp__plugin_atlassian_atlassian__*` and `mcp__claude_ai_Atlassian_Rovo__*`. A two-namespace fix (the issue's literal suggestion) would still leave a Rovo-registered consumer broken, so this fix covers all three.

## Assumptions

- The reviewer is dispatched as a Workflow `agent()` from `code-review.mjs` (Stage 8 fan-out), where MCP tools are deferred — the same surface `figma.mjs` documents. `ToolSearch` is therefore the reliable discovery mechanism; the static frontmatter grant is retained as belt-and-suspenders for the top-level path that works today.
- Declaring a tool name in an agent's `tools:` frontmatter that the current session does not register is harmless (already true today — the github-only path declares `mcp__atlassian__*` and never calls it).
- The agent's own Step 1 protocol is authoritative for the fetch ("Always fetch the issue yourself, regardless of what the dispatch prompt says"); the `code-review.mjs` dispatch prompt is reinforcement and must stop mis-directing to a single hardcoded name.
- This repo's CI is model-free (`CLAUDE.md`), so the live JIRA-under-plugin behavior cannot be exercised in CI; the regression guard is a **static** namespace-coverage check.

## Decision Ledger

| D-n | Decision | Provenance |
| --- | --- | --- |
| D-1 | Cover all three real Atlassian namespaces (`mcp__atlassian__`, `mcp__plugin_atlassian_atlassian__`, `mcp__claude_ai_Atlassian_Rovo__`), not just the two named in the issue — the Rovo namespace carries the Jira tools on this very machine, so omitting it recreates the bug. | codebase-derived |
| D-2 | Apply both mechanisms `figma.mjs` distinguishes: keep the static `tools:` grant (all namespaces) AND add a `ToolSearch` discovery step in Step 1, rather than betting a static grant alone un-defers the tools in a Workflow subagent. | codebase-derived |
| D-3 | Include the cheap half of the issue's fix #2 (the `BLOCKED` message names the probed namespaces so a tool-surface gap is legible), but DEFER the round-1 tool-surface short-circuit optimization — the issue itself marks it "worth considering separately". | codebase-derived |
| D-4 | Regression guard is a static `scripts/check-*.sh` + `-selftest.sh` pair asserting the agent declares every namespace and carries the ToolSearch discovery step; no live-JIRA test (model-free CI cannot run one). | codebase-derived |
| D-5 | Scope the static check to the review-toolkit agent (the authoritative fetcher). Also fix the `code-review.mjs` dispatch prompt, but keep the CI guard within the review-toolkit plugin to avoid cross-plugin coupling. | codebase-derived |

## Affected files/modules

- `plugins/review-toolkit/agents/scope-completeness-reviewer.md` — existing `[UNVERIFIED]`-free, verified present. Edit: `tools:` frontmatter (add `ToolSearch` + the plugin & Rovo namespace tool names), Step 1 fetch protocol (ToolSearch-discover-then-call), and the `BLOCKED` reason (name probed namespaces).
- `plugins/dev-pipeline/skills/run/workflows/code-review.mjs` — verified present (dispatch block at lines 305–344). Edit: the `trackerType === 'jira'` `fetchInstr` (lines 315–318) → namespace-agnostic ToolSearch instruction; add a shared `ATLASSIAN_MCP_TOOLSEARCH` constant mirroring `figma.mjs`'s `FIGMA_MCP_TOOLSEARCH`.
- `plugins/review-toolkit/scripts/check-scope-tracker-namespaces.sh` — `[NEW]` static lint.
- `plugins/review-toolkit/scripts/check-scope-tracker-namespaces-selftest.sh` — `[NEW]` proves the lint (green on the real agent, red on a fixture missing a namespace).

## Reuse inventory

- `figma.mjs`'s `FIGMA_MCP_TOOLSEARCH` (`plugins/dev-pipeline/skills/run/workflows/figma.mjs:27`) — the `select:`-both-namespaces pattern to mirror for the new `ATLASSIAN_MCP_TOOLSEARCH` constant. Verified present.
- The `scripts/check-*.sh` + `check-*-selftest.sh` house pattern (e.g. `check-reviewer-references.sh`, `check-model-tiers.sh`) — mirror its shape (env-overridable roots, stderr errors, exit-code contract). Verified present.
- No new runtime helper is introduced — the new files are a static lint + its selftest. No new production helper: none.

## Implementation steps

1. **Agent frontmatter** (`scope-completeness-reviewer.md:4`): extend `tools:` to add `ToolSearch` and the plugin + Rovo variants of the three Jira tools, keeping the existing `mcp__atlassian__*` entries. Result lists all three namespaces × {getJiraIssue, getJiraIssueRemoteIssueLinks, getAccessibleAtlassianResources} plus `ToolSearch`.
2. **Agent Step 1 protocol** (jira branch, ~lines 37–46): replace the single hard-named fetch instruction with a namespace-agnostic one — `ToolSearch` (`select:` all three namespaces' `getJiraIssue` + `getAccessibleAtlassianResources`), call whichever `getJiraIssue` resolves, resolving `cloudId` via whichever `getAccessibleAtlassianResources` resolves. Only if none resolve after the ToolSearch probe → `BLOCKED`.
3. **Agent BLOCKED reason** (~lines 42–46): the BLOCKED text names the namespaces probed, so review-lead / the operator can tell "tracker genuinely unreachable" from "tool under an unprobed name" — the legible-failure half of fix #2.
4. **code-review.mjs**: add `ATLASSIAN_MCP_TOOLSEARCH` constant (mirroring `FIGMA_MCP_TOOLSEARCH`); rewrite the `jira` `fetchInstr` (lines 315–318) to instruct ToolSearch-then-call-resolved-name instead of hard-naming `mcp__atlassian__getJiraIssue`.
5. **New static lint** `check-scope-tracker-namespaces.sh`: assert the agent's `tools:` line contains every required namespace prefix AND the Step 1 protocol references the ToolSearch discovery; non-zero + stderr message on any missing namespace. Env-overridable root for hermetic selftest.
6. **New selftest** `check-scope-tracker-namespaces-selftest.sh`: green against the real agent; red against a temp fixture with one namespace stripped (proves the guard bites).

## Test strategy

Verify-after (infra/prose change — no runtime behavior in the configured `unitTestScope`, which is unset for this shell/markdown repo). The new lint is the behavioral guard; its selftest proves it. Live JIRA-under-plugin behavior is un-testable in model-free CI (accepted, D-4).

## Acceptance-criteria traceability

State's intake AC snapshot is empty (the issue carries no `## Acceptance Criteria` section), so the scope gate uses the synthetic whole-change item. The plan-local criteria below (defined at intake as D-1..D-4) trace to steps and tests:

| AC ID | Criterion (short) | Step(s) | Test(s) |
| --- | --- | --- | --- |
| PL-1 | Agent tool surface + protocol cover all three Atlassian namespaces | 1, 2 | `check-scope-tracker-namespaces-selftest.sh` |
| PL-2 | Fetch is namespace-agnostic (ToolSearch-discover-then-call), not a hardcoded prefix | 2, 4 | `check-scope-tracker-namespaces-selftest.sh` |
| PL-3 | BLOCKED reason names probed namespaces (legible tool-surface gap) | 3 | — no test (covered-by-selftest) — asserted by the lint's protocol-string check |
| PL-4 | Static regression guard exists and bites when a namespace is dropped | 5, 6 | `check-scope-tracker-namespaces-selftest.sh` (red-on-fixture case) |

(`PL-n` = plan-local IDs; not an intake snapshot, which is empty.)

## Verification commands

```bash
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -n1 -I{} env SKIP_STRESS=1 bash {}
node --check plugins/dev-pipeline/skills/run/workflows/code-review.mjs
```

## Risks / rollback notes

- **Risk:** frontmatter listing a non-registered namespace tool could theoretically fail agent load. Mitigation: already the status quo (github-only sessions declare `mcp__atlassian__*` and load fine); declaring absent tools is a no-op grant.
- **Risk:** the ToolSearch step adds a turn to the reviewer's budget. Mitigation: one `select:` call is cheap and the reviewer's `maxTurns` is 30 with a turn-20 backstop; negligible.
- **Rollback:** revert the branch; the change is additive (extra namespaces + a discovery step + a new lint). No data migration. Migration: none.

## Out-of-scope

- The round-1 tool-surface short-circuit optimization (detect tool-surface failure before spending a review round) — the issue marks it "worth considering separately"; a follow-up.
- Changing the hard-gate semantics of `BLOCKED == FAIL` in review-lead — untouched; only the BLOCKED *message* gains probed-namespace detail.
- Any non-Atlassian tracker MCP.

Unverified references: none.
