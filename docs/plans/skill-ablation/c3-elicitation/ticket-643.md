# The scheduler's only signal is an exit code its transport cannot produce

Lane B of the 2026-08-22 backlog recalibration. Operator pain point, stated directly: *"run-lean
orchestrator works like shite, not sure `claude -p` is meaningful."*

**#617, #638 and #639 are sequenced behind this and must not execute first** — all three are
repairs to a transport this slice may delete.

## Problem

`run-lean`'s contract is that it is a scheduler: it *"reads exit codes and tracker state, and
authors nothing."* Its transport cannot produce the exit codes that contract is built on.

`plugins/dev-pipeline/skills/run-lean/orchestrate-lean.sh:633`:

```
"$SPAWN_BIN" --permission-mode "$PERM_MODE" --model "$model" -p "$prompt" 2>&1 | tee -a "$log" >&2
```

`claude -p` exits 0 whenever the model ends its turn — success, failure, or a turn that ended
holding unpushed commits. **Six separate rationale blocks in this one file exist to work around
that single property**: `:39` (exit status is not a completion signal), `:87` (close-out exit
untrustworthy), `:111` (dirty tree at turn end), `:122` (SIGKILL untrappable, no surviving
process), `:178` (no channel into a live session), `:947`. The scheduler compensates by re-running
`lean-gate.sh` after every spawn to obtain a signal the spawn itself could not give it — so each
phase boundary costs a full gate execution on top of the session.

### The precedent is already in the file, and it worked

`:947` records what #590 did about exactly this, at one of the four spawn sites:

> NO SPAWN, NO CONTINUATION BUDGET, NO TOKEN COMPARISON. All three existed to work around one
> property of a model session: `claude -p` exits 0 whenever the model ends its turn... **A gate
> command cannot end its turn early — its exit code IS the verdict.**

The close-out spawn was deleted and replaced by a direct gate call. It removed a failure class
without adding one. That is the template; this slice asks whether it generalizes.

### What it costs today, measured

