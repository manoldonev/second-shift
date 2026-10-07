# Intake receipt — #939 optional herdr workspace for every detached run

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | What the feature is for | Watching unattended `--detach` lanes, not steering inside sessions | user-answered | intent |
| D-2 | herdr's standing in the product | Optional and off by default; the operator trials it as his own cockpit | user-answered | intent |
| D-3 | Ticket shape | One tracer-bullet ticket covering every layer end to end: spawn identity, one watch call, one adapter | user-answered | intent |
| D-4 | How run.sh drives the adapter | A log-mapping watcher: one bounded call, then a pane-side watcher maps run.sh's own log lines to states. No event hooks in run.sh's control flow | user-answered | intent |
| D-5 | Lane admission | Admitted on the operator's word, stated in the body as a written departure from the consumer-evidence rule. The consumer causal link is unproven | user-answered | intent |
| D-6 | Workspace at run end | Always kept; the operator closes it | user-answered | intent |
| D-7 | VS Code tie | In this slice, as the opt-in `RUN_WATCH_EDITOR=code\|cursor` | user-answered | intent |
| D-8 | Switch shape | Per-machine env `RUN_WATCH_CMD`, following the scheduler's `RUN_*` knob convention (run.sh:64, docs/config-schema.md:22) | codebase-derived | fact |
| D-9 | Call site | The detached child, once the worktree is ready, with a once-per-launch guard. The parent hands over the log path as `RUN_DETACHED_LOG` (run.sh:244); the child's `say` writes to the log (run.sh:97); worktree_ready runs on every BUILD attempt (run.sh:895) | codebase-derived | fact |
| D-10 | Watchdog mechanism | Its own watchdog run from MAIN_ROOT, not `bounded()`, which does `cd "$WT"` and sets CHILD (run.sh:260-263); the bound value is parked under OR-1 | codebase-derived | fact |
| D-11 | Passing the log path to the pane | Fixed `pane run` text with inputs via `--env` on workspace/tab create. `pane run` types text plus Enter into the pane shell (herdr cli-reference.mdx:157,192,269), and the log path derives from committed config (run.sh:177,244) | codebase-derived | fact |
| D-12 | Sidebar state authority | Cosmetic and never read back: a `custom:` report-agent source is a soft overlay outside herdr's full-authority allowlist (herdrdev/herdr src/detect/mod.rs) | codebase-derived | fact |
| D-13 | Session identity | `--session-id` (v4 uuid) and a sanitized `-n` on every spawn. Measured on 2.1.292: listed in `claude agents --json` as busy within 2 s, transcript on disk within 1 s | codebase-derived | fact |
| D-14 | Spawn environment scrub | Unset `HERDR_*`, `RUN_WATCH*` and `RUN_DETACHED_LOG` in spawns and lane checks, names listed at run time; spawn scrubs nothing today (run.sh:880-884), lane() scrubs a fixed list (run.sh:270) | codebase-derived | fact |
| D-15 | Ownership of worktree and server | herdr never creates or removes worktrees and never starts or stops its server; run.sh owns the worktree (run.sh:816-822, :974-978) | codebase-derived | fact |
| D-16 | Re-entry | Match the workspace by label only (herdr WorkspaceInfo carries no cwd) and open a new tab per launch, since each launch writes a new log (run.sh:244) | codebase-derived | fact |
| D-17 | Watch bound value | 10 s default, parked under OR-1 | deferred | open |
| D-18 | Naming REVIEW sessions | Name both roles; whether agent-view reply can type into a named `-p` session is parked under OR-2 | deferred | open |
| D-19 | herdr-side behavior CI cannot see | report-agent persistence on a tail pane and headless blocked visibility, parked under OR-3 | deferred | open |
| D-20 | Live transcript pane in the tracer bullet | In scope, per the operator after reviewing what #939 left out (2026-10-07): a second pane renders the current top-level BUILD/REVIEW session's transcript one line per text block, tool call or failed result; subagent transcripts stay out | user-answered | intent |
| D-21 | Line anchors | Re-anchored on origin/main v16.1.1 (run.sh): say :97, terminal() :122, DETACH_LOG :244, detach wrapper :247-250, bounded() :260, SEAM_SCRUB/lane() :275-277, SPAWN_COMMON :287, worktree add :818-820, spawn envv :880, claude -p :884, round line :890, worktree_ready call :895, worktree remove :978 | codebase-derived | fact |
| D-22 | herdr CLI surface | Verified on installed herdr 0.9.3 and source a124eed: workspace/tab create and pane split take --cwd --label --env --no-focus; report-agent takes positional PANE_ID with --source --agent --state --message; WorkspaceInfo carries label (src/api/schema/workspaces.rs:62-65); tab create returns root_pane (response.rs:91-92); HERDR_PANE_ID exported into panes (src/integration/env.rs:8); server down fails in about 1 s with server_not_running | codebase-derived | fact |
| D-23 | Renderer implementation | bash + jq inside herdr-adapter.sh; repo scripts are bash and jq is already a lane dependency | codebase-derived | fact |
| D-24 | Pane layout per launch tab | Stacked: log pane on top (tab root), transcript pane split below with the larger share; both panes get full width for ~100-120 char lines | user-answered | intent |
| D-25 | PR conventions | feat(dev-pipeline): title, a Changelog trailer describing the opt-in watch adapter, no version or CHANGELOG edits (CLAUDE.md) | codebase-derived | fact |
| D-26 | Watch call process mechanics | Own process group (perl POSIX::setsid, already required by --detach, run.sh:242), whole-group kill on timeout with the timeout recorded by the watchdog (wait returns 143, not 124), CHILD set to the call while it runs so the INT/TERM traps reap it, stdout/stderr to a file in $STATE, never the detach log or a command substitution. Probes c02-c07, d05, d10, d16, s08-s14 in scratchpad/939-probes/lifecycle | codebase-derived | fact |
| D-27 | Environment boundary | Spawn scrub is new code in spawn() for both roles (run.sh:880,884; SEAM_SCRUB covers lane() only, :277), names listed with compgen -e per prefix; the detach re-exec stays unscrubbed (the selftest's fakes ride on it, run-selftest.sh:132); the watch call drops HERDR_PANE_ID/TAB_ID/WORKSPACE_ID but keeps HERDR_SOCKET_PATH/SESSION/CONFIG_PATH; the adapter passes explicit ids from its own calls | codebase-derived | fact |
| D-28 | How the panes learn a run ended without an exit line | Fix the root in this ticket: the --detach wrapper forwards TERM/INT/HUP to the run and always writes `detached run exited rc=<n>`, so a kill of the printed pid or the process group stops the run via its trap and leaves the line. Weighed: panes polling the run pid (recommended), this root fix (chosen), accept a stuck sidebar. SIGKILL stays out of scope | user-answered | intent |
| D-29 | Making the env-scrub selftest able to fail | The fake claude's env capture (run-selftest.sh:61) is widened to dump HERDR_*, RUN_WATCH* and RUN_DETACHED_LOG, and a leak case exports values before the run; without it an AC-12 guard passes vacuously | codebase-derived | fact |
| D-30 | Per-launch pane inputs | Root pane inputs ride on `tab create --env` (runs on every launch, re-entry included); the transcript pane's on `pane split --env`; `pane run` carries none (its request schema has no env) | codebase-derived | fact |
| D-31 | uuid case | Lowercase the generated uuid: macOS uuidgen emits uppercase while transcript filenames are lowercase | codebase-derived | fact |
| D-32 | Watcher line patterns | Terminal read from the bare `^terminal: <slug>` line (terminal() writes it twice, run.sh:123); progress from `round [0-9]+ of [0-9]+` (a looser pattern hits the review-retry line, :960); terminal is not the log's last line (ci/closing-comment lines follow); attempt ids are global across rounds (`2.2`, `1.1-retry1`, :896, :928) | codebase-derived | fact |
| D-33 | Duplicate scan | dup-scan --issue 939: no candidates (0 eligible or in-flight tickets) | codebase-derived | fact |
| D-34 | How HUP reaches a detached run's trap (D-28's third signal) | run.sh gains a HUP trap (reap, `hung up; claim left in place`, exit 129; the -h exit table now reads 129 / 130 / 143), and the detach launcher restores HUP and INT to default before the exec: nohup leaves HUP ignored and `&` leaves INT ignored, and bash cannot trap a signal ignored on entry. caffeinate now holds the machine awake with `-w <run pid>` beside the run instead of wrapping it, so the printed pid is the forwarding wrapper. Reason: without these, a HUP or INT to the pid or group never reaches a trap, and a TERM to the printed pid hits caffeinate | user-delegated | intent |
| D-35 | Adapter edge behaviors the ACs leave open | A RUN_WATCH_EDITOR other than code/cursor opens nothing, says so on stderr and does not fail the call; a tool call whose key argument is missing renders `[unparsed]` (the Data Contracts rule for a missing field); a session left for a newer one before its transcript appeared gets the same `no transcript for <session>` line as one at exit; a newly created workspace keeps its own first tab (a shell on the worktree) beside the launch tab. The session id is drawn from /dev/urandom in bash, lowercase by construction (D-31), not from uuidgen. Reason: each is the narrowest reading of the contract that drops nothing silently | user-delegated | intent |

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | The watch bound's value (10 s) | reversible-default-and-flag |
| OR-2 | Whether `claude agents` peek/reply can send input into a named `-p` REVIEW session | reversible-default-and-flag |
| OR-3 | herdr behavior only the operator's real herdr shows: report-agent persistence on a `tail` pane, blocked visibility with no client attached | reversible-default-and-flag |

