# Intake receipt — #979 the run skill names how to watch a detached run

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | The watch primitive step 3 names | A `Bash` call with `run_in_background` on a bare until-loop. It ends when the detach log has the `detached run exited rc=` line or the pid that the detach line printed is gone (`kill -0` fails). Nothing may follow `done`: a PreToolUse hook that rewrites the command can drop `run_in_background`, and the #973 watcher's trailing `; grep … \| tail -3` made it that kind of command. The loop is local and polls every 30 s. Weighed: a `Monitor` re-armed on each expiry (capped at 30 min by the tool, so 4+ wake-ups for a two-hour build, and an expiry is a routine event to tell apart from a dead run); having `run.sh`'s detach line print the exact command (testable, but it changes `run.sh` for a skill-text ticket); and replacing `--detach` with run.sh itself under `nohup` + `run_in_background` (no watcher, but the run dies with the session, which `--detach` exists to prevent) | user-answered | intent |
| D-2 | What the session does when the watch ends | It reads the log's last lines. The exit line is there → step 4, reading the terminal as now. No exit line and the pid is alive → the watcher died, not the run, so it re-arms the same loop and never treats the dead watcher as the run's end. No exit line and the pid is gone → it reports the run as interrupted with no terminal line and stops. The `--detach` wrapper always writes the line, even on a forwarded TERM/INT/HUP (`run.sh:265-277`), so a missing line with a dead pid means an uncatchable kill (SIGKILL) and a human's read | user-answered | intent |
| D-3 | Root-causing the watcher's exit 144 | Out of scope. D-2 catches a dead watcher whatever killed it, and D-1 does not depend on the cause. Unverified: why the auto-backgrounded #973 watcher exited 144 at about 7.5 min. Verified 2026-10-11 by the operator's tooling notes: the ctx-wire PreToolUse hook dropped `run_in_background` on rewritten commands, which is why the watcher ran in the foreground and was moved to the background at 120 s. That hook is not installed in the operator's user settings today | user-answered | intent |
| D-4 | Other places that restate the watch step | None to change. `detached run exited` appears in prose only at `run/SKILL.md:28` and in a historical plan (`docs/plans/second-shift-939-decisions.md:34`), which stays as written | codebase-derived | fact |
| D-5 | `run.sh` and tests | `run.sh` is unchanged (D-1), so CLAUDE.md's "a behavior change to `run.sh` lands with a `run-selftest.sh` case" does not apply. A test that checks the skill for the new wording is barred by the writing-tests rules, so no new selftest | codebase-derived | fact |
| D-6 | Commit verb and trailer | `fix(dev-pipeline):` on the PR title, because the skill left the watch to the session, which picked a primitive that died (CLAUDE.md, "Commit verbs decide the version bump"). Add a `Changelog:` trailer saying `/dev-pipeline:run` names its watch and re-arms one that ends without the run's exit line, `Migration: none` | codebase-derived | fact |
| D-7 | Duplicate scan | `dup-scan.sh --issue 979` returned 0: no candidates at or above threshold | codebase-derived | fact |

## Open Regions

No open regions — every decision in scope is ratified.

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | `run/SKILL.md` step 3 text the driving session reads | decided (D-1) |
| S-2 | The watch's single completion notification in the operator's session | decided (D-1) |
| S-3 | A watch that ends while the run is still alive | decided (D-2) |
| S-4 | A run that is gone with no exit line in its log | decided (D-2) |
| S-5 | The `RUN_WATCH_CMD` / herdr `watch:` line | out-of-scope — unchanged; step 3 already says it is never a signal to act on |
| S-6 | The release-note line | decided (D-6) |

## Checks

No ticket-specific checks — the configured lanes cover this change.

## Fan-out

Fan-out: skipped — by the operator at the pre-flight notice: no reason given
