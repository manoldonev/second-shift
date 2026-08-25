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
| 3 | a | #658 | sonnet, single-PR (triplet T3, bound 2026-08-25) | 2026-08-25T14:43:37Z (ledger, launch 1) | 0:20:32 to first verdict (r1 needs-work 15:04:09Z, per protocol item 3); terminal approve 16:31:51Z after **4 rounds across 2 launches**, merged 17:07:20Z, PR #683 | 9 | **2 launches / 9 spawns** (5 on launch 1, which died; 4 on launch 2) | **~6 — RECONSTRUCTED, not measured** (launch keystroke ~1 on row 1's basis; reading the hard stop and handing it off ~3; rescue oversight ~1; verdict read ~1. The rescue itself ran in-session, so this counts the operator's own time, not the repair) | **1 × T** — see the intervention detail | `.claude/pipeline-state/658-lean-launches.tsv` (complete — the scheduler drove every turn) |
| 4 | b | #647 | sonnet, single-PR (triplet S, per #652's assignment) | ≤2026-08-23T22:01:20Z (first branch commit; launch keystroke not separately recorded) | 0:43 to first verdict (r1 needs-work 22:44:47Z, per protocol item 3); terminal approve 2026-08-24T09:46:33Z with the 9h53m off-shift gap excluded per #652's shift ruling; PR #657 | 4 | 4 (operator invocations: build, review r1, build re-entry, review r2) | **~20** (operator-reported at row time: launches, handoff/verdict reads, one review redirect, two pasted rulings) | none by rubric (one in-shift operator redirect of a redundant review sweep — arm-b steering, not a failure; filed as #658) | n/a (arm b writes no ledger; invocation count operator-recorded) |
| 5 | b | #642 | opus, single-PR (triplet O, per #652's assignment) | ≤2026-08-24T14:17:40Z (first branch commit; launch keystroke not separately recorded) | 1:54 to first verdict (r1 needs-work 16:11:43Z, per protocol item 3); terminal approve 18:23:09Z, total ~4:05, 3 rounds, PR #660 | 6 | 6 (operator invocations: build, review r1, re-entry, review r2, re-entry, review r3) | **~35** (operator-reported at row time: launches, three verdict/handoff reads, AC-6 ruling relays) | none by rubric (first build session ended post-handoff pre-ruling — operator-managed lifecycle, no work lost, ruling took the tracker path; two operator body amendments to #642 re-based AC-6 mid-run, both dated and direction-noted) | n/a (arm b writes no ledger; invocation count operator-recorded) |
| 6 | b | #661 | opus, single-PR (triplet T3, bound 2026-08-25 on #652) | ≤2026-08-25T08:53:34Z (first branch commit; launch keystroke not separately recorded) | 1:09:34 to first verdict (r1 **approve** 10:03:08Z — round 1 was terminal, per protocol item 3); merged 10:09:51Z, PR #679 | 2 | 2 (operator invocations: build, review r1) | **~5** (operator-reported at row time: two launches, handoff read, verdict read — a self-reported estimate, not instrumented) | none by rubric (one non-blocking reviewer warning — a false clause in `check-emit-deadline.sh`'s cited-evidence comment; the enrollment set it guards is still correct, both kill directions probed, so nothing shipped depends on it) | n/a (arm b writes no ledger; invocation count operator-recorded) |
| 7 | c | #644 | opus, single-PR (triplet O, per #652's assignment) | 2026-08-24T19:20:02Z (ledger) | 1:20:48 to first verdict (r1 needs-work 20:40:50Z, per protocol item 3); approve 21:29:48Z, merged 21:36:38Z, 2 rounds, PR #673 | 4 | 6 attended invocations (4 turn handoffs rc=9 + 2 post-merge preflight-rejections rc=2) | **~25** (operator-reported at row time: handoff reads, 4 session launches, two verdict reads) | none by rubric; one arm-c structural finding — the arm CANNOT write its own `approved` terminal: post-merge re-entry preflight-rejects on the closed ticket before reaching close-out (ledger rows 21:37:04Z/21:37:46Z), completion proven by tracker instead | `.claude/pipeline-state/644-lean-launches.tsv` (per-invocation launches; no approved terminal by construction — see intervention detail) |
| 8 | c | #656 | **opus — the ticket's `sonnet` label could not bind.** An attended session inherits whatever model it is running in, and arm c has no `claude -p` transport to size; the scheduler still requires `--build-model` and stamps it, so the ledger records `sonnet` for a build that ran on opus. Arm-c structural, same class as #676. Single-PR (triplet S, per #652's assignment) | 2026-08-25T11:04:13Z (ledger, launch 1) | 0:40:03 to first verdict (r1 needs-work 11:44:16Z, per protocol item 3); terminal approve 13:45:05Z after **4 rounds**, merged 14:06:22Z, PR #681 | 8 | **3 orchestrator invocations recorded; 8 operator sessions (4 build, 4 review).** Rounds 2–4 advanced without re-invoking the orchestrator, which writes no ledger row, so the recorded count is a FLOOR and is **not comparable with row 7's 6** | **~45 — RECONSTRUCTED, not measured** (derived from 8 sessions against row 7's ~25 at 4 sessions; operator confirmation owed at scoring, as for row 2) | none by rubric; three structural findings — the ledger undercount in the previous cell, the unbindable build-model label, and a round-2 review record that asserted a wrong count which the build shipped and round 3 then blocked on | `.claude/pipeline-state/656-lean-launches.tsv` (undercounts — see the invocations cell) |
| 9 | c | #668 | **opus — MEASURED, not inferred.** The label and the ledger both say `sonnet` and always would: an attended session inherits whatever model it runs in and arm c has no `claude -p` transport to size, so the scheduler stamps `--build-model` regardless (rows 7 and 8, same gap). What settles it is PR #685's own cost block, which derives `claude-opus-5` from OTel `claude_code.cost.usage` time-fenced to the build session (17:27–17:42Z, 1 session). **Arm c's three rows are therefore all opus and internally consistent** — and the cost block is a general post-hoc settlement for the unbindable label, not a one-off. Single-PR (triplet T3, bound 2026-08-25) | 2026-08-25T17:27:31Z (`668-lean-launches.tsv`, the attended-build launch; a `--dry-run` preview at 17:27:24Z preceded it) | 0:31:07 to first verdict (r1 needs-work 18:01:43Z, per protocol item 3); terminal approve 20:36:23Z at **round 2**, merged 20:45:48Z, PR #685. Contains a 2h18m gap (18:18:20Z→20:36:23Z) whose off-shift status is the operator's to confirm; #652's standing ruling already excludes off-shift time for every arm, so confirming it needs no new decision — and the attention cell is not wall-clock-derived, so the gap does not enter it either way | 4 | **3 orchestrator launches recorded** (`668-lean-launches.tsv`): one `--dry-run` rc=0 plus two attended handoffs rc=9 (build 17:27:33Z, review 17:43:36Z). **The ledger stops at the review handoff** — rounds r1-fix and r2 were driven without re-invoking the orchestrator and left no row — so this is a floor, not a count, and is NOT comparable with row 7's 6 | **~25 — RECONSTRUCTED BY ANALOGY, not measured.** Row 7 is the same arm at the same round count and cost ~25. First-hand basis covers only the build half (2 operator turns — one launch instruction, one handoff read — 17:27:31→17:43:36Z); the review-side turns are the analogy. Operator confirmation owed at scoring | none by rubric; one structural gap recorded in the intervention detail | `.claude/pipeline-state/668-lean-launches.tsv` (6 rows), reproduced verbatim in this PR's body so it does not strand |

