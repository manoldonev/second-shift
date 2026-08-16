# second-shift#549 — the phase-spawn transport

**Ticket:** [#549](https://github.com/manoldonev/second-shift/issues/549) (child of #525).
**Binding pre-flight receipt:** `.claude/pipeline-state/549-ledger.md` — 13 decisions, 3 open
regions. Where this spec and the issue body disagree, the receipt wins.

> **This run is PAUSED on OR-1, and no transport change is proposed.** The probe was run, and its
> answer is that **no candidate survives D-3's criteria list** — including a fourth candidate the
> receipt did not enumerate, which survives every criterion in the configuration that delivers
> nothing and fails criterion (ii) in the configuration that delivers the win. OR-1's disposition
> is `pause-and-ask`, and its own reasoning names this artifact as what makes the stop legible.
> AC-1 below is that artifact. AC-2 records the stop. Nothing else is claimed.

## The defect, restated

`orchestrate-lean.sh` spawns every phase as `claude -p`, where **turn end is process exit**. A
phase cannot yield: it cannot hold a `Monitor`, and it cannot own a process that outlives the turn
that started it. Every wait past the harness's 120s tool reap is poll-driven, and each poll costs a
model round-trip.

---

## AC-1 — the probe, recorded per candidate per criterion (D-2, D-3)

Everything below was **measured on this machine against CLI 2.1.233**, with `claude-haiku-4-5` as
the probe model and identical prompts across arms. No result here is reasoned about.

### The criteria (D-3, verbatim)

| # | Criterion |
| --- | --- |
| i | accepts a prompt and runs unattended to completion |
| ii | completion is detectable by the scheduler without a model round-trip |
| iii | an exit status is recoverable — every `\|\| terminal *-session-failed 1` arm consumes one |
| iv | #531 D-5's three-way stream split holds **verbatim** (D-4) — disqualifying |
| v | `--permission-mode` passes through as it does today |
| vi | no TTY required, because CI has none |

### A — `claude --bg` + `claude agents --json` (the receipt's native candidate)

| # | Verdict | Measured |
| --- | --- | --- |
| i | ✓ | The prompt is the positional; the CLI refuses `--bg` with `--print` outright (*"--print never starts the interactive session that `claude agents` attaches to"*). Launched TTY-free it returned rc=0 in 1s and reached `state: done` unattended. |
| ii | ✓ | `claude agents --json --all --cwd <dir>` (*"does not require a TTY"*) → `{"status":"idle","state":"done"}`. Shell-side. |
| iii | ✗ | The session **never exits** — it stays resident and attachable. No `exitCode` in the record, and the scheduler is not the parent, so D-7's "thin wrapper writes an rc file" has no position to sit in. |
| iv | ✗ | The payload reaches no pipe the scheduler holds. The only channels are `claude logs <id>` — a non-streaming ANSI TUI screen-dump — and the private per-session JSONL. |
| v | ✓ | Accepted, passed through. |
| vi | ✓ | stdin `/dev/null`, both streams redirected. |

### B — `script(1)` pty wrapper

| # | Verdict | Measured |
| --- | --- | --- |
| i | ✗ | **Still alive at 70s** and killed; a pty makes the session interactive and it does not exit on its own. |
| ii | ✗ | Only by scraping the TUI. |
| iii | — | Moot: nothing exits. |
| iv | ✗ | 13 ANSI escape sequences in the first 1302 bytes — a rendered terminal, not a stream. |
| v | ✓ | Passed through. |
| vi | ✗ | Inventing a TTY is the mechanism. |

### C — `--tmux` / iTerm2 native panes

| # | Verdict | Measured |
| --- | --- | --- |
| i | ✗ | `--tmux` **requires `--worktree`**, which collides head-on with a lane whose worktree the gate creates and destroys. |
| ii–v | — | **Not measured.** Unreachable behind i, and `tmux` is absent, so there was nothing to measure them against. Unreachable is not the same as failing, and scoring these ✗ would claim four measurements nobody took. |
| vi | ✗ | Needs a terminal, and `tmux` is absent on the operator's own machine. |

Criterion i disqualifies C on its own; the outcome does not turn on the four rows above.

### D — the streaming transport, which the receipt does not enumerate

`claude -p --input-format stream-json --output-format stream-json --verbose`, prompt delivered as
one compact JSON user message on stdin. It has **two configurations**, and they do not agree:

| # | stdin closed at EOF | stdin held open |
| --- | --- | --- |
| i | ✓ 60s foreground call → `result: success`, rc=0 at 84s | ✓ |
| ii | ✓ the `{"type":"result"}` line, then the child exits | ✗ **see below** |
| iii | ✓ native — direct child, `${PIPESTATUS[0]}` unchanged | ✓ native |
| iv | ✓† payload is the child's stdout pipe, tee'd to today's two sinks | ✓† |
| v | ✓ | ✓ |
| vi | ✓ stdin a file, both streams pipes | ✓ |

† **(iv) holds given a renderer that does not exist.** The channel is right — it is a pipe the
scheduler owns — but the bytes on it are stream-json, and a wall of stream-json in the transcript
satisfies the letter of D-4's split while destroying the thing the split exists for. The ✓ is for
the channel, not for the output as it stands.

**Why "held open" fails (ii).** A `result` event is emitted at *every* settle point, not at the
end of the phase. Measured: a session that armed a `Monitor` emitted `result: success` at 15.0s,
stayed alive, was re-invoked when the monitor fired at 42.7s, did the work, and emitted a **second**
`result` at 45.2s. So the scheduler cannot tell a settle-with-work-pending from a final one without
either reading the payload — which its own header forbids — or inventing a quiet-period timeout,
which would silently kill exactly the long waits this ticket exists to make cheap.

### And the measurement that decides it: the EOF configuration buys nothing

The two configurations were A/B'd against plain `-p` on identical prompts:

| shape | 40s backgrounded tool call | 200s foreground call (reaped at 120s) | armed `Monitor` |
| --- | --- | --- | --- |
| plain `-p` | ✓ completed | ✗ rc=0 at 152s, nothing written | ✗ (previously measured) |
| streaming, stdin at EOF | ✓ completed | ✗ rc=0 at 138s, nothing written | ✗ abandoned at `result` |
| streaming, stdin held open | ✓ completed | ✓ returned `SLEPT-200` at 210.5s | ✓ fired; session re-invoked |

The harness already holds a turn open for a backgrounded tool call under **both** `-p` and the
EOF configuration, so that column is not a difference. The only column that moves is the one whose
configuration fails criterion (ii).

**An earlier reading of this evidence was wrong and is corrected here.** The 200s row was first
scored as `-p` failing and "the streaming transport" succeeding — but the succeeding run held stdin
open and the failing one did not, and in the EOF run the model simply ended its turn after the reap
and the process exited with it. Attributing that to the transport would have credited it with a win
it does not have.

### What is not committed here, and why that is a known weakness

The numbers above with decimals in them — the 15.0s/42.7s/45.2s settle sequence, `SLEPT-200` at
210.5s, 13 ANSI escapes in the first 1302 bytes — were read off live runs during the build session,
and **their transcripts, scripts and timing logs were not preserved**. The tables are the
per-candidate, per-criterion record D-3 asks for and they are complete at that level, but they are
not independently re-checkable.

That matters more here than it usually would, because this dataset has **already produced one wrong
conclusion** — the 200s row corrected immediately above — and it was caught only by re-reading
notes that no longer exist. A second error of the same kind would be undetectable from this
document.

So: treat every timing above as a **single-run observation on one machine**, not as a reproduced
measurement. The claims that survive without the notes are the cheap re-checkable ones, and those
were re-run independently at review and held exactly — `claude --version` = 2.1.233, `command -v
tmux` absent, the `--bg`/`--print` refusal text, and `--tmux` requiring `--worktree` per `claude
--help`. Re-running the settle-sequence measurement behind a committed harness is the first thing
question 1 below should buy if it is taken; it is the finding everything else would rest on.

## AC-2 — the stop, and what it is asking for (OR-1)

OR-1's trigger condition is met: no candidate survives D-3's criteria list. Its disposition is
`pause-and-ask`, and its stated reasoning applies exactly — *"picking a candidate that fails a
criterion silently re-opens the contract that criterion protects, and landing nothing while
reporting success is the shape #531 was filed for."*

**No production file is changed by this branch.** A working implementation of candidate D in its
EOF configuration was written and reverted: it passes every criterion, the scheduler's loop stays
green under it, and it is measured to deliver **no** improvement — landing it would have reported
this ticket done while changing nothing an operator would feel.

**What this branch withdrew.** At `608e57c` this spec carried **AC-1 through AC-10** — a full
implementation spec that made candidate D's EOF configuration the lane's default, with the
capability check, the `LEAN_PHASE_TRANSPORT` channel, the `SEAM_SCRUB_ENV` scrub, both `SKILL.md`
two-branch rules, and six new `orchestrate-lean-selftest.sh` cases. `5bd3654` replaced that set
with the three ACs above, once the A/B at the end of AC-1 showed the EOF configuration buys
nothing. The direction of that edit is the safe one — claims were *withdrawn*, not stretched to
cover a diff — and OR-1's `pause-and-ask` disposition, written at intake, is what licenses
replacing the AC set mid-run. It is disclosed here because the merged file otherwise reads as
though this ticket never had an implementation spec at all.

**And the implementation is gone.** It was discarded rather than parked: it is not in the reflog,
not in a stash, and not in a dangling object. Reverting before handoff was right; discarding and
preserving were separate decisions and only the first was taken. The cost lands entirely on
question 1 below, where the held-open configuration would reuse most of it — in particular the
`spawn_prompt` accessor that decouples the selftest's ten argv-bound prompt assertions from the
transport, which is a prerequisite for *any* transport that moves the prompt off argv, not just
this one.

What the operator is being asked, on the issue:

1. **Is the completion contract in scope?** Candidate D in its held-open configuration delivers
   the win and needs a way for a phase to say "I am finished" that is not the `result` event — a
   sentinel the phase writes, or the scheduler watching a gate record. That is a new contract on
   `build-lean`/`review-lean`, not "one capability check plus one branch" (D-1's stated price), and
   it re-opens OR-2 rather than settling it.
2. **Or does the ticket close as answered?** The measurement is that the reap, not the transport,
   is what makes a long wait expensive, and that the gate's existing detach-and-block (#511) is
   already the mitigation for it (D-9 keeps it). On that reading the remaining cost is the one the
   issue's own follow-up comment names — the close-out session re-running a full milestone-3 sweep
   on an unchanged head — whose lever is `tools/run-selftests.sh --cache-dir`, not the transport.

## AC-3 — nothing is claimed that was not measured

This branch adds one document. It changes no behavior, adds no seam, and asserts no improvement.
D-6's exit criterion (one real build phase's transcript showing the milestone-3 wait costing at
most one model turn) is **not** met and is not claimed to be.

## What this branch does not dispose of

The receipt's remaining decisions are each conditional on a surviving candidate, and none survived.
That is not skipped work — but it is also not *settled* work, and a merge carrying `Closes #549`
would dispose of all nine **by closure**, silently. They are enumerated here so the disposition is
something a reader can find rather than infer, and so that answering OR-1 is one line per row
rather than a re-derivation.

**Every row below is `parked — awaiting OR-1`.** Under question 2 the whole table resolves to
"closed as answered; no transport lands, so nothing here has a subject". Under question 1 the whole
table carries forward into the re-scope, against candidate D's held-open configuration.

| Item | What it obliges | Why it has no subject yet |
| --- | --- | --- |
| D-1 | Winner becomes the lane default; `-p` retained as an automatic fallback behind a `spawn()` capability check | There is no winner to default to. D-1's stated price — one capability check plus one branch — is also measured to be the wrong price for the only configuration that delivers anything (see question 1). |
| D-4 | #531 D-5's three-way stream split holds verbatim under the new transport | Scored **per candidate** as criterion (iv) in AC-1, which is the disqualifying use D-4 asks for. What is not done is the other half — asserting it in the suite against a landed transport. |
| D-5 | `LEAN_PHASE_TRANSPORT` channel, the nested-child `SEAM_SCRUB_ENV` scrub, and `build-lean/SKILL.md`'s two-branch in-flight rule | The two-branch rule's second branch describes a transport that does not exist; writing it now would document a capability the lane does not have. |
| D-7 | The transport must surface a recoverable rc; a thin wrapper writes an rc file where it is not native | Measured per candidate as criterion (iii). Candidate A is where it actually bites — the session never exits, so the wrapper has no position to sit in. No wrapper is written because no candidate is adopted. |
| D-8 | All three spawn sites move together, via the single `spawn()` | `spawn()` is unchanged, so the invariant holds vacuously. Re-assert it against any landed transport. |
| D-10 | P10 identity invariants **asserted**, not assumed, under the new transport: fresh session per phase, the `env -u RUN_ID -u LEAN_RUN_MODEL` scrub re-applied, `--permission-mode` passed through, no phase able to block on a human prompt | `--permission-mode` pass-through was measured per candidate (criterion v). The other three are unasserted — they are properties of a spawn path that did not change. |
| Testing 1 | Extend `orchestrate-lean-selftest.sh`'s `LEAN_SPAWN_BIN` fake with the winner's surface plus a fake status channel | No winner, no surface to fake. |
| Testing 2 | The fallback path stays exercised by the cases that run today | Holds vacuously — those cases are the only cases, and they are green on this branch. |
| Testing 3 | #531's stream-split assertions are the acceptance evidence for D-4 and must pass under **both** transports | There is one transport. They pass under it. |

One obligation from `## Testing` is **not** parked and is discharged: *"editing this guard re-keys
its generic survivor ordinals — re-baseline in the same diff."* This branch edits no guard, so
there are no ordinals to re-key and no `tools/mutation-catalog.tsv` row to re-anchor.

---

## Open Regions — dispositions taken

| ID | Disposition | Outcome |
| --- | --- | --- |
| OR-1 | pause-and-ask | **FIRED.** No candidate survives D-3's criteria list. AC-1 is the per-candidate, per-criterion artifact the region asks for; the question is on the issue and the run is paused. |
| OR-2 | pause-and-ask | **Partly answered, and it matters for question 1 above.** A yielded phase *is* genuinely re-invoked under candidate D's held-open configuration — measured, monitor fired at 42.7s and the session resumed. It is **not** re-invoked in the EOF configuration, where the session finalizes and the yield is abandoned. So the region's risk is real and configuration-dependent. |
| OR-3 | reversible-default-and-flag | Not reached — there is no default to reverse. Corpus sizing stays with `/dev-pipeline:perf-retro`. |

## Out of scope

* The visibility half of #531 — this ticket is elapsed time only.
* Retiring the `-p` mitigations (D-9); nothing here gives grounds to.
* Corpus-level sizing of the tax (OR-3).