- OR-1: the value is one constant, and AC-6 holds at any bound.
- OR-2: default is to name both roles. If a reply lands in a `-p` session, dropping `-n` on REVIEW is a one-line change.
- OR-3: the sidebar is cosmetic (D-12). AC-6 guarantees a misbehaving herdr changes no run outcome, and the operator's post-merge trial reads it.

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | The run log's `session:` lines | decided (D-13) |
| S-2 | The run log's `watch:` lines: off, skipped, failure | decided (D-9) |
| S-3 | The herdr workspace, its per-launch tab and the log pane | decided (D-16) |
| S-4 | Sidebar states: working, idle, blocked with slug or exit code | decided (D-12) |
| S-5 | The workspace after the run ends | decided (D-6) |
| S-6 | The VS Code / Cursor window on the worktree | decided (D-7) |
| S-7 | The `claude agents` listing of lane sessions | decided (D-13) |
| S-8 | `run.sh -h`, the config-schema row and the run/SKILL.md line | decided (D-8) |
| S-10 | The transcript pane: per-event lines, session separators, waiting and `[unparsed]` markers | decided (D-20) |
| S-11 | The run log's `detached:` line and what a kill of its pid or process group does | decided (D-28) |
| S-12 | The launch tab's layout: log pane on top, transcript pane below | decided (D-24) |
| S-13 | The watch call's own output file in the run's state dir | decided (D-26) |
| S-9 | Tracker, PR body, run block, decision record | out-of-scope — the integration writes nothing there (AC-14) |