### Intervention detail

One entry per intervention, cited. Empty until the runs happen.

| run # | class | what happened | evidence (file, line, timestamp) |
| --- | --- | --- | --- |
| 2 | U (evidence insufficient) | launch 1 preflight-rejected rc=2 thirty seconds after launch; the terminal text was not captured, so the cause is unattributable by the rubric's evidence rule. Candidate, named not assigned: residue of #644's never-executed close-out (the #676 defect) — #644's final ledger rows show its close-out was preflight-rejected 5 minutes earlier on the same machine. Operator re-launched at 21:44:24Z; launch 2 ran clean to approved. U widens the band per the criterion. | `637-lean-launches.tsv` rows 1–2 (21:42:15Z, 21:42:45Z) |
| 3 | T (attributable) | Launch 1's round-3 BUILD spawn produced the edit r2's blocker required, then **exited 0 with it uncommitted**: its transcript ends on the session saying it would wait for an armed `Monitor` to notify it, and under `claude -p` turn end IS process exit, so nothing was collected. `build-lean/SKILL.md:41` states that rule verbatim, naming an armed `Monitor` as "abandoned, not deferred" — the rule was present and not followed. The gate's inflight arm hard-stopped the lane (`build-inflight rc=1`) rather than letting a review read a remote head missing the fix, so nothing escaped. The operator committed the orphaned work from the lane worktree and re-launched; launch 2 ran clean to approved. Classed **T, not U**: unlike run 2, the terminal text, the ledger row and the recovery commit were all captured, so the cause is attributable. | `658-lean-spawn-20260825T144337Z-25616-5-build.log` final line; `658-lean-launches.tsv` terminal `build-inflight rc=1` at 2026-08-25T15:37:02Z; recovery commit `e266d678` |
| 7 | none (structural, not an intervention) | `--attended` cannot reach its own close-out: the post-merge re-invocation preflight-rejects on the closed ticket (`FAIL ticket: #644 is CLOSED`) before the gate's m5 merged-PR acceptance is consulted, so the ledger can never carry an `approved` terminal for arm c. Run completion is proven by the tracker (PR #673 merged 21:36:38Z, approve record `f6e670f`). Filed as a spike defect. | `644-lean-launches.tsv` terminals `preflight-rejected rc=2` at 2026-08-24T21:37:04Z and 21:37:46Z |
| 9 | none (structural, not an intervention) | **The ledger cannot count this run's rounds.** `668-lean-launches.tsv` records three launches and stops at the review handoff (17:43:36Z): rounds r1-fix and r2 were driven by calling `build-lean`/`review-lean` directly, and a bypassed round writes no ledger row at all. The invocation cell is therefore a floor rather than a count, and is not comparable with row 7's 6 — the same class row 8 hit. Arm c's OTHER structural gap, the unbindable `--build-model` label, is **not** an evidence gap on this row: PR #685's cost block names `claude-opus-5` from OTel telemetry, which settles the model after the fact here and could settle rows 7 and 8 the same way. | `668-lean-launches.tsv` (6 rows; terminals `dry-run rc=0`, `attended-build-turn rc=9`, `attended-review-turn rc=9`); PR #685 description, Pipeline Cost block |

## Scoring

**Do not fill this in before all nine rows exist.** Partial scoring is the failure the band rule
was written to prevent: an arm selected on four runs is an arm selected on the corpus the author
happened to have.

`M1ᵗ` is computed per the pre-registration's `B1` — `1 − (launches with a class-T intervention ÷
total launches)` — over arm `a`'s runs, stated as a band from pessimistic (every `U` is a failure)
to optimistic (every `U` is clean).

| quantity | value |
| --- | --- |
| `M1ᵗ` band, pessimistic end | **0.60** — every `U` a failure: 1 − 2/5 |
| `M1ᵗ` band, optimistic end | **0.80** — every `U` clean: 1 − 1/5 |
| attention(a), mean over runs 1–3 | **~3.3** (1, ~3, ~6 — two reconstructed) |
| attention(b), mean over runs 4–6 | **~20** (5, 20, 35) |
| attention(c), mean over runs 7–9 | **~32** (~25, ~45, ~25 — two reconstructed) |
| **arm selected by revision 4's table** | **NO ARM — the band straddles the `0.80` boundary.** |

Launch enumeration, from the ledgers per protocol item 6 (arm `a` only — `b` runs no scheduler and
`c` has no `claude -p` transport, so neither can contribute to a transport metric):

| row | ticket | launches | intervention |
| --- | --- | --- | --- |
| 1 | #636 | 1 | none |
| 2 | #637 | 2 | 1 × `U` — launch 1, `preflight-rejected rc=2` at `21:42:45Z` |
| 3 | #658 | 2 | 1 × `T` — launch 1's round-3 BUILD spawn exited 0 with the fix uncommitted |
| | | **5** | `T` = 1, `U` = 1 |

**Applying revision 4's table to each end.** The optimistic end `0.80` lands in the `M1ᵗ >= 0.80`
row, and `attention(a) < attention(b)` holds (~3.3 against ~20, an ordering no reconstructed cell in
this corpus can flip), so that end selects **C — keep**. The pessimistic end `0.60` lands in
`0.50 <= M1ᵗ < 0.80`, which selects **B — reshape**. Two different rows: the band straddles, and the
answer is **no arm**.

**The whole corpus turns on one launch.** Collapse row 2's single `U` and the band collapses to a
point: clean → `M1ᵗ = 0.80` exactly → **C** (revision 4's `R4-1` made that endpoint single-valued
for precisely this case); a `T` → `0.60` → **B**. Either way an arm is selected. It is not
recoverable — the audit ledger records tool calls and not their output, and #637's spawn logs exist
only for launch 2 because launch 1 never spawned anything. The `U` is permanent.

**What decides it, quantified.** Band width is `U ÷ total launches`. For both ends to reach the
`>= 0.80` row: `1 − 2/(5+n) >= 0.80`, so **n = 5 further clean arm-`a` launches**. One further
class-`T` moves it the other way. This costs no campaign: every ordinary `run-lean` invocation *is*
an arm-`a` launch and the ledger already records its terminal, so the exit condition accrues from
normal work rather than from measurement.

**Read this before designing another campaign.** The decision rule needs exactly two inputs:
`M1ᵗ`, which the launch ledger produces for free, and an *ordering* between attention(a) and
attention(b). It never compares `b` against `c`, and no row of the table can select arm `c` at all —
the outcomes are keep, reshape, or delete **the scheduler**. Arm `c`'s three runs (rows 7–9, ~95
operator-minutes, the corpus's most expensive third) therefore carry zero decision weight, and the
`b`-vs-`c` separability question that consumed the late campaign was never a question the criterion
asked. The metric everyone worried about was used as a boolean; the metric that actually decided the
outcome was free, automatic, and lost to a single uncaptured terminal line.

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
