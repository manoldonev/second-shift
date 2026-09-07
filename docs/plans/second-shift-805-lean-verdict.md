# lean review verdict — #805

verdict=needs-work
run_id: review-805-1
session_id: c72d97a4-8041-4baa-9d8b-e9b54adb3207
rounds: 1
pr: #810
reviewed_head: 2ea113d5bd9d33050a4441751009224c5bc65afb
reviewed_patch_id: 270b43f222f5c50980af8a96be226886b36cb843
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
panel: review-toolkit:scope-completeness-reviewer,review-toolkit:pipeline-reviewer,review-toolkit:unit-test-mutation-reviewer
model: opus
capabilities: pr-marker

Round 1, full branch range `3912f458..2ea113d5` (root round — nothing to inherit).

The transport swap itself is sound and unusually well evidenced: the state routing, the `--all`
poll, the fail-closed tolerance, the stuck fallback with its non-vacuity twin, and the mid-flight
exit-7 abort are all driven by real cases against an argv-discriminated fake, and the identity
boundary is genuinely untouched. Two blockers stop the round, and both are measured rather than
argued.

## Blockers

**B-1 — AC-11: the ratification bar is not met and the operator's pre-authorized fallback was not
taken.** Measured at the reviewed head with `git diff --numstat 3912f458..HEAD -- . ':!docs/plans/'`:
`+781 / −181`, net **+600**. `#717`'s bar for a `harness-internal` ticket is a negative net diff.
AC-11 states the conditional obligation explicitly: "If the poll loop and its fallbacks do not
clear the bar, falsifier 5 is taken instead". The operator's ratification comment states the same
thing and pre-authorizes the cut: "Net-negative is the bar. If the poll loop does not clear it,
land only the comment correction, id-at-dispatch and `claude stop` for exit 7, and record the
negative." Neither arm holds — the bar is not cleared and the reduced landing was not taken.

The PR body is candid about this and argues the fallback is itself net-positive, so taking it
would be dishonest accounting rather than compliance. That argument may well be right, and it is
a finding worth having. But it is an argument the operator was owed **before** the full scope was
built, not after: taking the recorded narrowing is not a unilateral scope cut, it is the
disposition the ratification already carried. As it stands the round certifies a diff whose own
author says the ticket's central bar is unmet. The remedy is the operator's call, not BUILD's and
not mine — amend the bar on the ticket, or take the cut.

**B-2 — AC-7: on every terminal path out of `poll_session`, the transcript never gains the final
message and no spawn-end line is written — and `build-blocked`'s own remedy points at that empty
file.** `spawn()` calls `transcript_close` and `say "spawn $role settled"` only *after*
`poll_session` returns; the `blocked`, `spawn-unreadable` and mid-flight `staleness-expired` arms
call `terminal`, which exits. Under `--bg` the payload never reaches this process, so on those
paths the per-role transcript stays **0 bytes** — while `orchestrate-lean.sh:912` tells the
operator "Read what it asked in the payload transcript".

Measured, in an isolated worktree at the reviewed head, by dumping every spawn transcript at the
point case `bg2` (`build-blocked`) evaluates: exactly one 0-byte transcript in the whole suite run
— `7-lean-spawn-<launch>-1-build.log` — against 71 bytes carrying
`[orchestrate-lean] session <sid> left no readable final message.` for every spawn that settled
normally. These are the paths the ticket exists to make legible; they are the ones that produce
nothing to read.

**B-3 — `build-no-pr`'s remedy renders `claude attach ` with no id.** `spawn()` clears
`SPAWN_ID=""` at `orchestrate-lean.sh:1002` before returning, and the `build-no-pr` terminal at
`:1201` interpolates `$SPAWN_ID`. It is always empty there. `SPAWN_SID` (the full session id) is
still live at that point; `SPAWN_ID` is not.

Measured: adding `grep -qE "claude attach [A-Za-z0-9-]+' reaches"` to case `h4` fails the suite
(control run at the same head, clean env: all green; patched run: exactly 1 failure, `h4`). The
emitted text is `... 'claude attach ' reaches the session itself while the supervisor still holds
it.` This is D-3's interviewed decision — "the `build-no-pr` remedy names that file and
`claude attach <id>`" — implemented but inert, and unguarded: `h4` asserts the slug and two prose
fragments, never the id.

B-2 and B-3 share one root cause: `SPAWN_ID` / `SPAWN_SID` / `SPAWN_LOG` have three different
lifetimes and the two operator-facing remedies each read the wrong one at the wrong moment.

## Warnings