## Checks

- `bash plugins/dev-pipeline/skills/run/run-selftest.sh`
- `bash plugins/dev-pipeline/skills/run/herdr-adapter-selftest.sh`

## Fan-out

Refuter: cross (opus/fable alternating)
Lenses: process-lifecycle-and-isolation opus 6/6 · environment-boundary fable 5/6 · external-contract-fidelity opus 3/6 · log-as-interface fable 5/6 · premortem fable 3/6
Tally: rows added 7 · snapshot claims overturned 0 · questions added 1
Checkouts: herdr (~/work/herdr) was cloned after the launch; lenses read herdr through its installed CLI and gh api, and the snapshot rows were verified against the clone

| ID | Angle | Claim | Tag | Disposition |
| --- | --- | --- | --- | --- |
| F-1 | process-lifecycle-and-isolation | bounded() cds into $WT and a TERM-ignoring call holds the run 20 s (run.sh:260-272) | already-had | snapshot D-10 already ruled out bounded() |
| F-2 | process-lifecycle-and-isolation | A grandchild survives bounded's pkill -P; setsid plus group kill leaves none (probes d05, d10) | new | became D-26 |
| F-3 | process-lifecycle-and-isolation | Traps reap only $CHILD; an own-variable watchdog leaks the call on TERM (probes s08, s09) | new | became D-26 |
| F-4 | process-lifecycle-and-isolation | A forking call's late write lands after the exit line unless its output goes to its own file (probes c06, d16) | new | became D-26 |
| F-5 | process-lifecycle-and-isolation | A command-substitution capture holds the run while any descendant keeps the pipe (probe c07) | new | became D-26 |
| F-6 | process-lifecycle-and-isolation | A process-group TERM kills the wrapper, so the log never gets its exit line (probe s12) | new | became D-28 |
| F-7 | environment-boundary | Spawns inherit the whole env; SEAM_SCRUB applies to lane() only (run.sh:277,880,884) | already-had | snapshot via D-14 |
| F-8 | environment-boundary | compgen -e lists exported names by prefix; env -u of an unset name is harmless | new | became D-27 |
| F-9 | environment-boundary | The detach re-exec must stay unscrubbed; RUN_DETACHED_LOG is a new export (run.sh:169,244,247-249) | new | became D-27 |
| F-10 | environment-boundary | The fake claude records a fixed four-name env set, so a leak is invisible (run-selftest.sh:61,156) | new | became D-29 |
| F-11 | environment-boundary | Launched from a herdr pane, HERDR_PANE_ID reaches the adapter and an omitted split target hits the operator's pane | new | became D-27 |
| F-12 | external-contract-fidelity | Per-launch inputs cannot ride on workspace create when the workspace is reused; tab create and pane split carry --env | new | became D-30 |
| F-13 | external-contract-fidelity | --session-id needs any valid UUID; macOS uuidgen emits uppercase while transcript names are lowercase | new | became D-31 |
| F-14 | external-contract-fidelity | terminal() writes each slug twice; the watch call needs HERDR_SOCKET_PATH kept for a non-default herdr session | new | became D-32 |
| F-15 | log-as-interface | Only the bare `^terminal: ` line matches once; terminal is not the log's last line (run.sh:123) | new | became D-32 |
| F-16 | log-as-interface | `round [0-9]+ of [0-9]+` is unambiguous; attempt ids are global across rounds (run.sh:896,928) | new | became D-32 |
| F-17 | log-as-interface | worktree_ready runs on every BUILD attempt, so the once-per-launch guard is load-bearing (run.sh:895) | already-had | snapshot D-9 / AC-4 |
| F-18 | log-as-interface | Transcripts live under a non-default config dir here; a ~/.claude-only glob misses them | already-had | snapshot D-13 / AC-2 glob |
| F-19 | log-as-interface | Which kill does the operator use? Only a TERM to the inner run yields an rc=143 line | new | became D-28 |
| F-20 | premortem | Killing the printed `detached:` pid kills the wrapper and orphans the run; --resume then builds beside the orphan (run.sh:247-250) | new | became D-28 |
| F-21 | premortem | An AC-12 selftest reading env-N.txt passes vacuously (run-selftest.sh:61) | new | became D-29 |
| F-22 | premortem | herdr 0.9.3's surface matches the ACs; server-down fails in about 1 s; pane run is parsed by the operator's login shell | already-had | snapshot D-22 |

