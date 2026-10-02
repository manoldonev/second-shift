# Intake receipt — #908

## Decision Ledger

| ID  | Decision | Resolution | Provenance | Kind |
| --- | -------- | ---------- | ---------- | ---- |
| D-1 | How run.sh stops a headless BUILD ending its run on a backgrounded long check | Prevent it at spawn: the BUILD session is launched with CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1, BASH_DEFAULT_TIMEOUT_MS and BASH_MAX_TIMEOUT_MS, passed as `--settings '{"env":…}'` rather than the process env, so checks run in the foreground. No session re-entry (--resume), no fresh-retry safety net; build-inflight stays as it is for any other cause. Departed at review: the process env loses to a repo's own settings.json `env` (the docs: a settings `env` entry replaces the shell's value), while `--settings` sits above the user, project and local files | user-delegated | intent |
| D-2 | Which spawned sessions get that env | BUILD gets the no-background env. REVIEW keeps background tasks, because review-lead's Workflow panel runs as one, never inherits the BUILD's switch from the launching shell, and gets CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS. Departed at review: -p stops waiting on a running background Workflow after 600 s idle by default and drops its result; the raise run-lean carried for this was lost when run.sh replaced it | user-delegated | intent |
| D-3 | The session timeout values | BUILD's Bash timeouts and REVIEW's background-task wait are both 300 s inside that session's bound, never below the harness's own default (120 s for Bash, 600 s for the wait), and capped at the JS timer maximum 2147483647 ms; no new config key. Departed at review: at the full bound a hung command used up the whole build and was killed without a result or a price | user-delegated | intent |
| D-4 | A headless line in the build prompt | None. The env enforces the behavior; the prompt is unchanged | user-answered | intent |
| D-5 | Whether the env works under claude -p | Measured 2026-10-02 on Claude Code 2.1.287: as process env, a claude -p session ran `sleep 150` in the foreground and returned after 155 s; as `--settings` env with no `timeout` parameter passed, it returned after 156 s. The official env-vars page documents all three: the DISABLE switch turns off `run_in_background` and auto-backgrounding, and the default timeout is what a call that passes no timeout gets, so each one is load-bearing | codebase-derived | fact |
| D-6 | The fresh-process rule | Kept: every session is still a fresh process (run.sh:42) and the F1 assertion (run-selftest.sh, no --resume/--continue) still holds | codebase-derived | fact |
| D-7 | The guard | run-selftest.sh cases [F-env]: the BUILD's and the REVIEW's applied env, the 120 s floor, the integer-only bounds and the REVIEW never inheriting the switch. Each fails without the change (CLAUDE.md: a run.sh behavior change lands with a run-selftest.sh case) | codebase-derived | fact |
| D-8 | Commit verb and changelog | PR title `fix(dev-pipeline): …` (patch), and a consumer-visible `Changelog:` trailer covering the BUILD and REVIEW env, the integer-only bounds and the intake change. Migration: a fractional `RUN_*` count or bound is now refused (CLAUDE.md commit-verb and trailer rules) | codebase-derived | fact |
| D-9 | Build model | opus (operator standing rule for this repo) | user-answered | intent |
| D-10 | Lane admission | Not admitted under CLAUDE.md's admission rule: the ticket body records only this repo's lane. The operator queued it by hand on 2026-10-02 and launched the run | user-answered | intent |
| D-11 | The open region on what the DISABLE switch takes from BUILD | Closed by the env-vars page: it turns off background Bash, background subagents and auto-backgrounding; foreground Agent dispatch (the design-frames plan check) still works, and Workflow is not in BUILD's allowlist | codebase-derived | fact |
| D-12 | Fractional counts and bounds | `cap` takes maxRounds, checksRedMax and both timeouts as positive integers only, accepting a whole-number `7200.0` (config-lint passes it and `jq -r` prints it so) and a zero-padded value. Found at review: a fractional bound failed the new arithmetic, abandoned the round loop and fell through to close-out as a phantom `approved` | user-delegated | intent |
| D-13 | `claude --bg` as the spawn | Rejected: #810 moved the scheduler to `--bg`, #816 and #819 fixed what that broke, and #881 went back to `-p` for `--permission-prompts none`, `permission_denials`, `total_cost_usd`, `--allowedTools` and `--max-turns`, none of which `--bg` offers. A probe the same day confirmed `--bg` survives the turn-ends-on-a-background-task path; it is not worth what run.sh would give up | user-delegated | intent |
| D-14 | Children of the BUILD session | They inherit the env, including any nested `claude` a repo's checks start. Accepted: a nested session in a check gets the same foreground behavior | user-delegated | intent |
| D-15 | The Verification note in this repo's CLAUDE.md | Reworded: the 2-minute reap and `run_in_background` advice applies to interactive sessions; a lane BUILD runs the sweep in the foreground | user-delegated | intent |
| D-16 | `-p` defaulting to `--bare` in a future release (the headless docs) | Out of scope: no flag pins the non-bare behavior today. Revisit when that default ships | user-delegated | intent |
| D-17 | The untracked `.claude/coderlm_state/` that stopped this ticket's first run as build-inflight | Not this PR: #913 adds it to .gitignore | codebase-derived | fact |
| D-18 | Why intake never raised `--bg` | `plan-interview` builds the mechanism options independently of the ticket's candidates: a root cause in a tool's own behavior gets an option that swaps that primitive, found on the tool's own surface and checked against the repo's history of it. In this PR, by the operator's instruction | user-answered | intent |

## Open Regions

No open regions — every decision in scope is ratified.

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | The terminal slugs, exit codes and the SKILL.md exit table | decided (D-1) |
| S-2 | The build prompt the BUILD session reads | decided (D-4) |
| S-3 | The REVIEW session's environment and its Workflow panel | decided (D-2) |
| S-4 | Config schema / run.* keys a consumer can set, and the refusal a fractional one now gets | decided (D-12) |
| S-5 | Release notes a consumer reads | decided (D-8) |
| S-6 | The run log | out-of-scope — no new line; the spawn is logged as before |
| S-7 | The run.sh header's env section | decided (D-3) |
| S-8 | This repo's CLAUDE.md Verification note | decided (D-15) |
| S-9 | The plan-interview protocol an engineer is interviewed by | decided (D-18) |

## Checks

No ticket-specific checks — the configured lanes cover this change.

## Design

Design: none — a scheduler env change that renders nothing.
