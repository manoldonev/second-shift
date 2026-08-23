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

---

## Revision 3 — amendments made AFTER the numbers were read

**Dated 2026-08-23, after scoring.** Revision 2's text above is unedited, and revision 1 stays up
unedited on the issue. This section exists because round 1 of the independent review on PR 651
returned four defects that bind the criterion itself rather than the audit, and #650 is instructed
to measure against this file — so a defect left here propagates into the campaign that selects the
arm.

**These amendments cannot be trusted the way revision 2 can, and the reason is structural:** they
were written by an author who has now seen the result. Each one therefore states which arm it
favours. Read them in that light, and note that none of them can move this slice's outcome — no arm
is selected here under any revision.

### R3-1 — the prior belongs in the committed file (round-1 blocker B-4)

Revision 2 says at `:108` that the prediction "is recorded as a prior" and then records none. It
lives only in [revision 1's comment](https://github.com/manoldonev/second-shift/issues/643#issuecomment-5385766947),
which is the exact container revision 2 condemns two sections earlier — "a scope amendment placed in
a comment was the single most expensive error of the 2026-08-22 recalibration." Carried here
verbatim, under revision 1's own heading:

> ### Prediction, recorded now
>
> M1 lands between 0.30 and 0.50 — arm A, or the top of arm B. **If it comes back materially higher,
> that is evidence against the framing above, and the arm the table selects beats the prediction.**

Provenance, checkable: comment `5385766947` was created `2026-08-23T11:31:08Z`; this branch's first
commit `f573ee3` is `2026-08-23T11:51:08Z`. The prediction precedes the branch by 20 minutes, and
precedes the scoring commit `ecc77e5` (`11:55:52Z`) by 24. **Direction: neutral** — transcription
only. The audit's earlier gloss of this quote dropped "or the top of arm B" and is corrected there.

### R3-2 — the decision table is made total (round-1 blocker B-3)

Revision 2's B1 table selects arm C on `M1ᵗ >= 0.80` alone, while its B3 section adds "Arm C is
selected on `M1ᵗ` **and** attention(a) < attention(b)." A run where `M1ᵗ` clears 0.80 and the
attention comparison fails is selected by the table and refused by the prose, and **no arm is
assigned** — which is revision 1's defect, the one B1 was written to remove, reintroduced by the fix
for it. Revision 1 had no such hole: its table carried the conjunct and a `>= 0.50, but either
condition fails → B` catch row.

The conjunct moves back into the table, which is now total over its domain:

| `M1ᵗ` band (both ends) | attention | Arm |
| --- | --- | --- |
| >= 0.80 | attention(a) < attention(b) | **C — keep.** #617/#638/#639 unblock and the slowness is someone else's ticket. |
| >= 0.80 | attention(a) >= attention(b) | **B — reshape.** The transport holds but the operator still pays; that is revision 1's "either condition fails" row. |
| 0.50 – 0.80 | any | **B — reshape.** |
| < 0.50 | any | **A — delete the scheduler layer.** |
| the band straddles a row boundary | any | **no arm** — the corpus is insufficient and the prospective runs decide (revision 2's band rule, unchanged). |

Prose adds nothing to this table; B3's sentence is superseded by its top two rows.

**Direction: this favours the arm the author predicted.** It makes arm C strictly harder to reach —
`M1ᵗ` alone no longer selects it — and the author predicted arm A. It is adopted anyway because it
restores a rule revision 1 fixed *before* any data existed, and because attention is unmeasured in
this slice, so it cannot change what lands here. #650 measures attention and inherits the table.

### R3-3 — the launch-enumeration sources are corrected, and the ordering clause was violated

Revision 2's B2 consequence reads: "the launch enumeration must come from sources outside the
corpus (the operating record, `cost-log.jsonl`, tracker timestamps), **be committed before
scoring**, and mark unrecoverable launches explicitly." Two corrections, both against this session:

1. **`cost-log.jsonl` cannot serve, and this is checkable rather than argued.** The lean lane writes
   no row to it by design. Empirically: the file's last row is `2026-07-31T21:40:35Z`, three weeks
   before the corpus window opens on 08-16, and none of the 15 corpus issues appears in it. Naming
   a source without opening it is the same error class as R3-1. The source list is amended to **the
   gate's progress records and tracker timestamps**; `cost-log.jsonl` is struck.
2. **"Committed before scoring" was not satisfied, and cannot now be.** No enumeration was committed
   before `ecc77e5`. It is committed late instead, in the audit's *Launch enumeration* section, and
   the slice records the violation as a departure rather than restating the clause as met. A
   pre-registration whose procedural steps are quietly dropped when they turn out to be
   inconvenient is worth nothing, so it is recorded as broken.

**Direction: neutral to the arm; adverse to this session's compliance record.** That is the honest
place for it to land.

### R3-4 — the corpus is its rule, not its count (round-1 blocker B-1)

`D-4` fixes the corpus as "**all** launches since #548 introduced spawn logging: 2026-08-16 → 08-22"
and then states a count of 57. The count was a **miscount of that rule**, not a second definition of
it: a top-level glob of the state directory returns 57 spawn logs, a recursive `find` returns 63,
and the six-log difference is one complete archived launch of #641 that satisfies the rule in full.
The rule is unchanged and the no-drop rule is unchanged; the enumeration is corrected to **63**.

Correcting an enumeration toward *more* data is not re-opening a fixed corpus — dropping members
would be. The audit restates every band on 63 and the arm does not move.

**One statement in revision 2 above is falsified by the recovered set and is left standing on
purpose.** The B2 correction says "the earlier launches' transcripts are gone", citing #641's
four-launches-behind-three-logs as the illustration. One of those four survives in full, in the
archive directory the corpus was drawn from. The *mechanism* revision 2 describes is real and
unchanged — `orchestrate-lean.sh` does truncate, and `SPAWN_N` does reset — but the claim that no
launch survives it is too strong: one did, because a human copied it aside before the next launch
ran. The audit's limitation 1 carries the corrected version, and the recovered launch is the only
end-to-end-observable launch in the entire corpus.

**Direction: this favours the arm the author predicted**, slightly. The recovered set adds one
class-T spawn and five clean, taking `M1ᵗ` from 0.88–0.91 down to 0.873–0.905. It stays in the keep
row, so nothing turns on it — but it moves toward arm A, which is why it is stated as a number
rather than waved through.

## Revision 4 — amendment made AFTER round 2 of the independent review

**Dated 2026-08-23, after scoring.** Appended, not edited in: revision 3's text above is unchanged,
revision 2's is unchanged, and revision 1 stays up unedited on the issue. The append discipline is
the point — every revision of this criterion is readable in the order it was written, so a bar that
moves is visible rather than rewritten away. As with revision 3, this amendment was written by an
author who has seen the result, so it states which arm it favours.

### R4-1 — the decision table is single-valued at `M1ᵗ = 0.80` (round-2 blocker B-9)

`R3-2` rebuilt the table to close round 1's B-3 and asserted it "is now total over its domain". It
is total. It is not **single-valued**: the `>= 0.80` rows and the `0.50 – 0.80` row both claim the
endpoint, so a run at exactly `M1ᵗ = 0.80` with `attention(a) < attention(b)` is selected as **C** by
row 1 and as **B** by row 3. Totality was checked over the *gaps* and not over the *boundary points*,
which is the one place a band table fails silently.

The overlap is inherited from revision 2 (`>= 0.80` / `0.50 – 0.80`) rather than introduced by
revision 3 — but revision 3 is the amendment written to remove exactly this class of hole, and it
re-published the boundary unchanged while asserting the property. `0.80` is not a measure-zero
curiosity on a nine-run campaign: it is `4/5`, `8/10`, `12/15`.

**The B band becomes half-open.** `0.50 <= M1ᵗ < 0.80`, so exactly `0.80` falls to the `>= 0.80`
rows. That is the only reading consistent with the criterion's own history: `>= 0.80` has appeared,
inclusive and unchanged, in every revision since revision 1, while the B row has been written as a
range with no stated endpoint convention. The `< 0.50` row is already half-open in the same
direction, so the table now reads consistently across both boundaries.

| `M1ᵗ` band (both ends) | attention | Arm |
| --- | --- | --- |
| `M1ᵗ >= 0.80` | attention(a) < attention(b) | **C — keep.** #617/#638/#639 unblock and the slowness is someone else's ticket. |
| `M1ᵗ >= 0.80` | attention(a) >= attention(b) | **B — reshape.** The transport holds but the operator still pays; that is revision 1's "either condition fails" row. |
| `0.50 <= M1ᵗ < 0.80` | any | **B — reshape.** |
| `M1ᵗ < 0.50` | any | **A — delete the scheduler layer.** |
| the band straddles a row boundary | any | **no arm** — the corpus is insufficient and the prospective runs decide (revision 2's band rule, unchanged). |

The three bands are now pairwise disjoint and cover `[0, 1]`, so the table is total **and**
single-valued. This supersedes `R3-2`'s table; `R3-2`'s reasoning for restoring the conjunct is
unchanged and still governs.

**Direction: this favours the scheduler.** At exactly `0.80` the choice was previously ambiguous
between B and C; it is now C whenever attention favours the scheduler, which is the keep arm — and
the author predicted arm A. It is adopted anyway because leaving the endpoint two-valued hands the
selection back to a post-hoc judgement call at the one value most likely to be hit, which is the
precise discretion the pre-registration exists to remove. Nothing in this slice turns on it: no arm
is selected here, attention is unmeasured here, and this corpus's band (`0.873–0.905`) does not
touch the endpoint. #650 inherits this table, not `R3-2`'s.