### Snapshot

    | ID | Decision | Resolution |
    | --- | --- | --- |
    | D-1..D-20 | (the intake receipt's rows, unchanged) | as recorded in 939-ledger.md |
    | D-21 | Line anchors in the receipt | Re-anchored on origin/main at v16.1.1: say :97, terminal() :122, DETACH_LOG :244, bounded() :260, SEAM_SCRUB/lane() :275-277, SPAWN_COMMON :287, worktree add :818-820, spawn envv :880, claude -p :884, round line :890, worktree_ready call :895, worktree remove :978 |
    | D-22 | herdr CLI surface the adapter uses | Verified on installed 0.9.3 and source a124eed: workspace create / tab create / pane split all take --cwd --label --env --no-focus; report-agent takes positional PANE_ID + --source --agent --state --message; WorkspaceInfo has label; tab create returns root_pane; HERDR_PANE_ID exported into panes |
    | D-23 | Renderer implementation | bash + jq inside herdr-adapter.sh (repo scripts are bash; jq already a lane dependency) |
    | D-24 | Pane layout in a launch tab | OPEN — watch pane as the tab root, transcript pane split from it; direction (stacked vs side by side) is a what-the-operator-sees decision |
    | D-25 | PR conventions | feat(dev-pipeline): title, Changelog trailer describing the opt-in watch adapter, no version/CHANGELOG edits (CLAUDE.md) |