- **`terminal()`'s `spawn_cleanup` is the only stop on the `spawn-unreadable` and unmodelled-state
  paths, and nothing asserts it.** Those two arms do not call `stop_session` themselves, unlike
  `blocked` and `staleness-expired`. Cases `bg5/*` and `bg5b` assert rc, slug, `gate_count` and
  that `sess1` appears in the output — the terminal message names the id itself, so that grep
  passes regardless. Deleting `spawn_cleanup` from `terminal()` leaves a live session running
  after a fail-closed refusal and every case still passes.
- **`$lower-session-failed` is never driven through the REVIEW role.** Cases `j1` and `j1a` drive
  BUILD only, so `$lower` is the literal `build` everywhere this line is reached; a mutant
  hardcoding `build-session-failed` survives. AC-9 collapses the two register rows precisely on
  the claim that "the log keeps both slugs", so this is the site backing that claim. `blocked`
  gets this right — `bg2a` drives REVIEW.
- **`probe_spawn`'s new listing validation has no case.** The preflight cases exercise only the
  binary-does-not-resolve branch; every other case's fake answers `[]` at preflight, which
  vacuously satisfies `map(has("state")) or all`. Reverting `probe_spawn` to its pre-diff one-liner
  passes the whole suite.
- **The six forwarded telemetry variables are asserted for none of them.** `d1`/`d2` cover
  `LEAN_ATTEND_MODE` and `LEAN_RUN_MODEL`, which is AC-10's letter; D-27's OTel forwarding is new
  production behavior with no guard. The telemetry cases run under `--dry-run` and never reach
  `spawn_settings`. Deleting the forwarding loop passes every test.
- **AC-6's INT/TERM trap has no case at all.** The trap is present and correct; nothing exercises
  it. It is drivable — signal a run mid-poll and assert the stops file.

## Suggestions

- `poll_session` sleeps before its first read, so a session that settles in two seconds still costs
  a full `POLL_SECS`. Reading first and sleeping after would remove ~15s of expected latency per
  spawn at the shipped default.
- `OTEL_EXPORTER_OTLP_HEADERS` typically carries an auth credential, and `--settings` puts it on
  the child's **argv**, where any local process can read it from `ps`. Under `-p` it was an
  inherited environment variable. The flag also accepts a file path; a `0600` temp file would keep
  the D-27 behavior without widening the exposure. Low severity on a single-operator machine, and
  noted rather than pressed.
- The malformed-id disjunct of the dispatch guard (`*[!A-Za-z0-9-]*`) is untested; only the empty
  branch is driven, via `NOID`.

## Verification performed by this review

- `orchestrate-lean-selftest.sh` at the reviewed head, isolated worktree, clean env: **all green**
  (the local `ov1`/`ov2` reds under an inherited `LEAN_ATTEND_MODE` are the known env leak, not
  this branch).
