# #643 — the scheduler's only signal is an exit code its transport cannot produce

Issue: https://github.com/manoldonev/second-shift/issues/643
Pre-registration: [`second-shift-643-preregistration.md`](second-shift-643-preregistration.md)

## What this slice is, and what it is not

**#643 as filed is not a slice.** It bundles three things with different costs and different
completion conditions:

1. a **measurement instrument** — the pre-registered criterion, the attribution rubric, the corpus;
2. a **measurement campaign** — AC-2's "at least three runs per arm on comparable tickets", which
   is nine lane runs across three drive-modes, one of which (variant `c`) does not exist yet;
3. an **execution** — AC-3's "the selected arm is executed in this slice", up to and including
   deleting 2,669 lines of scheduler.

(1) is a session. (2) is calendar work measured in days, and cannot be collected inside one
`build-lean` run. (3) cannot begin until (2) reports. Carrying all three under one PR would mean
either a PR that stays open for days, or — the failure this ticket exists to attack — an arm
selected on evidence the criterion says is insufficient to select it.

**This slice delivers (1), plus the retrospective audit the corpus can support.** (2) and (3) are
filed as a follow-up. The re-scope is recorded as departures `D-1`..`D-3` below, and is the
operator's call, not this session's: see the Decision Ledger for provenance.

The retrospective audit **narrows** the arms; per the pre-registration it does not select one.
That is deliberate and is not a hedge — the whole corpus is the author's own week (2026-08-16 →
08-22, the window in which spawn logging exists at all), so a conclusion drawn from it alone would
be retrodiction dressed as measurement.

## Acceptance Criteria

- **AC-1** — a committed pre-registration naming the criterion and the three arms, dated, landed
  **before** any timing is collected. Satisfied by `second-shift-643-preregistration.md` as this
  branch's first commit; the ordering is checkable from `git log --reverse`.
- **AC-2** — *departed, see `D-1`; unit corrected, see `D-8`.* This slice records the retrospective
  audit in a committed evidence file: every **spawn** in the fixed corpus classified by the
  pre-registration's T/P/S/X/U rubric, with the resulting `M1ᵗ` stated as a band
  (pessimistic/optimistic). The **launch** unit is separately enumerated from outside the corpus,
  with the unrecoverable launches named — the criterion's B2 consequence, discharged late per `D-7`.
  The prospective per-arm runs move to the follow-up.
- **AC-3** — *departed, see `D-2`.* No arm is selected or executed here. The follow-up owns both.
- **AC-4** — `bash tools/run-selftests.sh --full --exclude tools/install-topology-selftest.sh` is
  green, and no orphaned selftest survives its subject.
- **AC-5** — *departed, see `D-3`.* The lane's front door does not move in this slice, so no
  `docs/` or `plugin.json` front-door change is due. Reinstated in the follow-up, which is where a
  front door can actually move.
- **AC-6** — `Changelog:` trailer present.
- **AC-7** (added by this slice) — the follow-up carrying AC-2's campaign and AC-3's execution is
  **filed and linked from this PR** before handoff — **#650**. A re-scope that does not file its remainder is
  a scope cut, not a split.
- **AC-8** (added by this slice; unit corrected, see `D-8`) — the evidence file records, for each
  corpus **spawn**, the evidence that produced its class, not merely the class. A classification with
  no citable evidence is scored `U` and widens the band; it is never quietly assigned. All 63 rows
  carry evidence.

## Decision Ledger

| id | subject | resolution | provenance |
| --- | --- | --- | --- |
| D-1 | AC-2's "at least three runs per arm" | DEPARTURE — the campaign is nine lane runs over days and cannot be collected in one build session; variant `c` does not exist and must be built as a time-boxed spike first. This slice delivers the retrospective audit only; the campaign moves to the follow-up required by AC-7. | user-answered |
| D-2 | AC-3's "the selected arm is executed in this slice" | DEPARTURE — the pre-registration states the retrospective corpus narrows arms and the prospective runs select. Selecting here would be the precise failure the criterion was written to prevent. Moves to the follow-up. | user-answered |
| D-3 | AC-5's front-door truth | DEPARTURE — conditional on an arm landing. No front door moves in this slice, so the criterion is vacuous here; reinstated in the follow-up. | user-answered |
| D-4 | the corpus window | Fixed at all launches since #548 introduced spawn logging: 2026-08-16 → 08-22, **63** spawn logs across 15 issues. Stated in the pre-registration and not re-openable after scoring begins. The rule is what is fixed; the count first reported (57) was a miscount of it — a top-level glob missed one complete archived launch of #641, which the rule plainly includes. Corrected upward per revision 3's `R3-4`; correcting an enumeration toward more data is not re-opening a corpus, and the arm does not move. | codebase-derived |
| D-5 | a spawn died of an API 500, which the rubric had no bin for | Class **I** (infrastructure: API 5xx, network) added alongside P/S/X as not counting against the scheduler. Recorded because it moves the reading TOWARD the arm this session predicted against. | codebase-derived |
| D-6 | four spawns landed on already-merged issues — a scheduler defect that is not transport | Class **M** (mis-dispatch) added and reported separately rather than folded into X, where it would have been invisible. Neutral to `M1ᵗ`. | codebase-derived |

| D-7 | the criterion's B2 consequence — a launch enumeration committed BEFORE scoring | DEPARTURE — no enumeration was committed before the scoring commit `ecc77e5`, and the ordering cannot now be satisfied. It is discharged late instead, in the audit's *Launch enumeration* section, from the gate's progress records (outside the spawn-log corpus) with unrecoverable launches marked. Recorded as broken rather than restated as met. Revision 3 additionally strikes `cost-log.jsonl` from B2's named sources: the lean lane writes no row to it, and its last row predates the corpus window by three weeks. | codebase-derived |
| D-8 | AC-2 and AC-8 say "launch"; the audit classifies spawns | AC text corrected to **spawn**, which is what the surviving evidence supports and what the file always in fact did. The launch unit is not dropped — it is enumerated separately per `D-7` and bounded in the audit's limitation 1 — but it is not the unit the per-row rubric can be applied to, because no surviving source enumerates launches. Correcting the AC to match the deliverable, rather than leaving a criterion no evidence can satisfy. | codebase-derived |

**Provenance note for `D-1`..`D-3`.** The operator was given the phase split in plain terms on
2026-08-23 — "Phase 1 — this session … Phase 2 — the prospective runs … nine lane runs" — together
with the statement that phase 1 does not select the arm, and launched `build-lean` on #643 after
reading it. That is the ratification these three rows rest on. It is recorded here rather than
inferred silently, so a reviewer can repudiate it.

## Verification

```
bash tools/run-selftests.sh --full --exclude tools/install-topology-selftest.sh
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
```

This slice adds no shell and no gate. It adds two committed documents and one evidence file, so
its guard mass delta is zero by construction and it needs no `Guard-mass:` trailer — the check
#641 landed applies to it like any other PR.
