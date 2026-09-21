# lean review verdict — #867

verdict=needs-work
run_id: review-867-1
session_id: e4125a5b-074b-4ff5-b22e-e8726d57648c
rounds: 1
pr: #874
reviewed_head: 68be90d47143201a90d4410c35d08982425991c6
reviewed_patch_id: c1d29cc9a08dea755a60f7994f4585f13fd9f235
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
panel: review-toolkit:scope-completeness-reviewer
model: opus
capabilities: pr-marker

## Review Summary

Round 1, full range `be5b44cf..68be90d4`. Panel: pipeline default (scope-completeness only), no opt-ins taken. security-reviewer was not selected because the declared panel does not select it, so the lead pass covered security. a11y and design-fidelity were not routed because no web-component path changed. The spec's `## Design` section is absent, so fidelity is `not-applicable`.

The mechanism is right. `tracker.writes` is derived with preflight.sh's default, the deny list lives in one place, both roles go through the one spawn, and the github spawn line is unchanged. `orchestrate-selftest.sh` passes at this head: 150 PASS, 0 FAIL, rc=0, run locally because CI's `lint-and-selftests` was still pending. The `pr-gates` red is only the missing verdict record, which this round supplies.

Two blockers, both small.

## Findings

| # | Severity | Where | Finding |
| --- | --- | --- | --- |
| 1 | blocker | `plugins/dev-pipeline/skills/run/orchestrate.sh:588` | **`addTeamworkGraphContext` is an Atlassian write tool, and the list leaves it off.** I read the live MCP tool description this session. It "Adds a relationship between two entities in the Teamwork Graph (e.g. linking two Jira work items, marking one as blocking another, attaching a remote link, or connecting a Jira work item to an Atlas project or goal)". That is the same write `createIssueLink` makes, and `createIssueLink` is on the list. The PR body's reading that it "adds context to the session" is its own inference, and it does not hold. A lane session under `tracker.writes: false` can still link or block the ticket it is graded against. Fix: add `addTeamworkGraphContext` to `ATLASSIAN_WRITE_TOOLS`. The other 13 names match every write tool the live Rovo MCP exposes. |
| 2 | blocker | `plugins/dev-pipeline/skills/run/orchestrate-selftest.sh:1274` | **(m2a) asserts 5 of the 13 listed names, and AC-3 asks for every listed write tool.** Dropping, say, `createCompassComponent` or `addWorklogToJiraIssue` from the scheduler's list stays green. Fix: have the (m2a) loop cover the full list, including the name from finding 1. |
| 3 | nit | `plugins/dev-pipeline/skills/run/orchestrate.sh:595` | The loop variables `_tool` and `_ns` leak into the script's global scope. This is harmless, and not a blocker. |

## AC scorecard

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | unsatisfied | The list is one variable. Every name is appended under all three namespaces only when writes is false, and no read tool is on it. But the list omits `addTeamworkGraphContext`, which the live MCP describes as creating Jira issue links, blocks and remote links. So "every Atlassian write tool" does not hold (finding 1). |
| AC-2 | satisfied | On the github default and on an explicit `writes: true`, `DISALLOWED_TOOLS` is exactly `AskUserQuestion EnterWorktree ExitWorktree`. Selftests (e1a), (e1b) and (m2b) pass at this head. |
| AC-3 | unsatisfied | (e1b) covers the github arm with no `mcp__` tool and passes. (m2a) runs a jira config with no `writes` key and checks read tools are absent. But it asserts only 5 of the 13 listed write tools, and the AC asks for every one (finding 2). |
| AC-4 | satisfied | The README's "No JIRA writes" paragraph now names the enforcer (the scheduler's `--disallowedTools` under `tracker.writes: false`, all three namespaces, read tools kept). It also names the boundary: a `/dev-pipeline:build` or `/dev-pipeline:review` invoked directly is operator-attended and not covered. |

## Verdicts

| Reviewer | Verdict | Findings | Confidence Range |
| --- | --- | --- | --- |
| Scope Completeness | Pass | 0 | — |
| Security | Lead pass — ❌ | 1 (finding 1) | 95 |
| Performance | Lead pass — ✅ | 0 | — |
| Complexity | Lead pass — ✅ | 0 | — |
| Maintainability | Lead pass — ✅ | 1 nit | 80 |
| Test Coverage | Lead pass — ❌ | 1 (finding 2) | 90 |

**Ready to merge?** No. Both fixes are small, about two lines plus the test loop.
