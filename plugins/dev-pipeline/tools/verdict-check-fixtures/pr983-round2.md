verdict: approve
reviewed: c9ff84e44fc7ebb61ffb176982f895f39e55ac80

## Decision record rows

The record was added at `7100d01b`, which matches `Record baseline:` and is an ancestor of the head. Since then D-1 and D-2 were edited and D-8 was added. No tests were deleted or skipped, and no CI or check configuration was edited: the diff touches only `run/SKILL.md` and the record.

| Row | Score | Evidence |
| --- | --- | --- |
| D-1 watch primitive | departed (the operator) | At `7100d01b` the loop ended when the pid was gone (`kill -0`). At the head it ends when the process group is gone (`pgrep -g <pid>`). Who decided: the operator, in the intake session that launched this run (`3b35f140`, 2026-10-11T09:45:28Z). The answer was "Group check; re-arm or stop", and the option's text compared `pgrep -g` with `kill -0`. At 09:46:14Z the same session answered "Exit line OR group gone". `run/SKILL.md:33` implements it as one bare `run_in_background` loop with nothing after `done`, polling every 30 s, and `Monitor` is ruled out. I checked the premise against `run.sh:270-277`: `nohup` → `perl setsid` → exec `bash -c` keeps `$!`, so the printed pid leads the group and the run is a child in that group. A probe on this machine (a setsid leader with a child, leader SIGKILLed) gave `kill -0` → dead and `pgrep -g` → alive, and `pgrep -g` showed the group gone once the child exited. |
| D-2 when the watch ends | departed (the operator) | Same edit and same decider as D-1. `run/SKILL.md:43-48` has all three branches: exit line → step 4; no line and the group listed → re-arm ("a watch that ended is never the run's end"); no line and the group gone → report the run interrupted, citing any `terminal:` slug, and stop. The premise that the wrapper always writes the line on a forwarded TERM/INT/HUP holds at `run.sh:273-275`. |
| D-3 exit 144 out of scope | honored | The diff does no root-cause work and changes no hook or `run.sh`. |
| D-4 no other restatement | honored | Only `run/SKILL.md` and the record changed. The row's fact is incomplete: `README.md:114` also quotes the exit line. That line describes the log's outcome, not how to watch it, and is still accurate, so "none to change" holds. |
| D-5 run.sh and tests | honored | `run.sh` is unchanged, and the diff adds no selftest and no prose-presence guard. |
| D-6 verb and trailer | honored | The PR title is `fix(dev-pipeline): …`. `1be8b826` carries a `Changelog:` trailer with `Migration: none.`, and its text still fits the head. `pr-gates` passes. |
| D-7 duplicate scan | honored | An intake-time fact that puts no obligation on the diff. This is the record's figure; I did not re-run the scan. |
| D-8 the watch's `timeout` (added) | honored | Its provenance is `user-delegated`, and it names its source: the prior review's W1. `run/SKILL.md:28-30` sets `timeout` to the maximum the `Bash` tool's description states, and `:39-41` calls a stop at that bound the routine re-arm. This fixes W1 from the verdict on `1be8b826`. |

Ticket #979's acceptance item, "step 3 names the watch primitive and the re-arm rule for a watch that ends early", is met at `run/SKILL.md:25-48`.

## Findings

No blockers.

**W1 — Warning: the PR description describes the superseded check.** Its Summary still says the loop ends when "the pid printed by the detach line is gone (`kill -0` fails)", and the D-2 bullet keys on "the pid alive / gone". The head ships the process-group check, and `kill -0` is the check step 3 now says would call a live run dead. The description is what the merging human reads. Bring it in line with the head before merging. The body of commit `1be8b826` says the same, but a squash merge replaces it with the PR title.

**N1 — note: a second operator answer exists.** A parallel intake of #979 (`f6786a89`, 09:48:18Z, after the answer above) chose "Bash bg until-loop + re-arm", whose option text said "the printed pid is gone". That session's receipt is the record at `7100d01b`. The head follows the earlier answer from the launching session, which was the one question that put `kill -0` and the group check side by side, and the probe above shows the group check is right. I am not raising this as a blocker. It is written down so the departure is not read as unprompted.

**Suppressed (below 80).**
- `run/SKILL.md:29`: "the maximum the `Bash` tool's description states". A harness whose description gives a maximum only for foreground calls (this review session's says "max 600000 for a foreground command") would read 10 min. That costs re-arms, not correctness (confidence 60).
- `run/SKILL.md:28`: the quoted detach line is a prefix of what `run.sh:277` prints (confidence 50).
- Whether a rewriting PreToolUse hook rewrites a loop with `grep` in its condition is unprobed. D-3 says no such hook is installed today (confidence 40).

## review-lead (panel: pipeline default, scope-completeness only; no opt-ins taken)

The record has no `review panel` row and this repo has no `reviewers.default[]`. I took no opt-in of my own: the diff is skill prose and a record, with no auth/tenancy/query, web-component or co-located-spec surface. The lead pass covered performance, maintainability, complexity, test coverage and security. a11y and design-fidelity were not routed: no changed path matched `apps/web/**/*.{tsx,jsx}`, and the record has no design frames.

| Reviewer | Verdict | Findings | Confidence |
| --- | --- | --- | --- |
| Scope Completeness | Pass | 0 | — |
| Security | Lead pass — ✅ | 0 | — |
| Performance | Lead pass — ✅ | 0 | — |
| Complexity | Lead pass — ✅ | 0 | — |
| Maintainability | Lead pass — ✅ | 0 | — |
| Test Coverage | Lead pass — ✅ (prose-only diff; D-5) | 0 | — |

Data provenance: none. The diff reads no newly read persisted field.

CI: `pr-gates` passes. `selftests (macos, bash 3.2)` and `lint-and-selftests` were still pending at review time. The PR body's local sweep claim ("47 scored, 0 failed") was not verifiable by the prior review, so green rests on CI.

revised after reading the build's account: added W1. The description states the `kill -0` check that the head replaced. No row score changed.
