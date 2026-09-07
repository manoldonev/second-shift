# second-shift #805 — `claude --bg` replaces the `claude -p` spawn in `orchestrate-lean.sh`

`claude -p` is the wrong spawn primitive for this lane. It exits 0 whenever the model ends its
turn, so a payload that exhausted its context, paused on a question, or signed off mid-dispatch is
byte-identical to one that finished — and `orchestrate-lean.sh` carries three separate mechanisms
compensating for that. `--bg` returns a session id at dispatch, reports a real state
(`working` / `blocked` / `done` / `failed` / `stopped`), and offers `claude stop` as a live
control channel.

**#549 declined this branch on a mis-scoped probe** — it tested an asynchronous primitive as if it
were a synchronous spawn, found "no exit status on `--bg`", and never read the signal `--bg`
actually carries.

The identity boundary is untouched: a bg session's own `CLAUDE_CODE_SESSION_ID` equals the
`sessionId` the listing reports, so `cmd_verdict`'s build-vs-review refusal and the audit ledger
need no change. This is a transport swap, not a boundary change.

Binding input: the pre-flight receipt `.claude/pipeline-state/805-ledger.md` (gitignored, canary
machine), whose D-1 … D-25 are carried below, and the operator's ratification comment
(https://github.com/manoldonev/second-shift/issues/805#issuecomment-5562750078), which resolves
OR-1 … OR-4 and states the net-negative bar.

This is a `harness-internal` ticket (#717): the ratification bar is a negative net diff, and
AC-11 is where that is graded.

## Acceptance criteria

- AC-1: `spawn()` in `plugins/dev-pipeline/skills/run-lean/orchestrate-lean.sh` dispatches
  `"$SPAWN_BIN" --bg`, reads the session id out of its output, and returns a STATE rather than a
  child exit code. Deleted with it: the `-p` invocation, the `2>&1 | tee` pipeline and its
  `${PIPESTATUS[0]}` read, the `env -u RUN_ID -u LEAN_RUN_MODEL` scrub, and
  `SPAWN_BG_WAIT_CEILING_MS` / `LEAN_SPAWN_BG_WAIT_CEILING_MS` /
  `CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS` together with the rationale block that motivates them.
  The child's environment arrives instead through `--settings` carrying an `env` object with
  `LEAN_ATTEND_MODE=headless` and `LEAN_RUN_MODEL=<model>` — nothing from the launcher's shell
  reaches a `--bg` session (D-9) — plus the telemetry variables `probe_telemetry` already reads,
  forwarded only when the launcher carries them (D-27). The spawn also passes `--disallowedTools AskUserQuestion` (D-6)
  and `--name lean-<issue>-<role>-r<round>` (D-4). A dispatch whose output carries no readable
  session id is fail-closed, not scored as a spawn.
- AC-2: after dispatch, `spawn()` polls `claude agents --json --all` on a fixed cadence, keyed on
  the exact `sessionId` returned, and routes the documented state enum: `done` proceeds, and `failed`,
  `stopped` and `blocked` all reach the existing `build-session-failed` /
  `review-session-failed` terminal, which names the state and stops the session — headless,
  nobody can answer a blocked one (D-5, D-6, D-13). `blocked` gets no slug of its own: the
  narrowing below removed it, and the state is carried in the message and the launch ledger. The listing flag is `--all`: without it a
  finished session drops out and the poll would read its own success as a disappearance (D-10).
  The cadence is an env seam defaulting to 30 seconds, so the suite drives the loop without
  sleeping (D-14).
- AC-3: the stuck fallback (D-8), **narrowed to its documented arm**. A session reporting
  `working` past a bounded WHOLE-SESSION ceiling (env seam, default 2 hours) → `claude stop <id>`,
  a launch-ledger `state=stuck`, and the run proceeds exactly as for `done`, because the gate is
  the completion oracle either way. The harness's private `~/.claude/jobs/<id>/state.json` is
  **not read**: it named the same shape in ninety seconds rather than at a wall-clock bound, and
  it was the first thing the narrowing below gave up.

  **AMENDED at review round 4, and this is a DEPARTURE from the ratified parameter — read it
  before ratifying.** The `Ratified:` comment names "a 30-minute SILENCE ceiling", and this AC
  declared one until now. It cannot be built on this transport. A silence ceiling needs a signal
  that separates a payload with nothing to do from one three minutes into a sweep, and the only
  thing that carried it was the job record the same narrowing removed — `working` is what a
  healthy session reports for its entire life. So the bound that ships measures TOTAL elapsed
  session time, which is the nearest implementable thing, and its value is measured rather than
  intuited: over this lane's own launch ledgers, 55 BUILD spawns ran a median of 12.6 minutes and
  a maximum of 100.5, with 11 of 55 past thirty minutes. A 30-minute bound would therefore have
  stopped one healthy BUILD in five mid-work and ledgered each `stuck` — the print-mode wait
  ceiling rebuilt by accident, which is the regression this transport swap exists to remove. Two
  hours clears the observed maximum with room. Both halves of the departure — the number and the
  semantics — are the operator's to accept or refuse; the code carries the same reasoning at
  `orchestrate-lean.sh:833` and the PR body names it as a departure rather than as the ratified
  thing.
- AC-4: an unreadable listing is fail-closed (D-18). Three consecutive polls in which
  `claude agents --json --all` fails to run, fails to parse, or does not contain the dispatched id
  end the run with `terminal spawn-unreadable 1` naming that id. A state that could not be read is
  never scored as `done`, and the tolerance is three rather than one because a supervisor killed
  under a live session leaves the session running and the listing recoverable.
- AC-5: exit 7 becomes a live abort (D-2, ticket OR-4). The poll loop re-runs `staleness_rc` each
  tick; on 7 it `claude stop`s the child and then takes `terminal staleness-expired 7`, whose
  message is revised to say the session was stopped mid-flight and the lane worktree may hold a
  partial operation — a stop ends the payload's running tool process, so a git command in progress
  can leave an `index.lock`. The pre-loop staleness call is unchanged.
- AC-6: an in-flight child does not outlive its scheduler (D-1). A trap on INT and TERM
  `claude stop`s the dispatched id before exiting. One lane, one supervisor: an orphan would go on
  writing records under a `RUN_ID` nobody is supervising.
- AC-7: the per-role transcript and the control stream (D-3, D-4). The transcript file is still
  created at spawn — `retro-corpus.sh` classifies a run `orchestrated` on its presence — and at
  spawn-end gains the session's last assistant text, read from
  `~/.claude/projects/<cwd-slug>/<sid>.jsonl`, which is the same content `-p` used to print. It
  stays advisory: a transcript that cannot be opened is a lost convenience, never a stopped run.
  The control stream carries one line at spawn naming the id and `claude attach <id>`, one line per
  state transition the poll observes, and one at spawn-end. No heartbeat, no audit-ledger tail.
  Sessions are not `claude rm`'d.
- AC-8: the launch ledger records a state, not a return code (D-12). The `spawn` row gains
  `id=<short id>`; the `spawn-end` row's `rc=<n>` becomes `state=<done|failed|stopped|blocked|stuck>`.
  `tools/lane-latency.sh` reads timestamps only and is unaffected.
- AC-9: `scripts/gate-buckets.tsv` is reconciled (D-13). `build-session-failed` and
  `review-session-failed` become ONE row, because the two are now one source site whose slug is
  composed from the role — the register anchors on source text, and the log keeps both slugs.
  `staleness-expired` re-anchors onto its edited message, and `spawn-unreadable` gets a row of its
  own. `blocked` gets none — it routes through the collapsed row above. `bash scripts/check-gate-buckets.sh` stays green.
- AC-10: the suite drives the new transport (D-14). `orchestrate-lean-selftest.sh`'s `claude` fake
  is discriminated on argv the way its `gh` fake already is: `--bg` prints `backgrounded · <id>`
  and records the prompt and the flags, `agents --json --all` is served from a case-written state
  file the case advances per call, and `stop` is recorded. The fake never sleeps. New cases cover
  the poll reaching `done`, `failed`/`stopped`, `blocked` through the collapsed terminal, the
  silence ceiling with its non-vacuity twin, an unreadable listing, the mid-flight exit 7, the
  `--settings` env handoff, and the transcript surviving a terminal reached from inside the poll. Any
  `tools/mutation-catalog.tsv` row whose sed anchor addresses edited code is re-anchored, and the
  `lean-reentry` leg of `scenario-liveness-selftest.sh` composes against the new transport.
- AC-11: **falsifier 5 fired, the operator's pre-authorized narrowing is taken, and the negative
  is recorded rather than the bar claimed.** #717's bar for a `harness-internal` ticket is a
  negative net diff and this ticket does not reach it. What the narrowing removed is gone from the
  branch: D-8's undocumented job-record read, the `build-blocked` / `review-blocked` slug pair and
  their register row, `probe_spawn`'s listing validation, and every case and catalog row that
  addressed them. What it keeps is what the ratification comment itself names as the reduced
  landing — the prose corrections, the session id at dispatch, and `claude stop` for exit 7 — plus
  the poll those two require in order to exist at all.

  The recorded negative, measured at this head, is that **no cut depth reaches the bar**, because
  the cost is the poll loop and the reduced landing keeps the poll loop by construction. Counting
  executable lines only — comments and blanks excluded on both sides, so the repo's comment
  density is not what is being measured — the branch adds **389** and deletes **92**. Stripping
  every comment the branch adds would not close that gap. The intake deletion table was the error:
  it projected that "a large fraction" of a 1,044-line file was `-p` compensation, and the realized
  deletions are 83 lines from that file and 178 across the whole branch.

  Whether that buys ratification is the operator's call and is not claimed here. The PR body
  states both figures and the commands that reproduce them.
- AC-12: the prose that describes `-p` follows the code (D-17). In `orchestrate-lean.sh`: the
  identity-under-orchestration paragraph's inherit-and-scrub claim, the "why a spawn's exit status
  is not a completion signal" block, the exit-0 interpretation in the three-mechanisms-died
  paragraph, the "there is no channel into a live `claude -p`" statement on the exit-7 bound, and
  the stream-split header on `spawn`. In `run-lean/SKILL.md`, `review-lean/SKILL.md` and
  `build-lean/SKILL.md`, the passages naming `-p` as the spawn primitive or turn end as process
  exit. Two `lean-gate.sh` header claims this PR falsifies are corrected in place: the build-exit
  contract's "exits 0 … is `claude -p` ending a turn", and `require_ticket_live`'s "the scheduler
  structurally cannot, because there is no channel into a running `claude -p`".
  `operator-override.sh`'s `headless` contract gains one sentence: `claude attach` is a
  keyboard channel into a headless payload, so `headless` means "not attended through the gate",
  not "unreachable". `bash tools/prose-blockers.sh check` stays green, with triage rows added
  last.

## The narrowing taken

The ratification comment's conditional — *"Net-negative is the bar. If the poll loop does not
clear it, land only the comment correction, id-at-dispatch and `claude stop` for exit 7, and
record the negative"* — is a pre-authorized narrowing, not an option to decline. Round 1 measured
the bar unmet and landed the full scope anyway, arguing the exception; that was the wrong shape,
and the round was rejected for it. Round 2 takes the disposition.

**Removed by the narrowing:** D-8's primary arm (`job_idle`, the `~/.claude/jobs/<id>/state.json`
read, and its two cases), the `build-blocked` / `review-blocked` terminals and the
`gate-buckets.tsv` row that classified them, `probe_spawn`'s session-listing validation, and the
`lean-orchestrate-stuck-idle-read` mutation-catalog row whose anchor addressed the deleted read.

**Kept, because the reduced landing names them or cannot exist without them:** the `--bg` dispatch
and the id it yields, `claude stop` on exit 7 and on an interrupted scheduler, the poll that turns
a dispatched id into a state, the `--settings` env handoff (nothing else reaches the child), the
transcript, and AC-12's prose corrections.

## Out of scope

`claude logs` (D-16 — live-only TUI chrome; the ticket's "liveness is `claude logs` plus `state`"
claim is corrected in the PR body, not built on). Session worktree relocation, which is the opt-in
`-w` flag and not something a shell-dispatched `--bg` does (D-11). The concurrency posture (D-7):
the poll keys on an exact id and the single-lane assumption is about worktrees and the gate, not
transport. The REVIEW spawn's coldness and per-round freshness, which `--bg` does not touch. The
tracker follow-ups on #617 and #549 (D-19): the PR body lists them, the operator performs them.
Resuming a BUILD session, struck at intake. Any change to `cmd_verdict`, `lean-evidence.sh` or the
audit hook — the identity boundary is measured unchanged (D-15).

## Verification

```bash
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
SKIP_STRESS=1 bash tools/run-selftests.sh --full --exclude tools/install-topology-selftest.sh
bash scripts/check-gate-buckets.sh
bash tools/prose-blockers.sh check
```
## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | In-flight child when the scheduler exits abnormally (INT, TERM, error) | Trap and `claude stop <id>`. Preserves one-lane-one-supervisor; an orphan would keep writing records under a RUN_ID nobody supervises. `stop` also ends the payload's running tool process (H: a foreground bash loop froze at the stop, no orphan). The ticket's "survives terminal close" gain is deliberately declined for payloads. | user-answered |
| D-2 | Exit 7 gains a live abort (ticket OR-4) | In scope. The poll loop re-runs `staleness_rc` each tick; on 7 it `claude stop`s the child, then `terminal staleness-expired 7` with the message revised to say the session was stopped mid-flight and the worktree may hold a partial operation (a stop kills the tool process, so a git command in progress can leave `index.lock`). The `:169` comment is replaced by the statement that the channel exists and this is its one use. | user-answered |
| D-3 | Per-role transcript content (ticket OR-2) | File created at spawn (`retro-corpus.sh:391` classifies `orchestrated` on presence). At spawn-end, append the last assistant text from `~/.claude/projects/<cwd-slug>/<sid>.jsonl` — the same content `-p` printed, durable and machine-readable (verified on nine probe sessions). `build-no-pr` remedy names that file and `claude attach <id>` instead of "read the lane log". Sessions are not `claude rm`'d: `rm` keeps the projects jsonl but deletes the job record (D-25) and ends attachability. | user-answered |
| D-4 | Live view on the control stream | One line at spawn carrying the id and `claude attach <id>`, one line per state transition the poll observes, one at spawn-end. No audit-ledger tail (#804's reader, declined), no heartbeat. #531's stream split holds: control on stdout; the payload no longer reaches stderr at all. The spawn passes `--name lean-<issue>-<role>-r<round>` so the id is recognisable in `claude agents` (documented flag). | user-answered |
| D-5 | Poll cadence and key (ticket OR-1) | `claude agents --json --all` every 30s (measured cost 0.16s per call), keyed on the exact `sessionId` the spawn returned. State enum read: working, blocked, done, failed, stopped (documented). | user-answered |
| D-6 | `blocked` under headless (ticket OR-1) | DEPARTURE — the operator's pre-authorized narrowing was taken (falsifier 5), and it removes the build-blocked and review-blocked slugs this row specified. What the row DECIDES is unchanged and shipped: a blocked session is stopped rather than left waiting on a keyboard that does not exist, it ends the phase, and the spawn still passes --disallowedTools AskUserQuestion to remove the one prompt source real payloads reach. Only the terminal it routes to moved, onto the session-failed slug that already existed. The authority is the ratification comment itself, not this session re-deciding. | user-answered |
| D-7 | Concurrency posture (ticket OR-3) | No change. The poll keys on an exact id; the single-lane assumption (#525, unproven per #564) is about worktrees and the gate, not transport. Recorded: the supervisor makes accidental double-launch easier; `pgrep` of the SCHEDULER still catches it. | user-answered |
| D-8 | Fallback for a payload stuck at `working` after its turn ended | DEPARTURE — same narrowing. The documented arm ships and bounds exactly the shape this row is about: a session reporting working past a wall-clock ceiling is stopped, ledgered as stuck, and the run proceeds as for done. The primary arm does not ship — reading the harness's private ~/.claude/jobs/<id>/state.json was the largest single piece of the poll loop that the reduced landing does not name, so it is the first thing the cut gave up. The bound is slower and coarser: the job record could name the shape in ninety seconds, and what replaces it can only bound TOTAL session runtime, because `working` is what a healthy session reports for its whole life and nothing left in the listing separates idle from busy. It ships at two hours, measured against this lane's own launch ledgers (55 BUILD spawns, median 12.6 min, max 100.5, 11 past thirty minutes). That is a SECOND departure inside this row and a departure from the ratified parameter itself — the receipt names a 30-minute silence ceiling — and it is disclosed under AC-3 and in the PR body for the operator to accept or refuse. It is never absent. | user-answered |
| D-9 | Environment handoff to the child | Nothing from the launcher's shell environment reaches a `--bg` session except the documented allowlist (PATH, provider selection): P1 saw LRM and LAM unset; P5 saw a marker var and TERM_PROGRAM unset. `LEAN_ATTEND_MODE=headless` and `LEAN_RUN_MODEL=<model>` are injected with `--settings '{"env":{...}}'` (P6 and C2: both arrived; the docs name a settings `env` block as the mechanism; `respawnFlags` in the job record show the flags persist across a supervisor restart). Harness-applied, not model-controlled, so #613's belt holds. The `env -u RUN_ID -u LEAN_RUN_MODEL` scrub is deleted as dead code. `CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS` and its rationale block (`:727-745`) are deleted: a turn that ends with a tracked task pending stays `working` and re-invokes (P4b, P4c, P4g). | codebase-derived |
| D-10 | Listing flag | `--all` is required: the docs list only "background sessions that are still working or blocked" by default; completed ones need `--all` (the three #549 `done` probes appear only under it). | codebase-derived |
| D-11 | Worktree relocation (ticket falsifier 3) | None. A session worktree is the explicit `-w, --worktree` flag; `claude rm` removes one only if it exists. Lane worktree handling is unchanged. | codebase-derived |
| D-12 | Launch-ledger `spawn` and `spawn-end` rows | `rc=N` becomes `state=<done, failed, stopped, blocked, stuck>`; the `spawn` row gains `id=<short id>`. `tools/lane-latency.sh` reads timestamps only; nothing parses `rc=`. | codebase-derived |
| D-13 | Terminal vocabulary | build-session-failed and review-session-failed retained as ONE source site whose slug is composed from the role, now firing on failed, stopped and blocked; their two register rows collapse to one and re-anchor on the message edit. spawn-unreadable gets a row of its own. stuck proceeds as done, and the revised staleness-expired message re-anchors its row. The narrowing removed the separate blocked slugs this row originally added. | codebase-derived |
| D-14 | Selftest seam | One `claude` fake discriminated on argv, the `gh` fake's precedent (selftest `:123`): `--bg` prints `backgrounded · <id>` and records the prompt and flags, `agents --json --all` is served from a case-written state file the case advances per call, `stop` and `rm` are recorded. The liveness scenario is extended for the poll, the stuck fallback, `blocked`, unreadable listing and the mid-flight exit 7 (writing-tests skill). The fake never sleeps: the poll interval is a seam (`LEAN_SPAWN_POLL_MS`) the suite sets to 0. | codebase-derived |
| D-15 | P10 boundary | Unchanged. The bg session's own `CLAUDE_CODE_SESSION_ID` equals the listed `sessionId` (P1, C2); no `--session-id`, no `--resume`. The audit ledger opens on the first tool call (present for every probe that ran a tool, mode 0600); a session that never calls a tool has none — `entry` never ran there, so nothing fails open. | codebase-derived |
| D-16 | `claude logs` | Not part of the design. It fails on finished sessions ("Couldn't read logs") and on live ones returns TUI chrome only. The ticket's "liveness is `claude logs` plus `state`" claim is corrected in the PR body: live view is `claude attach`, post-hoc view is D-3. | codebase-derived |
| D-17 | Prose surfaces that describe `-p` | `orchestrate-lean.sh` header blocks at `:24-30`, `:40-48`, `:163-171`, `:684-701`, `:727-745`; `run-lean/SKILL.md:44`; `review-lean/SKILL.md:154,158`; `build-lean/SKILL.md:41`. Each is rewritten for the supervised session or deleted with its mechanism. The `headless` contract in `operator-override.sh:53-117` gains one sentence: `claude attach` is a keyboard channel into a headless payload, so `headless` means "not attended through the gate", not "unsteerable" — the trust boundary (manifesto §The trust boundary) is the merge boundary either way. | codebase-derived |
| D-18 | Read failure of `claude agents --json`, and the supervisor's life | Fail closed, #527's posture: three consecutive unreadable or id-absent polls end the run with `terminal spawn-unreadable 1` naming the id; never scored as done. Measured (D): `kill -9` of the supervisor under a live session left the session running (its loop kept advancing), the listing still answered, `stop` worked, and only `rm` failed transiently — so three polls is the right tolerance. Documented: a session whose process exits unexpectedly is restarted by the supervisor and resumes its conversation (a payload crash therefore no longer surfaces as `build-session-failed` unless the supervisor gives up and reports `failed`); after an auto-update the supervisor restarts itself onto the new binary and sessions survive the version mismatch. The `spawn` preflight (`:579`) additionally parses `claude agents --json --all` and refuses (rc 2) when the array or its `state` field is absent. | codebase-derived |
| D-19 | Tracker follow-ups | #617 closes as absorbed; #549 receives a correcting comment. Operator acts at `Ratified:` time; BUILD writes neither, the PR body lists both. Parked under OR-2. | deferred |
| D-20 | Net-negative accounting (#717) | D-2 and D-8 consume margin. Falsifier 5 stands: if the diff is not net-negative once the poll loop and fallback exist, BUILD lands only the `:169` correction, id-at-dispatch and `claude stop` for exit 7, and records the negative in the PR body. Owed before `ready-for-dev`: the operator's `Ratified:` comment naming the consumer-visible outcome and the deleted files — parked under OR-1. | codebase-derived |
| D-21 | Supervisor idle rule (ticket falsifier 4) | No exposure. Documented: "Working, waiting-on-input, or attached sessions are never stopped"; the ~1h rule stops a finished, unattached session's process and keeps its conversation. A milestone-3 sweep is a working session throughout (P4c, P4g). | codebase-derived |
| D-22 | Permission prompts: parity with `-p` | The auto-mode classifier auto-denies inside a `--bg` session exactly as under `-p`: the same forced command (`rm -rf /tmp/… && mkdir …`, the class real payloads hit) returned "Permission to use Bash … has been denied" to the model, which continued to `done`, under plain `--bg` (T1), with `--permission-prompts none` (T2) and with a `PermissionRequest` deny hook (T3); the `-p` baseline (T0) returned the identical message. Real payloads carry 94 such denials across 44 of 84 sessions, so this parity is load-bearing and it holds with no extra flag. `--permission-prompts none` is documented for `--print` and adds nothing here; `dontAsk` replaces `auto` and is rejected. | codebase-derived |
| D-23 | What `blocked` means | Documented as the catch-all for "waiting on you": a question, a permission decision, or another prompt. Measured: a final reply that is a question reads `blocked` with no tool involved (S2), a plain statement reads `done` (S1); an `AskUserQuestion` call reads `blocked` (B2). So in this lane `blocked` is either a question-ending reply (which under `-p` was exit 0 with no PR) or a real prompt (closed by D-6's flag); both end the run, which is what `-p` did with less information. Falsifier 1 is scored dead on this basis, not on P3, whose `blocked` was a question-ending reply. | codebase-derived |
| D-24 | Alternatives, recorded as considered and declined | `-p --output-format stream-json`: liveness only, still a print-mode turn that ends on pending background work, still no control channel (#617 option 2). Agent SDK: the vendor-blessed headless surface, with interrupt and permission callbacks, but a Python or TS stratum in a bash lane and the same print-mode turn semantics. Teammates: experimental, interactive lead required, cannot nest. Subagents: share the parent's session id, refused by `cmd_verdict` (#805 body). `--bg` is documented ("the scriptable version for launching an agent from automation scripts"), needs no dependency, and is the only surface measured to handle the pending-work shape natively. | codebase-derived |
| D-25 | The job record | `~/.claude/jobs/<id>/state.json` and `timeline.jsonl` are harness-written, durable while the session exists (deleted by `claude rm`), and carry `state`, `detail`, `tempo`, `inFlight`, `output.result`, `respawnFlags`, `cliVersion` and per-transition timestamps. Undocumented: the lane reads it only in D-8's primary arm, where its absence degrades to the documented ceiling; `detail` is model-authored prose and is never read (it said "background task running" on every stuck session). D-3 keeps the projects jsonl as the transcript source. The PR body names the record as the operator's fastest post-hoc read. | codebase-derived |
| D-26 | The issue body's `## Open regions` table was unreadable to milestone 1 | Corrected in place under the bot identity, before any code was written: each disposition cell carried `<token> — <prose>`, and the gate's table arm compares the whole cell against the closed two-value enum, so all four rows scanned as "no recognizable disposition" and milestone 1 refused with rc=2. The tokens are now bare and the reasoning sits below the table as a PARAGRAPH, which is where `intake-toolkit:interviewing-baseline` puts it; a bullet list there re-fires the same refusal, because the bullet arm emits a second row per id and a bullet naming `OR-n` without a token carries an empty disposition. No disposition changed, nothing was resolved by this edit — OR-1, OR-3 and OR-4 are `pause-and-ask` and were already resolved by the operator's `Ratified:` comment, which names all four word-bounded. Disclosed here and in the PR body because a build-authored body edit is otherwise indistinguishable from a self-ratification. | codebase-derived |
| D-27 | Telemetry configuration on the far side of the transport swap | **Not covered by the receipt (P9), and named here rather than decided quietly.** D-9 enumerated the two variables the lane sets itself and stopped there, but `probe_telemetry` judges a run priceable from the LAUNCHER's `CLAUDE_CODE_ENABLE_TELEMETRY` / `OTEL_*`, and under `-p` the payload inherited exactly those. Dropping them would leave every payload session exporting nothing while preflight still called the run priceable, and `pipeline-cost-block.sh` would fall to its transcript source — tokens recovered, money not. Resolved as behavior preservation rather than as a new capability: the six variables the probe and the cost block already depend on are forwarded through D-9's own `--settings` mechanism, and only when the launcher actually carries one. Reversing it is deleting one loop. | codebase-derived |
| D-28 | `SECOND_SHIFT_CONFIG` on the far side of the supervised spawn (#811 OR-5; this is **D-26 in the pre-flight receipt**, whose ledger ends at D-25 — the spec's carried copy already holds a D-26 and a D-27 added during BUILD, so the ids diverge from here) | Forwarded in the spawn's `--settings` env block on every spawn when the launcher sets it, verbatim and absolute, and no key at all when it does not. The gate resolves it INSIDE the payload (`lean-gate.sh:489`, with lean-reconcile.sh, lean-evidence.sh, operator-override.sh, bot-commit.sh, gh-bot.sh, preflight.sh and pipeline-cost-block.sh sharing the same `${SECOND_SHIFT_CONFIG:-$MAIN_ROOT/.claude/second-shift.config.json}` ladder), so under `-p` it inherited and under `--bg` it silently fell back to the committed config: every launch carrying an alternate one (docs/consumer-eval.md's pinned-base recipe, the lane bench) targeted the wrong base branch with no error anywhere. Also recorded here because a wrapper author needs it: EVERY control-plane call goes through `$SPAWN_BIN` and not a literal `claude` — the `--bg` dispatch, `agents --json --all`, `stop <id>`, and preflight's resolvability probe — so a `LEAN_SPAWN_BIN` wrapper sees all four and must discriminate on argv, which is what D-14's fake already does. | codebase-derived |
