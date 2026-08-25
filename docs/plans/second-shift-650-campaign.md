# #650 — the drive-mode campaign's evidence file

Ticket: https://github.com/manoldonev/second-shift/issues/650
Criterion (frozen, revisions 1–5): [`second-shift-643-preregistration.md`](second-shift-643-preregistration.md)
Retrospective audit (phase 1): [`second-shift-643-audit.md`](second-shift-643-audit.md)

**This file is a SKELETON, and it is committed empty on purpose.** Every column below is fixed
before the first run is timed, because a schema decided after the first run is a schema fitted to
it — the same failure the pre-registration exists to prevent, one level down. The nine runs happen
across days and outside the session that built the instruments; each fills in one row here and
commits it.

**Nothing in this file selects an arm.** Scoring happens once all nine rows exist, against the
criterion as frozen — restated here **by reference only**. A copy of the rubric in this file would
be a second authority that could drift from the first, so if the two ever appear to disagree, the
pre-registration is right and this file is wrong.

## What is being measured

Three drive-modes, three runs each, on comparable tickets:

| arm | drive-mode | what it is |
| --- | --- | --- |
| **a** | `run-lean` as it stands | `orchestrate-lean.sh <issue> --build-model <m>`. Spawns BUILD and REVIEW as `claude -p` children; every other check is already a direct gate call. |
| **b** | manual two-terminal | `/dev-pipeline:build-lean <issue>` and `/dev-pipeline:review-lean <pr>` invoked by the operator in their own sessions, with no scheduler at all. |
| **c** | the attended drive-mode | `orchestrate-lean.sh <issue> --build-model <m> --attended`. Every check a direct gate call, no `claude -p` transport, each invocation advancing the lane by one operator turn. Landed by this ticket's PR as a time-boxed spike; it is an instrument, and it ships only if it wins. |

**The primary metric is operator-attention minutes** (`B3`), not wall-clock. Wall-clock is recorded
and reported, and it is not decisive: a scheduler that costs more wall-clock and less attention is
making exactly the trade it exists to make.

## Protocol, fixed before the first run

1. **Ticket selection.** The next three `ready-for-dev` tickets of comparable size at the time each
   run starts, per the pre-registration's stated reversible default. Sizes and the basis for calling
   them comparable go in the row.
2. **The attention clock** (`B3`, unchanged): it starts at the first keystroke of the run's first
   command and stops when the verdict record is committed. Operator absence between prompts counts
   as attention **only when the lane is blocked on the operator**. Under arm `c` every handover is
   blocked-on-operator by construction; under arm `a` the between-phase gaps are not.
3. **Wall-clock** is launch → first verdict record, secondary and reported.
4. **Sessions** counts model sessions started, of any role, including continuations and re-reviews.
5. **Interventions** are classified by the pre-registration's rubric — `T` transport, `P` classifier,
   `S` host sleep, `X` content, `I` infrastructure, `M` mis-dispatch, `U` unattributable — and each
   one cites its evidence. A classification with no citable evidence is `U` and widens the band; it
   is never quietly assigned.
6. **Launch enumeration is now recoverable and must be taken from the ledger**, not reconstructed:
   `.claude/pipeline-state/<issue>-lean-launches.tsv` carries one `launch` row per launch, one
   `spawn` row per spawn, and one `terminal` row per outcome. This is what #643's `B2` correction
   could not have — its corpus predates the ledger, and its launch unit was destroyed by the
   truncation that ticket's `AC-1` removed. **A run whose ledger is missing is not scored; it is
   re-run.** Arm `b` produces no ledger by construction (no scheduler runs), so its launch count is
   its invocation count, recorded by the operator at the time and not reconstructed afterwards.

## Run rows

One row per run. `—` means not yet recorded; a committed row is a run that happened.

