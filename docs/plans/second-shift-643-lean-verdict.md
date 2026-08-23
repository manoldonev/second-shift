# lean review verdict — #643

verdict=needs-work
run_id: review-643-1
session_id: 0a9d4b5e-24f4-4cef-bdec-f520c8732ab9
rounds: 1
pr: #651
reviewed_head: f38b7d33d21a12ab2c9fcb8cec4491f8ab94f3d1
reviewed_patch_id: 82d47de96b07aa1baa84f6f30a0122c2370ae087
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown
capabilities: pr-marker

Round 1, root round — full branch diff `4055f24..f38b7d3` (3 files, +361, docs-only). Panel:
maintainability (approve, declined domain — no code surface) and scope-completeness (**FAIL**,
7 items). The scope gate's FAIL is a hard gate on the merge verdict.

**The headline holds and I am not disputing it.** The prediction was made in advance and was
refuted by its author's own corpus; I verified the ordering independently, re-derived the band
math, spot-checked the evidence table against the actual spawn logs, and ran AC-4 to green. The
six blockers below are defects in the *artifact*, not in the *result* — every one of them leaves
the arm-narrowing conclusion standing. That distinction matters because #650 runs its campaign
against these exact committed files and is instructed not to re-litigate them.

## What verifies

- **AC-1's ordering is genuine.** `git log --reverse` puts `f573ee3` first; `git show --stat
  f573ee3` is the pre-registration + spec and no measurement. The audit lands two commits later
  in `ecc77e5`.
- **The evidence table is real.** 57 rows; the class tally (42 clean + 5 T + 4 M + 3 S + 2 U +
  1 I) sums to 57; the band math checks (50/57 = 0.877, 52/57 = 0.912); the byte sizes I sampled
  (51, 159, 161, 188, 142, 0, 0) match the files on disk; the four class-M rows are supported by
  the logs' own opening lines; and the "only #562 and #585 collide on `SPAWN_N`" claim is true of
  the full 57-file listing.
- **AC-4 verified by execution, not by reading the claim.** `bash tools/run-selftests.sh --full
  --exclude tools/install-topology-selftest.sh` from the branch worktree: `74 scored, 74 run,
  0 served from cache, 0 failed`, rc 0.
- **The re-scope is a split, not a cut.** #650 is filed, OPEN, `ready-for-dev`, linked from the PR
  body and the spec, and carries AC-2's campaign, AC-3's execution and the log-directory fix.
- **`pr-gates` is red for exactly one reason** — `no committed verdict record` — which this round
  supplies. Nothing else in that job failed.

## Blockers

**B-1 — the corpus is not the set it declares, and the omitted set contains a class-T spawn.**
`D-4` fixes the corpus at "**all** launches since #548 introduced spawn logging: 2026-08-16 →
08-22, 57 spawn logs", and the pre-registration carries the no-drop rule unchanged. Six spawn logs
inside that window were not collected: `.claude/pipeline-state/archive-641-pr645-20260822T141642Z/`
holds `641-lean-spawn-{1..6}`, an entire six-spawn launch of #641 archived on 2026-08-22T14:16:42Z.
They are not duplicates — the archived `641-lean-spawn-1/2/3` differ in size and content from the
live files of the same name (2300/3021/1666 vs 1919/2591/142 bytes).

One of them classifies **T** by the pre-registration's own rubric. Archived
`641-lean-spawn-3-build.log` (1666 bytes) ends:

> "…`check-guard-budget-selftest.sh` (10/10) and `gate-ablation-selftest.sh` (all cases) both pass
> locally… **PR body update is staged locally, ready to push once the full sweep confirms nothing
> else broke. I'll pick this back up when the sweep finishes.**"

Turn ended, work unpushed, exit 0, no signal to the scheduler — the same shape the audit's own
`581-lean-spawn-2` row scores T. The other five read clean (spawn 6 is a completed round-3 approve).

So the denominator is 63, not 57, and T is 6, not 5. I recomputed: 1 − 6/63 = 0.905 optimistic,
1 − 8/63 = 0.873 pessimistic. **The arm does not move** — still the keep row. What moves is the
tally, the no-drop claim, and limitation 1's "the earlier launches' transcripts are gone", which is
false for the one launch the audit names as its worst case. #641's four-launches-behind-three-logs
is the file's central illustration that the launch unit is unrecoverable, and one of those four
launches is recoverable in full, in the same directory the corpus was drawn from.

*Remedy:* score the six and restate the band, or state the collection boundary explicitly
(top-level, non-archived) and cite the archive as a recovered launch.

**B-2 — the pre-registration's own B2 consequence was never satisfied, and the audit substitutes
the route that same file ruled unavailable.** `second-shift-643-preregistration.md:34`:

> "the launch enumeration must come from sources outside the corpus (the operating record,
> `cost-log.jsonl`, tracker timestamps), **be committed before scoring**, and mark unrecoverable
> launches explicitly."

No such enumeration is committed anywhere on the branch, and nothing precedes the scoring commit
`ecc77e5`. `second-shift-643-audit.md:46-54` instead derives a 17-launch floor from a `SPAWN_N`
collision signal **inside** the corpus — an in-corpus recovery the criterion had just declared
unavailable at `:19-32`. Compounding it, one of the three named outside sources cannot hold the
data: the lean lane writes no `cost-log.jsonl` row by design.

This one is **not carried by `D-1`/`D-2`/`D-3`**. Those depart from the prospective campaign; this
binds the retrospective audit the slice does deliver, and it is the procedural step that was
supposed to make the launch unit scorable at all.

*Remedy:* commit the partial enumeration with unrecoverables marked — B-1's archive supplies #641's
— or amend the criterion in a new revision with the old one left standing, per #650's own rule.

**B-3 — the arm table and the B3 section disagree on arm C's selection condition, and revision 2
introduced the gap that revision 1 did not have.** The B1 decision table selects on `M1ᵗ` alone:

> `>= 0.80` → **C — keep.**

The B3 section adds a conjunct:

> "Arm C is selected on `M1ᵗ` **and** attention(a) < attention(b)."

If `M1ᵗ` clears 0.80 and the attention comparison fails, the table says keep, the prose says
not-keep, and **no arm is assigned**. Revision 1 had no such hole — its table read
`M1 >= 0.80 **and** M2(scheduler) <= M2(manual) → C`, with `M1 >= 0.50, but either condition
fails → B` catching exactly this region. Revision 2 moved the conjunct out of the table into prose
and dropped the catch row.

That is B1's own defect in miniature — B1 exists because "revision 1's prose and its table selected
different arms on the same data" — reintroduced by the fix for it. It has to close now: #650
measures against this file and is told not to re-litigate the criterion.

*Remedy:* restore the "either condition fails → B" row, or fold the attention conjunct back into
the table.

**B-4 — the audit attributes the prediction to the pre-registration, and it is not there.**
`second-shift-643-audit.md:12-13`:

> "The pre-registration recorded a prior of `M1ᵗ ∈ [0.30, 0.50]` — arm A, delete — and committed to
> 'if it comes back materially higher, that is evidence against my framing.'"

Neither the number nor that sentence appears in `second-shift-643-preregistration.md` or in #643's
body. Both are in issue comment
[5385766947](https://github.com/manoldonev/second-shift/issues/643#issuecomment-5385766947)
(revision 1, 2026-08-23T11:31:08Z), which reads: "M1 lands between 0.30 and 0.50 — arm A, **or the
top of arm B**. If it comes back materially higher, that is evidence against **the framing above**,
and the arm the table selects beats the prediction." The rendered quote is not the written one, and
the gloss drops "or the top of arm B". Separately, the pre-registration says at `:108` that the
prediction "is recorded as a prior" — and records none.

**The substance survives and I want that on the record:** comment 5385766947 predates the branch's
first commit (11:31:08Z vs 11:51:08Z), so the prediction genuinely preceded the data. What fails is
where the artifact says it lives. This is the defect the pre-registration itself diagnoses two
sections earlier — "A GitHub comment is not committed… a scope amendment placed in a comment was
the single most expensive error of the 2026-08-22 recalibration." Revision 2 committed the
criterion and left the prediction behind. #650's body says "Do not re-litigate the criterion. It is
committed at `docs/plans/second-shift-643-preregistration.md`" — a session that reads only that
file cannot find the prediction the headline is scored against.

*Remedy:* quote it accurately with the comment link, or fold it into the committed file marked as
carried verbatim from revision 1.

**B-5 — the three AC departures are asserted on the branch; #643's body defers nothing.**
`D-1`/`D-2`/`D-3` are documented, operator-ratified, and paired with an open #650 — that is a real
split and the ledger records its provenance rather than inferring it. But #643's body still states
AC-2, AC-3 and AC-5 unqualified, and `build-lean` reads the body. The pre-registration names this
exact shape, in bold, as the most expensive error of the 2026-08-22 recalibration; the branch-only
variant has the same failure mode with a different container.

*Remedy (human-authority — I am not clearing it here):* amend #643's body with the deferral and the
#650 link. Per the review-lead auto-mode caveat, a scope blocker with no code remedy is carried to
the merge boundary rather than waived in synthesis.

**B-6 — #617, #638 and #639 stay blocked behind a ticket that no longer owns the decision.**
#643's body opens by sequencing all three behind it, and AC-3 makes unblocking them the exit
condition of a `keep` result. No arm was selected, `Closes #643` fires on merge, and the decision
has moved to #650 — with nothing recorded on any of the three tickets.

