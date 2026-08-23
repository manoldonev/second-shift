# #643 — pre-registered decision criterion

**Dated 2026-08-23. Landed before any timing was collected — that ordering is AC-1.**

This file is the pre-registration `#643` AC-1 requires. It is revision 2: [revision 1]
(https://github.com/manoldonev/second-shift/issues/643#issuecomment-5385766947) was audited by
an independent session, four blockers were returned and accepted, and the criterion amended.
Revision 1 stays up unedited on the issue so the movement of the bar is visible rather than
rewritten away. The amendments make the criterion **harder on the delete arm**, which is what
an audit of a motivated author should produce.

Verbatim copy of the issue body section of the same name. The issue is the tracker-side
record; this file is the committed one.

---

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
