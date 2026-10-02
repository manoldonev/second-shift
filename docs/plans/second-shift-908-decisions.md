# Intake receipt — #908

## Decision Ledger

| ID  | Decision | Resolution | Provenance | Kind |
| --- | -------- | ---------- | ---------- | ---- |
| D-1 | How run.sh stops a headless BUILD ending its run on a backgrounded long check | Prevent it at spawn: the BUILD session is launched with CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1, BASH_DEFAULT_TIMEOUT_MS and BASH_MAX_TIMEOUT_MS, so checks run in the foreground. No session re-entry (--resume), no fresh-retry safety net; build-inflight stays as it is for any other cause | user-answered | intent |
| D-2 | Which spawned sessions get that env | BUILD only. REVIEW is untouched, because review-lead's Workflow panel runs as a background task | user-answered | intent |
| D-3 | The Bash timeout values | Both BASH_DEFAULT_TIMEOUT_MS and BASH_MAX_TIMEOUT_MS = BUILD_TO × 1000 (RUN_BUILD_TIMEOUT / run.buildTimeoutSeconds, default 7200 s); the scheduler's wall-clock bound stays the only cap, no new config key | user-answered | intent |
| D-4 | A headless line in the build prompt | None. The env enforces the behavior; the prompt is unchanged | user-answered | intent |
| D-5 | Whether the env works under claude -p | Measured 2026-10-02 on Claude Code 2.1.287: with the three variables set, a claude -p session ran `sleep 150` in the foreground and returned its output after 155 s (subtype success). Which of the three is load-bearing was not isolated, so all three are set | codebase-derived | fact |
| D-6 | The fresh-process rule | Kept: every session is still a fresh process (run.sh:42) and the F1 assertion (run-selftest.sh:144, no --resume/--continue) still holds | codebase-derived | fact |
| D-7 | The guard | A run-selftest.sh case asserting that the BUILD spawn's environment carries all three variables at BUILD_TO × 1000 and the REVIEW spawn's carries none. It fails without the fix (CLAUDE.md: a run.sh behavior change lands with a run-selftest.sh case) | codebase-derived | fact |
| D-8 | Commit verb and changelog | PR title `fix(dev-pipeline): …` (patch), and a consumer-visible `Changelog:` trailer: the build session now runs long checks in the foreground instead of ending its run on a backgrounded one. Migration: none (CLAUDE.md commit-verb and trailer rules) | codebase-derived | fact |
| D-9 | Build model | opus (operator standing rule for this repo) | user-answered | intent |
| D-10 | Lane admission | Not admitted: the ticket body records only this repo's lane, and CLAUDE.md's admission rule keeps it out of the lane until a consumer run shows build-inflight from the same cause. No queue label is applied | codebase-derived | fact |

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | Whether CLAUDE_CODE_DISABLE_BACKGROUND_TASKS changes anything else BUILD uses (Agent subagents, e.g. the design-frames plan check) | reversible-default-and-flag |

OR-1 default: set the variable anyway. The probe exercised Bash only. If a BUILD's Agent dispatch fails under it, flag it in the PR and drop that one variable, keeping the two timeouts. Reverting is a one-line env edit in `spawn()`.

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | The terminal slugs, exit codes and the SKILL.md exit table | decided (D-1) |
| S-2 | The build prompt the BUILD session reads | decided (D-4) |
| S-3 | The REVIEW session's environment and its Workflow panel | decided (D-2) |
| S-4 | Config schema / run.* keys a consumer can set | decided (D-3) |
| S-5 | Release notes a consumer reads | decided (D-8) |
| S-6 | The run log | out-of-scope — no new line; the spawn is logged as before |

## Checks

No ticket-specific checks — the configured lanes cover this change.

## Design

Design: none — a scheduler env change that renders nothing.
