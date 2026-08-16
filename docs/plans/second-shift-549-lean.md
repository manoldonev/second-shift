# second-shift#549 — the phase-spawn transport

**Ticket:** [#549](https://github.com/manoldonev/second-shift/issues/549) (child of #525).
**Binding pre-flight receipt:** `.claude/pipeline-state/549-ledger.md` — 13 decisions, 3 open
regions. Where this spec and the issue body disagree, the receipt wins; every AC below cites the
decision it implements.

## The defect, restated in one line

`orchestrate-lean.sh` spawns every phase as `claude -p`, where **turn end is process exit**. A
phase therefore cannot yield: it cannot hold a `Monitor`, and it cannot own a process that
outlives the turn that started it. Every wait longer than the harness's 120s tool reap has to be
poll-driven, and each poll costs a full model round-trip.

The two properties the headless spawn buys — a fresh session per phase (P10) and unattended
chaining — do not depend on `-p`. They depend only on each phase being a *new* session the
scheduler can start and wait on. So the transport is the variable (D-2).

---

## AC-1 — the probe, recorded per candidate per criterion (D-2, D-3)

The probe is the first deliverable and its record is this section. D-3's six criteria are the
whole research budget; each restates a contract the scheduler already holds. Everything in the
tables below was **measured on this machine against CLI 2.1.233**, not reasoned about.

### The criteria (D-3, verbatim)

| # | Criterion |
| --- | --- |
| i | accepts a prompt and runs unattended to completion |
| ii | completion is detectable by the scheduler without a model round-trip |
| iii | an exit status is recoverable — every `\|\| terminal *-session-failed 1` arm consumes one |
| iv | #531 D-5's three-way stream split holds **verbatim** (D-4) — disqualifying |
| v | `--permission-mode` passes through as it does today |
| vi | no TTY required, because CI has none |

### The candidates

**A — `claude --bg` + `claude agents --json`** (D-2's native candidate)

| # | Verdict | Measured |
| --- | --- | --- |
| i | ✓ | The prompt is the positional. `--bg` refuses `--print` outright: *"--bg and --print conflict: --print never starts the interactive session that `claude agents` attaches to"*. Launched TTY-free it returned `rc=0` in 1s printing `backgrounded · 90f3736e`, and the session reached `state: done` unattended. |
| ii | ✓ | `claude agents --json --all --cwd <dir>` (its own help: *"does not require a TTY"*) reports `{"id":…,"status":"idle","state":"done"}`. Shell-side, no model turn. |
| iii | ✗ | The session **never exits** — it stays resident as an attachable agent (`state: done`, pid alive). There is no exit status to recover: the record carries no `exitCode`, and the scheduler is not the parent, so there is no wrapper position for D-7's rc file either. Only the *launcher's* rc is available, and it reports whether the job started, not how it ended. |
| iv | ✗ | The payload reaches no pipe the scheduler holds. The only two channels are `claude logs <id>` — a non-streaming **ANSI TUI screen-dump**, not a stream — and the private per-session JSONL under `~/.claude/projects/`. Reconstructing the payload from the latter would make the scheduler a reader of an undocumented format, a larger commitment than anything its header currently permits. |
| v | ✓ | Accepted and passed through. |
| vi | ✓ | Ran with stdin `/dev/null` and both streams redirected. |

**Fails iii and iv.** D-4 named this outcome in advance ("including the native `--bg` one").

**B — `script(1)` pty wrapper**

| # | Verdict | Measured |
| --- | --- | --- |
| i | ✗ | `script -q /dev/null claude … "<prompt>"` was **still alive at 70s** and had to be killed. A pty makes the session interactive, and an interactive session does not exit on its own. |
| ii | ✗ | Completion would have to be scraped out of the TUI. |
| iii | — | Moot: nothing exits. |
| iv | ✗ | 13 ANSI escape sequences in the first 1302 bytes; the capture is a rendered terminal, not a payload stream. |
| v | ✓ | Passed through. |
| vi | ✗ | Inventing a TTY is the candidate's entire mechanism. |

**C — `--tmux` / iTerm2 native panes**

| # | Verdict | Measured |
| --- | --- | --- |
| i | ✗ | `--tmux` **requires `--worktree`** (the CLI's own help), which collides head-on with a lane whose worktree is created and destroyed by the gate. |
| ii–v | ✗ | Unreachable behind i. |
| vi | ✗ | Needs a terminal, and `tmux` is not installed on the operator's own machine (`command -v tmux` → absent), so it fails before CI is considered. |

**D — the streaming transport** — `-p --input-format stream-json --output-format stream-json
--verbose`, prompt delivered as one compact JSON user message on stdin. **Not in D-2's
enumeration** — see the intent-gap record below.

| # | Verdict | Measured |
| --- | --- | --- |
| i | ✓ | A 60s foreground tool call ran to completion unattended: `result subtype=success`, `SLEPT-60`, rc=0 at 84s. |
| ii | ✓ | The `{"type":"result"}` line on stdout, and the child's own exit. Both shell-readable. |
| iii | ✓ | **Native.** The session is a direct child, so `${PIPESTATUS[0]}` is unchanged from today. rc=0 measured on success, rc=1 measured on a malformed input line. |
| iv | ✓ | The payload is the child's **stdout pipe**. It is rendered to text and tee'd to exactly the two sinks #531 D-5 defined, so all three legs of the split hold verbatim. |
| v | ✓ | Passed through unchanged. |
| vi | ✓ | stdin is a file, stdout a pipe, stderr a pipe. No TTY anywhere. |

**Survives all six.**

### And it removes the defect, which no criterion asks about

The criteria bound the research budget; they do not by themselves show the transport is worth
changing. Two further measurements do:

* **The process outlives turn end.** After `result subtype=success` the child was still alive
  (`poll=None`), accepted a **second** user message on the same process, took a second turn, and
  exited `rc=0` only when stdin closed. Turn end is no longer process exit.
* **A 200-second foreground tool call completes.** Reaped at ~128s exactly as under `-p`, the
  model then took further turns and the call **still returned `SLEPT-200`** with
  `result subtype=success` at 210.5s. The reap is unchanged; what changed is that the process
  survives it.

Both controls are in AC-2's evidence and in the PR body.

---

## AC-2 — the streaming transport becomes the DEFAULT; `-p` text is an automatic fallback (D-1, D-8)

`spawn()` uses the streaming transport for every phase. `-p` text is retained and is selected
**automatically by a capability check**, never by an operator-facing knob — a seam defaulted off
delivers nothing (D-1).

* The check is for the capability the winner actually needs: the session binary advertising
  `--input-format` in its own `--help`, and `jq` resolving. It is evaluated **once** per run and
  cached, not per spawn.
* Deliberately **not** a TTY check. D-1 lists "no TTY" among the fallback triggers because at
  intake the presumed winner was TTY-dependent; the winner is not, so a TTY test here would
  select the fallback for a condition that does not affect it. Recorded as a departure rather
  than silently taken.
* All three spawn sites move together (D-8): `spawn()` is one function serving BUILD, REVIEW and
  the close-out, and phase-selective routing would be more code, not less.
* The fallback path is byte-identical to today's argv, which is what makes the revert one
  capability check (OR-3).

## AC-3 — the three-way stream split holds verbatim under both transports (D-4)

Under either transport: control lines on the scheduler's **stdout**, timestamped; payload on
**stderr** and appended to the per-role transcript at
`<pipelineStateDir>/<issue>-lean-spawn-<n>-<role>.log`. So a plain `> control.log` still captures
only control, the transcript still carries only payload, and the terminal still shows everything.

Under the streaming transport the payload is **rendered to human text** before it reaches those
two sinks — a wall of stream-json in the transcript would satisfy the letter of the split and
destroy the thing it exists for. The renderer formats and never judges: assistant text passes
through, a tool use becomes one `· <ToolName>` line, and any line that is not JSON (the child's
own diagnostics, merged by the existing `2>&1`) passes through raw. It is the same class of
operation as the `tee` beside it.

If the renderer cannot run, the payload is passed through unrendered rather than dropped:
advisory, never fatal — the same posture the transcript open already takes.

## AC-4 — the exit status is recovered from the child under both transports (D-7)

`${PIPESTATUS[0]}` remains the child's own status. The scheduler's advancement authority is
unchanged — `progress_token`, `infra_token` and PR presence — and rc still feeds only the
`*-session-failed` terminals. No rc file and no wrapper is needed, because the winning transport
keeps the session a direct child; D-7's "thin wrapper" contingency is not exercised.

## AC-5 — the phase learns which transport it is under, and the channel is scrubbed (D-5)

`spawn()` exports `LEAN_PHASE_TRANSPORT` to the session it starts, valued `stream` or `print`.

`lean-gate.sh` scrubs it for nested lane children, appended to `SEAM_SCRUB_ENV` exactly where
`LEAN_GATE_M3_NEW_SESSION` is appended and for the identical reason: a lane child is not
turn-bound and has nothing to outlive, so an inherited value would tell a nested child it may
yield.

## AC-6 — `build-lean/SKILL.md`'s in-flight rule gains the two-branch form (D-5) — doc AC

The rule currently reads as an unconditional fact about `-p`. It becomes two branches keyed on
`LEAN_PHASE_TRANSPORT`: under `print` the existing prohibition stands verbatim; under `stream`
the phase MAY yield and be re-invoked by notification, which is where the round-trip saving
comes from. Milestone 3's detach-and-block behavior is unchanged under both (D-9).

## AC-7 — `review-lean/SKILL.md`'s premise stops being false (D-8) — doc AC

D-8 moves all three spawn sites, so `review-lean/SKILL.md`'s assertion that the scheduler spawns
it "under `claude -p`, and there turn end IS process exit" is false under the default transport.
It is corrected to name the transport as variable and to point at `LEAN_PHASE_TRANSPORT`. Its
measured `Workflow`-under-`-p` note is left standing — that measurement is still true of the
fallback.

## AC-8 — `lean-gate.sh`'s milestone-3 rationale stops asserting the retired premise — doc AC

The milestone-3 detach-and-block comment justifies itself with "orchestrate-lean.sh spawns every
BUILD session under `claude -p`, where TURN END IS PROCESS EXIT". The **mechanism stays** (D-9 —
`LEAN_GATE_M3_NEW_SESSION`, `M3_WAIT_CEILING_ESCAPE_DEFAULT` and the `infra_token` continuation
arm all stay, because the `-p` path is retained as the fallback), but the premise sentence is
narrowed to the fallback it is now true of.

## AC-9 — guarded through the existing fake; no suite spawns a real session (D-11)

`orchestrate-lean-selftest.sh` already substitutes a stub `claude` through `LEAN_SPAWN_BIN`. The
stub is extended to serve the winner's surface — a `--help` that advertises `--input-format`, and
a recording of the JSON user message it was handed on stdin — so the capability check itself is
what the cases drive. **No new env knob is introduced to select the transport**, which is what
keeps D-1's "never an operator-facing knob" true in the suite as well as in production.

New cases, each naming an invariant no existing case reaches:

1. **capability present ⇒ streaming argv** — the recorded argv carries `-p --input-format
   stream-json --output-format stream-json --verbose`, and the recorded stdin is a single-line
   JSON user message whose text is the phase prompt.
2. **capability absent ⇒ the `-p` text fallback** — a stub whose `--help` does not advertise
   `--input-format` produces today's argv exactly, prompt as the positional.
3. **`jq` unavailable ⇒ the same fallback**, for a different reason than (2).
4. **the split holds under the streaming transport** — control on stdout only; the per-role
   transcript carries the **rendered** payload text and no raw `{"type":` line.
5. **rc is the child's** under the streaming transport — a scripted non-zero reaches
   `build-session-failed`.
6. **`LEAN_PHASE_TRANSPORT` is exported and names the active transport**, under both arms, while
   the `RUN_ID` / `LEAN_RUN_MODEL` scrub and the absent session id still hold.

Editing this guard re-keys its generic survivor ordinals: `tools/mutation-baseline.tsv` is
re-baselined in the same diff, and any `tools/mutation-catalog.tsv` row addressing the two edited
guards is re-anchored.

## AC-10 — the exit criterion is round-trip count, not wall clock (D-6)

D-6's evidence is one real build phase's per-role transcript showing the milestone-3 wait
consuming at most one model turn. That is produced by a **run**, not by this diff, so it is not
gated here — this AC records what the evidence is and where it comes from, so the claim is not
quietly upgraded to "proved" by a green CI. What this diff proves is the transport's properties
(AC-1) and the scheduler's behavior under both arms (AC-9).

---

## Open Regions — dispositions taken

| ID | Disposition | Outcome |
| --- | --- | --- |
| OR-1 | pause-and-ask | **Did not fire.** Its trigger is "no candidate survives D-3's criteria list"; candidate D survives all six, measured. The per-candidate, per-criterion table the region asks for is AC-1 either way. |
| OR-2 | pause-and-ask | **Answered by measurement, not by a default.** See below. |
| OR-3 | reversible-default-and-flag | Default taken as stated: D-6's round-trip count suffices to land the change. The revert is one capability check, and the fallback is code that stays exercised by AC-9 cases (2) and (3). Corpus sizing stays with `/dev-pipeline:perf-retro`. |

**OR-2 — "whether a phase that yields under the winning transport is genuinely re-invoked,
rather than parked."** Measured under the streaming transport: a session that armed a background
task and ended its turn at 3.7s was **re-invoked at 44.8s** by a harness-delivered event, with
zero polls and no further stdin, and settled to `result subtype=success` at 47.0s. The same shape
holds with stdin at EOF (`num_turns=2`, rc=0, 50s for a 40s task). The region exists because a
transport that parks a yielded phase would strand the lane silently; it does not park it.

## The intent gap — the winner is outside D-2's enumeration

D-2 resolved "not pre-committed … the winner is whichever survives all of them", and enumerated
three candidates. All three fail. A fourth — the streaming transport — survives every criterion.
Whether the probe may consider a candidate the receipt did not enumerate is a decision the
receipt does not cover, so it is recorded as an intent gap rather than taken silently:
`docs/plans/second-shift-549-lean-intent-gap.md`, which must be ratified before the merge boundary
will accept this branch.

## Out of scope

* The visibility half of #531 (AC-2/AC-3 there already own it) — this is elapsed time only.
* Retiring the `-p` mitigations (D-9): the fallback keeps their premise true.
* Corpus-level sizing of the tax (OR-3), owned by `/dev-pipeline:perf-retro`.
* Human-in-the-loop shortcuts, and the P10 identity contract, which every candidate preserves
  (D-10) — a fresh session per phase, the `env -u RUN_ID -u LEAN_RUN_MODEL` scrub re-applied per
  spawn, `--permission-mode` passed through, and no phase able to block on a human prompt.