- Control/mutant pair for B-3 as described above.
- Transcript dump probe for B-2 as described above.
- `bash scripts/check-gate-buckets.sh` — 318 sites, 166 rows, green.
- `bash tools/prose-blockers.sh check` — 29 stop-tier constructs, zero undispositioned.
- `shellcheck -e SC1091,SC2015,SC2181` over every changed script — clean.
- CI at this head: `lint-and-selftests` **pass** (4m50s), `mutation-sweep-pr` **pass**. `pr-gates`
  is red, which is the lean chain's pre-approve state and not a finding. `selftests (macos, bash
  3.2)` was still running; nothing in this record rests on it.

## AC scorecard

| AC-n | score | evidence |
| --- | --- | --- |
| AC-1 | satisfied | `spawn()` dispatches `--bg`, parses the id from the `backgrounded` line and fail-closes on an unreadable one (case `bg6`); `--disallowedTools AskUserQuestion`, `--name lean-<issue>-<role>-r<round>` and the `--settings` env block are all present and asserted (`bg8`, `d1`, `d2`). Every named deletion is gone from the file: no `SPAWN_BG_WAIT_CEILING_MS`, no `CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS`, no `PIPESTATUS`, no spawn-side `env -u RUN_ID -u LEAN_RUN_MODEL`, no rationale block. |
| AC-2 | satisfied | `poll_session` polls `agents --json --all` on the `LEAN_SPAWN_POLL_SECS` cadence keyed on the dispatched id, and routes all five states. `bg1` rides out `working`; `bg1a` asserts `--all` on every listing call; `j1`/`j1a` route `failed`/`stopped`; `bg2`/`bg2a` route `blocked` to a stop plus a role-composed terminal. |
| AC-3 | satisfied | `job_idle` reads `tempo` plus both `inFlight` counters and never `detail`; three idle ticks stop the session and set `stuck`, which then proceeds as `done`. The non-vacuity twin is present and passing — a session with a task in flight rides out four ticks untouched. The unreadable-record arm falls to the wall-clock `IDLE_CEILING_MS` bound, also covered. |
| AC-4 | satisfied | Four distinct unreadable shapes plus the unmodelled-state arm all reach `terminal spawn-unreadable 1` naming the id after three polls, with `gate_count` zero. The counter resets only inside the recognized arms, and the "two bad reads then a state" case proves the reset. |
| AC-5 | satisfied | `staleness_rc` is re-run each tick; rc=7 stops the session then takes `terminal staleness-expired 7`, and the revised message owns the partial-operation risk. Case `bg7` asserts the stop landed in the stops file mid-flight. The pre-loop staleness call is unchanged. |
| AC-6 | satisfied | `trap 'spawn_cleanup; exit 130' INT` and `trap 'spawn_cleanup; exit 143' TERM` are installed above `terminal`, and `spawn_cleanup` stops the in-flight id and clears it. The placement rationale is correct — `terminal` is reachable from arg parsing. Scored satisfied on the code; no case exercises it, which is carried above as a warning rather than against this criterion. |
| AC-7 | unsatisfied | The transcript is created at spawn and gains the final message on the `done` and `stuck` paths, and the spawn-time control line carries the id and `claude attach <id>` (`bg8`). But the spawn-end half does not hold on the paths that terminal out of `poll_session`: `transcript_close` and the spawn-end line are both after the `poll_session` call, and `blocked`, `spawn-unreadable` and mid-flight `staleness-expired` exit before reaching them. Measured at this head — the `bg2` blocked case leaves a 0-byte transcript, the only one in the suite run, while `orchestrate-lean.sh:912` directs the operator to read it. |
| AC-8 | satisfied | The `spawn` row carries `id=<short id>` and the `spawn-end` row carries `state=<...>` in place of `rc=`; asserted per spawn, and starts and ends alternate. Nothing parses the field, and `lane-latency.sh` reads timestamps only. |
| AC-9 | satisfied | `build-session-failed` and `review-session-failed` are one row anchored on `terminal "$lower-session-failed" 1`; `blocked` and `spawn-unreadable` have rows of their own; `staleness-expired`'s anchor still resolves against the edited message. `bash scripts/check-gate-buckets.sh` green at this head — 318 sites over 5 files, 166 rows. |
| AC-10 | satisfied | The `claude` fake is argv-discriminated across `--bg`, `agents --json --all` and `stop`, served from a per-case state stream, and never sleeps. Every case AC-10 enumerates is present and passing, the `--settings` handoff included. `tools/mutation-catalog.tsv` gains `lean-orchestrate-stuck-idle-read`; both liveness legs answer the new subcommands and pin the poll interval to zero. The coverage gaps found this round all sit outside AC-10's enumerated list and are carried as warnings. |
| AC-11 | unsatisfied | Measured at this head with the command the AC names: `+781 / −181`, net **+600** excluding `docs/plans/`. The bar is a negative net diff, and falsifier 5's reduced landing was not taken either. See B-1 above — the remedy is an operator decision on the ticket, not a code change I can name. |
| AC-12 | satisfied | Every prose site D-17 lists is rewritten: the inherit-and-scrub paragraph, the exit-status block, the three-mechanisms paragraph, the exit-7 bound and the spawn header in `orchestrate-lean.sh`; the `-p` passages in all three lean `SKILL.md` files; both falsified `lean-gate.sh` header claims; and `operator-override.sh`'s `headless` contract gains the `claude attach` sentence. Remaining `claude -p` mentions are deliberate historical references to what the swap replaced. `bash tools/prose-blockers.sh check` green, 29 stop-tier constructs, zero undispositioned. |

## Panel

`review-toolkit:scope-completeness-reviewer` (request-changes, 1 blocker — independently reached
B-1 at confidence 92, and confirms every other scope item in the issue body and the ratification
comment is in-diff), `review-toolkit:pipeline-reviewer` (approve, domain out of scope for this
diff), `review-toolkit:unit-test-mutation-reviewer` (approve-with-nits, 4 major plus 1 minor —
all four majors verified against the suite and carried above as warnings). No reviewer went dark.
`review-toolkit:security-reviewer` was not selected: no auth, tenancy, session or query-construction
surface in the diff and no repo security-context file, so the security dimension was covered by the
lead pass, which produced the argv-exposure suggestion above. The performance, complexity,
maintainability and test-coverage dimensions are lead-pass dimensions by design and were reviewed
in-session; B-2, B-3 and the first two warnings are lead-pass findings.

Design fidelity: the spec declares no `## Design` section, so the dimension is not applicable and
no fidelity reviewer was routed.