- **#618**: a `run-lean` run is substantially **slower end-to-end than the same ticket driven
  manually through `build-lean` + `review-lean` in two terminals**. Cold-start tax measured at
  ~9 minutes per spawn (run #546: spawned 20:15:45Z, first gate call 20:24:47Z), paid again every
  round. Even a round-1 approve with zero fixes costs 3 sessions.
- **#617**: the operator sees nothing for the life of each payload session — routinely 30-60
  minutes. A working session, a hung session and a killed one render identically. That same run
  had two sessions killed mid-milestone-3 and the kill was invisible at the terminal.
- **#549**: the spawn-transport probe found **no surviving candidate** — `result` fires at every
  settle, so no output-format change recovers a meaningful completion signal.

So on its own stated justification — velocity principle V2, *"the operator-in-the-middle wait
between build and review is the specific latency the lane's scheduler exists to delete"* — the
scheduler currently measures **negative**: it is slower than the wait it was built to remove.

## Scope — a decision, not a repair

Pre-register the criterion, measure, then execute whichever arm the measurement selects. Do not
open with a fix.

**The measurement.** Same ticket class driven three ways, wall-clock and session count recorded:
(a) `run-lean` as it stands; (b) manual two-terminal `build-lean` + `review-lean`; (c) a
gate-call-shaped variant that keeps only the spawns which genuinely need a model session and
replaces the rest with direct `lean-gate.sh` calls, per the #590 template.

**The three arms, named before the numbers land:**

- **Delete** — if (b) beats (a) on wall-clock and operator attention, `run-lean` retires and the
  documented lane is two terminals. ~2,669 lines go (`orchestrate-lean.sh` 996 +
  `orchestrate-lean-selftest.sh` 1,673). This is the arm the current evidence points at.
- **Reshape** — if (c) wins, the scheduler survives as a thin driver over gate calls, and the
  spawn count drops to the irreducible set.
- **Keep** — if (a) wins, #617/#638/#639 execute as filed and this slice records the refutation.

A negative result is a result. Recording that the scheduler earns its keep is a valid exit.

## Acceptance Criteria

- **AC-1** (oracle): a committed pre-registration naming the criterion and the three arms, dated
  and landed **before** any timing is collected.
- **AC-2** (proxy): at least three runs per arm on comparable tickets, with wall-clock, session
  count, and operator-attention minutes recorded in a committed evidence file.
- **AC-3** (critic): the selected arm is executed in this slice, or — if the result is `keep` —
  the refutation is recorded and #617/#638/#639 are unblocked with a comment citing it.
- **AC-4** (oracle — selftest): whichever arm lands, `bash tools/run-selftests.sh --full
  --exclude tools/install-topology-selftest.sh` is green and no orphaned selftest survives its
  subject.
- **AC-5** (critic): `docs/` states the lane's front door truthfully after the change — if
  `run-lean` retires, the two-terminal flow is the documented lane and `plugin.json` /
  marketplace surfaces stop advertising it.
- **AC-6** (critic): `Changelog:` trailer, with a `Migration:` line if the front door moves.

## Operator amendment — the scope split (2026-08-23)

*Operator-authored. The scope licence comes from the operator, not from the build session; the
ratified restatement at the foot of this body is the same amendment, signed.*

**AC-2, AC-3 and AC-5 are DEPARTED for this slice and are carried by #650.** Recorded as `D-1`,
`D-2` and `D-3` in `docs/plans/second-shift-643-lean.md`, and stated here because `build-lean` reads
this body, not the branch — a departure asserted only on the branch is invisible to the scope gate,
which is the same failure mode as putting a scope amendment in a comment.

| AC | Disposition | Why |
| --- | --- | --- |
| AC-2 — three runs per arm | → **#650** | Nine lane runs across three drive-modes over days; not collectable in one build session, and variant `c` does not exist yet. This slice delivers the retrospective audit instead. |
| AC-3 — execute the selected arm | → **#650** | This slice selects no arm. The criterion's own rule is that the retrospective corpus *narrows* the arms and the prospective runs select; selecting here is the precise failure the criterion exists to prevent. |
| AC-5 — front-door truth | → **#650** | Conditional on an arm landing. No front door moves in this slice, so the criterion is vacuous here. |

**What #643 delivers:** the measurement instrument (the pre-registered criterion, the attribution
rubric, the fixed corpus) plus the retrospective audit that corpus can support — AC-1, AC-4, AC-6,
and the two ACs this slice added, AC-7 (the follow-up is filed) and AC-8 (every corpus spawn carries
its evidence).

**#617, #638 and #639 stay blocked, but on #650, not on this.** The Problem section above sequences
them behind #643; the decision that gates them moved to #650 when AC-3 departed, and `Closes #643`
fires when this PR merges. They unblock when #650 selects an arm.

Open regions: which ticket class the three arms are measured over — reversible default is the
next three `ready-for-dev` tickets of comparable size, flagged in the PR.

Provenance: 2026-08-22 backlog recalibration, operator-directed. Evidence: `orchestrate-lean.sh`
as cited, #618, #617, #549, and #590's landed precedent.


---

# Pre-registered criterion — revision 2 (AUTHORITATIVE)

This section is the criterion AC-1 requires. It supersedes nothing in the Scope above; it
fixes the measurement procedure the Scope left open. **The build session must land this as a
committed file under `docs/plans/` in the slice's FIRST commit, before any timing is
collected** — AC-1 says "committed", and a comment is not.