*Remedy:* re-point their dependency onto #650, or note it on each.

## Warnings

**W-1 — "landed before any of the numbers were read" overclaims what `git log --reverse` proves.**
The audit's opening says the pre-registration landed "before any of the numbers below were read —
`git log --reverse` is the check". The pre-registration and scoring commits are 4m44s apart
(14:51:08 → 14:55:52 +03:00), inside a session the cost block fences at nine minutes total. 57 logs
cannot be classified in that window, so commit order establishes commit order, not read order. The
good-faith evidence in hand is stronger and doesn't need this: a refuted prediction, and `D-5`
recorded specifically because it moves the reading toward the arm the author predicted against.

**W-2 — the audit declines to bound the launch-level rate it could bound from its own numbers.**
Limitation 1 says the launch-level rate is "necessarily worse than the spawn-level rate by an
unknown factor" and stops. The factor is partly known: at the file's own floor of 17 launches with
5 T spawns, launch-level `M1ᵗ` is about 1 − 5/17 = 0.71 — the **reshape** row, not the keep row.
The conclusion still survives (0.71 is nowhere near the delete arm), which is exactly why stating
the bound costs nothing and closes the largest hole a reader can drive through the headline.

**W-3 — the robustness the audit has and does not claim.** `D-5` is flagged "so it can be checked
rather than trusted"; here is the check, and it favours the file. Unamended rubric (API 500 scored
`U`): 0.86–0.91. Charging all four mis-dispatches against the scheduler: 0.81–0.84. Corpus
corrected per B-1: 0.87–0.91. Every defensible variation stays in the ≥ 0.80 keep row at spawn
level; only the naive everything-counts reading (0.74) lands in reshape. That is a materially
stronger statement than the single band, and it is derivable from the table already committed.

