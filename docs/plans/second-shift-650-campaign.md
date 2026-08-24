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
| 2 | a | — | — | — | — | — | — | — | — | — |
| 3 | a | — | — | — | — | — | — | — | — | — |
| 4 | b | #647 | sonnet, single-PR (triplet S, per #652's assignment) | ≤2026-08-23T22:01:20Z (first branch commit; launch keystroke not separately recorded) | 0:43 to first verdict (r1 needs-work 22:44:47Z, per protocol item 3); terminal approve 2026-08-24T09:46:33Z with the 9h53m off-shift gap excluded per #652's shift ruling; PR #657 | 4 | 4 (operator invocations: build, review r1, build re-entry, review r2) | **~20** (operator-reported at row time: launches, handoff/verdict reads, one review redirect, two pasted rulings) | none by rubric (one in-shift operator redirect of a redundant review sweep — arm-b steering, not a failure; filed as #658) | n/a (arm b writes no ledger; invocation count operator-recorded) |
| 5 | b | — | — | — | — | — | — | — | — | n/a |
| 6 | b | — | — | — | — | — | — | — | — | n/a |
| 7 | c | — | — | — | — | — | — | — | — | — |
| 8 | c | — | — | — | — | — | — | — | — | — |
| 9 | c | — | — | — | — | — | — | — | — | — |

### Intervention detail

One entry per intervention, cited. Empty until the runs happen.

| run # | class | what happened | evidence (file, line, timestamp) |
| --- | --- | --- | --- |
| — | — | — | — |

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