Revision history: [revision 1](https://github.com/manoldonev/second-shift/issues/643#issuecomment-5385766947)
was audited by an independent Fable session; four blockers were accepted and the criterion
amended. Revision 1 stays up unedited so the bar's movement is visible.

An independent Fable session audited [revision 1](https://github.com/manoldonev/second-shift/issues/643#issuecomment-5385766947)
and returned four blockers. All four are accepted. **The original comment stays up unedited**, so
that every movement of the bar is visible rather than rewritten away.

The amendments make the criterion **harder on the delete arm**, which is what an audit of a
motivated author should produce. Two further defects, found while verifying the audit's claims
against the repo, are added below.

### Correction to B2 — the evidence is destroyed, not merged

The audit found that the launch count cannot be reconstructed from the corpus, and proposed
recovering it from log append boundaries. That recovery is **not available**. `orchestrate-lean.sh`
truncates before it appends:

```
if ! ( : > "$log" ) 2>/dev/null; then      # :621 — truncates to zero
...
  | tee -a "$log" >&2                       # :633 — appends within this spawn only
```

`SPAWN_N` resets per scheduler process (`:607`), so a re-launch reopens `<issue>-lean-spawn-1-*.log`
and **truncates the previous launch's payload**. `tee -a` appends only within one spawn. The three
`641-lean-spawn-*.log` files against four recorded launches are not a merge — the earlier launches'
transcripts are gone.

Consequence: the launch enumeration must come from sources outside the corpus (the operating
record, `cost-log.jsonl`, tracker timestamps), be committed before scoring, and mark unrecoverable
launches explicitly.

**This also changes revision 1's "unmeasurable stays in the denominator" rule, which I had believed
was the conservative choice.** Counting an unrecoverable launch as a failure biases M1 *down* —
toward arm A, the arm I predicted. Amended: unmeasurable launches are reported separately, and M1
is stated as a **band** — pessimistic (all unknowns are failures) to optimistic (all unknowns are
clean) — per note N1. An arm is selected only if **both ends of the band** fall in the same row. If
they straddle a boundary, the corpus is insufficient and the prospective runs decide.

### New defect — revision 1 does not satisfy AC-1

AC-1 requires "a committed pre-registration ... dated and landed **before** any timing is
collected." A GitHub comment is not committed. Worse, `build-lean` reads the **issue body**, not
comments — a scope amendment placed in a comment was the single most expensive error of the
2026-08-22 recalibration, and revision 1 repeats it.

Fix: this criterion is folded into the issue body, and the slice's **first commit** lands it as a
file under `docs/plans/` before any measurement is taken.

### B1 — one table, one procedure, on a pre-fixed attribution rubric

Revision 1's "What would SAVE it" prose and its table selected different arms on the same data.
The prose clause is deleted and replaced by attribution *inside* the table.

Every intervention is classified into exactly one class, by evidence fixed **now**:

| Class | Fires when | Evidence |
| --- | --- | --- |
| **T** transport | the session ended its turn with the milestone unmet — unpushed commits, a dirty tree, or exit 0 on incomplete work — and the scheduler had no signal distinguishing it from success | spawn log ends mid-milestone; gate record shows the milestone unsatisfied; no non-zero rc anywhere |
| **P** classifier | a tool call was denied inside the payload session | a denial line in the spawn log |
| **S** host sleep | the machine slept | a wall-clock gap in log timestamps with no surviving process |
| **X** content | the work itself was wrong — spec wrong, PR closed on design grounds, a legitimate needs-work | tracker/PR record; **not a lane failure and never counted against the scheduler** |
| **U** unattributable | evidence insufficient | — falls into the band |

**M1ᵗ = 1 − (launches with a class-T intervention ÷ total launches).** Classes P, S and X do not
count against the scheduler. U widens the band.

| M1ᵗ band (both ends) | Arm |
| --- | --- |
| >= 0.80 | **C — keep.** The transport is not what is hurting; #617/#638/#639 unblock and the slowness is someone else's ticket. |
| 0.50 – 0.80 | **B — reshape.** |
| < 0.50 | **A — delete the scheduler layer.** |

This is now a single procedure with no escape hatch, and it can acquit the scheduler on exactly the
evidence revision 1 gestured at without a trigger.

### B3 — attention-minutes is the primary metric, and the manual arm gets a protocol

V2 names *"the operator-in-the-middle wait."* That is attention, not wall-clock, and revision 1
omitted it from every decision rule while the ticket's own AC-2 requires recording it. Wall-clock
alone made arm C unreachable by construction — a flow that must run three sessions at a fixed
~9-minute cold start cannot reach parity with an attending expert.

- **Primary:** operator-attention minutes — time the operator is required to be present or acting.
  Arm C is selected on M1ᵗ **and** attention(a) < attention(b). The scheduler may legitimately win
  here while losing on wall-clock; that is the trade it exists to make.
- **Secondary, reported not decisive:** wall-clock launch → first verdict.
- **Manual-arm protocol, fixed now:** clock starts at the first `build-lean` keystroke and stops at
  the verdict record's commit; operator absence between prompts counts as attention only when the
  lane is blocked on the operator; the tickets are the next three `ready-for-dev` of comparable
  size, per the ticket's stated reversible default.

### B4 — the retrospective corpus is an audit, not the measurement

Revision 1 substituted a retrospective corpus for AC-2's prospective three-runs-per-arm and never
measured variant (c) at all, while permitting the table to select arm B — a reshape onto (c) —
without evidence that (c) works.

Stated plainly, as the audit asks: **the 57-log corpus is a retrospective audit of data the author
personally lived** — all of it falls in 2026-08-16 → 08-22 (verified: 13/11/8/22/3 logs across five
days), the week containing the three hand-rescues they performed and wrote up, and spawn logging
does not exist before #548 landed on 08-16. A prediction over that window is retrodiction and is
demoted accordingly: it is recorded as a prior, and carries no evidentiary weight.

The corpus therefore **narrows** the arms; it does not select one. AC-2's prospective runs select.
Variant (c) does not exist, so it is measured as a **time-boxed spike** — the minimum instrument
that replaces exactly the spawn sites a direct gate call can serve — and is shipped only if it wins.
Building the instrument is not "opening with a fix."

### N4 — two things arm A must argue past, not ignore

The audit named the strongest case for keeping the scheduler, and this criterion cannot measure it.
Recorded so arm A cannot win by silence:

1. **Concurrency.** Lanes running while the operator is asleep or elsewhere. Epic #525's whole
   direction dies with the scheduler and nothing here prices that.
2. **Non-author operators.** `run-lean` ships as the marketplace's front door. A manual baseline
   measured on the system's own author bounds nobody else's manual cost.

Arm A must state the case against both explicitly in its PR body, or it does not land.

### Unchanged from revision 1

Corpus and the no-drop rule; the window is now stated explicitly as **all launches since #548
introduced spawn logging, 2026-08-16 → 08-22**, a seven-day recency sample that includes the two
#647-defect days. Arm A remains scoped to the scheduler layer only — `build-lean`, `review-lean`
and `lean-gate.sh` are out of scope under every arm.



---

## Operator amendment — scope split (2026-08-23)

AC-2, AC-3 and AC-5 are **departed** for this slice per `D-1`/`D-2`/`D-3` in
[`docs/plans/second-shift-643-lean.md`](https://github.com/manoldonev/second-shift/pull/651/files);
the remainder is carried by #650.

- **AC-2** (three runs per arm) → #650. Nine lane runs over days; cannot be collected in one
  build session. This slice commits the retrospective audit as its evidence file instead.
- **AC-3** (execute the selected arm) → #650. This slice selects no arm, by the criterion's own
  rule: the retrospective corpus narrows arms, the prospective runs select.
- **AC-5** (front-door truth) → #650. Vacuous here; no front door moves in this slice.

**Sequencing:** the arm decision moved to #650 — #617, #638 and #639 are gated on **#650**, not
on this issue's closure (re-pointed by comment on each). This issue closing on PR #651's merge
does not unblock them.

This slice delivers the instrument plus the retrospective audit only.

Ratified by the operator, 2026-08-23.