| # | arm | ticket | size | started (UTC) | wall-clock | sessions | launches | **attention (min)** | interventions (class × n) | ledger path |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | a | #636 | opus, single-PR (triplet O, per #652's assignment) | 2026-08-23T18:58:06Z | 0:59:00 to first verdict (r1 needs-work, per protocol item 3); terminal approve 1:30:20, PR #654 | 4 | 1 | **1** (launch keystrokes; zero prompts, zero rescues) | none | `.claude/pipeline-state/636-lean-launches.tsv` |
| 2 | a | #637 | sonnet, single-PR (triplet S, per #652's assignment) | 2026-08-24T21:42:15Z (ledger, launch 1) | 0:22:41 to first verdict (r1 needs-work 22:04:56Z, per protocol item 3); terminal approve 22:37:09Z, 2 rounds, PR #677 | 4 | 2 (launch 1 preflight-rejected rc=2 at 21:42:45Z; launch 2 at 21:44:24Z ran to approved) | **~3** (reconstructed: launch, one re-launch after the rejection, verdict relay — flagged for operator confirmation at scoring) | 1 × U on launch 1 (see intervention detail) | `.claude/pipeline-state/637-lean-launches.tsv` — contents reproduced verbatim in row PR #678's body for cross-machine scoring |
| 3 | a | — | — | — | — | — | — | — | — | — |
| 4 | b | #647 | sonnet, single-PR (triplet S, per #652's assignment) | ≤2026-08-23T22:01:20Z (first branch commit; launch keystroke not separately recorded) | 0:43 to first verdict (r1 needs-work 22:44:47Z, per protocol item 3); terminal approve 2026-08-24T09:46:33Z with the 9h53m off-shift gap excluded per #652's shift ruling; PR #657 | 4 | 4 (operator invocations: build, review r1, build re-entry, review r2) | **~20** (operator-reported at row time: launches, handoff/verdict reads, one review redirect, two pasted rulings) | none by rubric (one in-shift operator redirect of a redundant review sweep — arm-b steering, not a failure; filed as #658) | n/a (arm b writes no ledger; invocation count operator-recorded) |
| 5 | b | #642 | opus, single-PR (triplet O, per #652's assignment) | ≤2026-08-24T14:17:40Z (first branch commit; launch keystroke not separately recorded) | 1:54 to first verdict (r1 needs-work 16:11:43Z, per protocol item 3); terminal approve 18:23:09Z, total ~4:05, 3 rounds, PR #660 | 6 | 6 (operator invocations: build, review r1, re-entry, review r2, re-entry, review r3) | **~35** (operator-reported at row time: launches, three verdict/handoff reads, AC-6 ruling relays) | none by rubric (first build session ended post-handoff pre-ruling — operator-managed lifecycle, no work lost, ruling took the tracker path; two operator body amendments to #642 re-based AC-6 mid-run, both dated and direction-noted) | n/a (arm b writes no ledger; invocation count operator-recorded) |
| 6 | b | #661 | opus, single-PR (triplet T3, bound 2026-08-25 on #652) | ≤2026-08-25T08:53:34Z (first branch commit; launch keystroke not separately recorded) | 1:09:34 to first verdict (r1 **approve** 10:03:08Z — round 1 was terminal, per protocol item 3); merged 10:09:51Z, PR #679 | 2 | 2 (operator invocations: build, review r1) | **~5** (operator-reported at row time: two launches, handoff read, verdict read — a self-reported estimate, not instrumented) | none by rubric (one non-blocking reviewer warning — a false clause in `check-emit-deadline.sh`'s cited-evidence comment; the enrollment set it guards is still correct, both kill directions probed, so nothing shipped depends on it) | n/a (arm b writes no ledger; invocation count operator-recorded) |
| 7 | c | #644 | opus, single-PR (triplet O, per #652's assignment) | 2026-08-24T19:20:02Z (ledger) | 1:20:48 to first verdict (r1 needs-work 20:40:50Z, per protocol item 3); approve 21:29:48Z, merged 21:36:38Z, 2 rounds, PR #673 | 4 | 6 attended invocations (4 turn handoffs rc=9 + 2 post-merge preflight-rejections rc=2) | **~25** (operator-reported at row time: handoff reads, 4 session launches, two verdict reads) | none by rubric; one arm-c structural finding — the arm CANNOT write its own `approved` terminal: post-merge re-entry preflight-rejects on the closed ticket before reaching close-out (ledger rows 21:37:04Z/21:37:46Z), completion proven by tracker instead | `.claude/pipeline-state/644-lean-launches.tsv` (per-invocation launches; no approved terminal by construction — see intervention detail) |
| 8 | c | — | — | — | — | — | — | — | — | — |
| 9 | c | — | — | — | — | — | — | — | — | — |

### Intervention detail

One entry per intervention, cited. Empty until the runs happen.

| run # | class | what happened | evidence (file, line, timestamp) |
| --- | --- | --- | --- |
| 2 | U (evidence insufficient) | launch 1 preflight-rejected rc=2 thirty seconds after launch; the terminal text was not captured, so the cause is unattributable by the rubric's evidence rule. Candidate, named not assigned: residue of #644's never-executed close-out (the #676 defect) — #644's final ledger rows show its close-out was preflight-rejected 5 minutes earlier on the same machine. Operator re-launched at 21:44:24Z; launch 2 ran clean to approved. U widens the band per the criterion. | `637-lean-launches.tsv` rows 1–2 (21:42:15Z, 21:42:45Z) |
| 7 | none (structural, not an intervention) | `--attended` cannot reach its own close-out: the post-merge re-invocation preflight-rejects on the closed ticket (`FAIL ticket: #644 is CLOSED`) before the gate's m5 merged-PR acceptance is consulted, so the ledger can never carry an `approved` terminal for arm c. Run completion is proven by the tracker (PR #673 merged 21:36:38Z, approve record `f6e670f`). Filed as a spike defect. | `644-lean-launches.tsv` terminals `preflight-rejected rc=2` at 2026-08-24T21:37:04Z and 21:37:46Z |

## Scoring

**Do not fill this in before all nine rows exist.** Partial scoring is the failure the band rule
was written to prevent: an arm selected on four runs is an arm selected on the corpus the author
happened to have.

`M1ᵗ` is computed per the pre-registration's `B1` — `1 − (launches with a class-T intervention ÷
total launches)` — over arm `a`'s runs, stated as a band from pessimistic (every `U` is a failure)
to optimistic (every `U` is clean).

| quantity | value |
| --- | --- |
| `M1ᵗ` band, pessimistic end | — |
| `M1ᵗ` band, optimistic end | — |
| attention(a), mean over runs 1–3 | — |
| attention(b), mean over runs 4–6 | — |
| attention(c), mean over runs 7–9 | — |
| **arm selected by revision 4's table** | — |

Revision 4's table is the one that applies (`R4-1` supersedes `R3-2`'s), and it is total and
single-valued over `[0, 1]`. If the band straddles a row boundary the answer is **no arm**, and
that is a result, not a failure to reach one.

## What this campaign still cannot price

Carried forward from the criterion's `N4` so no arm wins by silence, and repeated here because
these two are the reason a number is not the whole decision:

- **Concurrency.** Lanes running while the operator is asleep or elsewhere. Epic #525's direction
  dies with the scheduler, and nothing above prices it.
- **Non-author operators.** `run-lean` ships as the marketplace's front door. Every run below is
  measured on the system's own author, whose manual baseline bounds nobody else's.

An arm A result must argue past both explicitly in its PR body, or it does not land.