## Per-AC scoring

| AC | Score | Basis |
| --- | --- | --- |
| AC-1 | **satisfied** | Ordering verified independently — `f573ee3` first, prereg + spec only, no measurement; audit in `ecc77e5`. Criterion, three arms and date all present. B-4 is an attribution defect in the audit, not a miss against AC-1's text. |
| AC-2 | **unsatisfied** | Departed (`D-1`), and the restated version is not met either: it says "every **launch** … classified" while the audit classifies spawns, the B2-required launch enumeration is uncommitted (B-2), and the corpus is incomplete (B-1). |
| AC-3 | **unsatisfied** | Departed (`D-2`). No arm executed; the `keep` branch never fires, so #617/#638/#639 keep no disposition (B-6). |
| AC-4 | **satisfied** | Run by me on the branch worktree: 74 scored, 74 run, 0 failed, rc 0. No subject removed, so no selftest orphaned. |
| AC-5 | **unsatisfied** | Departed (`D-3`). The vacuity argument is defensible — no front door moved because no arm landed — but it is asserted only on the branch (B-5). |
| AC-6 | **satisfied** | `Changelog: none` on all four commits. |
| AC-7 | **satisfied** | #650 filed, OPEN, `ready-for-dev`, linked from the PR body and spec; carries AC-2's campaign, AC-3's execution and the log-directory fix. |
| AC-8 | **unsatisfied** | Every row present carries real evidence and I spot-verified it. But AC-8 binds "each corpus launch", and six members of the declared corpus — one of them class T — carry no row at all (B-1). |

## Panel

| Reviewer | Verdict | Findings | Confidence |
| --- | --- | --- | --- |
| Scope Completeness | **Fail** | 7 | 82–95 |
| Maintainability | Pass | 0 | — |

Security, performance, complexity and test-coverage were not selected: trivial-inert routing on a
Markdown-only diff outside `.claude/`. a11y + design-fidelity not routed — no changed path matched
`stageParams.webComponentGlobs` (default `apps/web/**/*.{tsx,jsx}`). No reviewer went dark.

Fidelity: **not-applicable** — the spec carries no `## Design` section.

**Verdict: needs-work.** Six blockers, none of which overturn the finding. The result this slice
reports is, as far as I can verify it, correct and honestly come by; what needs fixing is that the
committed artifacts do not yet say what the session actually did — a corpus that omits a transport
failure, a procedural step skipped, a decision table with an unmapped region, and a headline
sourced to a file that does not contain it. #650 inherits all four by reference.
