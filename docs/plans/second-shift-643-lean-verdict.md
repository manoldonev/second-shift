# lean review verdict — #643

verdict=needs-work
run_id: review-643-2
session_id: cf3f3cbe-c063-48b9-b69f-e2f794b763ed
rounds: 2
pr: #651
reviewed_head: 14db415a547aedd85bbcea23792b5b17cd24635d
reviewed_patch_id: 9be967198e3b1a186895d7a6f21798add520ae6f
inherited_patch_id: 82d47de96b07aa1baa84f6f30a0122c2370ae087
inherited_from_verdict: 91f5c32cafe4d144a7902316e8520708f32e06a8
fidelity: not-applicable
model: unknown
capabilities: pr-marker

Round 2, inheriting patch `82d47de96b07`. Delta read: `91f5c32..14db415` — one commit,
three files, docs-only. Round 1's findings were read first, and every one of its six blockers
was re-checked against the fix rather than taken on the PR body's word.

**Round 1's headline still holds, and round 2 does not disturb it.** The prediction was
pre-registered, is now carried verbatim into the committed file, and was refuted by its author's
own corpus. Every reading of that corpus lands in arm B or arm C; arm A is unreachable. The two
code-remediable blockers below are defects in the *artifact*, and I recomputed each one before
raising it: **neither moves the arm.** That distinction is load-bearing because #650 runs its
campaign against these exact committed files.

## Round 1's six blockers — all verified closed

| # | Round-1 blocker | Status |
| --- | --- | --- |
| B-1 | corpus declared 57, `find` returns 63 | **CLOSED, verified.** `find .claude/pipeline-state -maxdepth 1` = 57, recursive `find .claude` = 63, 15 issues — both reproduced. 63 evidence rows present; class tally re-derived mechanically from the rows themselves (47 clean / 6 T / 4 M / 3 S / 2 U / 1 I = 63) and it matches the tally table exactly. Archived byte sizes 2300/3021/1666/2521/1855/2950 vs live 1919/2591/142 — all seven checked. |
| B-2 | B2's launch enumeration never existed | **CLOSED, verified.** New *Launch enumeration* section. Every one of the 15 per-issue rows independently reproduced: build-session counts from the progress records' `session_id:` + `\| session \|` set, build-log counts from `find`. All 15 pairs match; both totals are 38. `cost-log.jsonl` correctly struck — last row `2026-07-31T21:40:35Z`, no corpus issue present. The ordering clause is recorded as **violated** (`D-7`), not restated as met. |
| B-3 | rev 2's table regressed vs rev 1 | **CLOSED**, the conjunct is back in the table and rev 1's catch row returns — but the new table has a boundary defect of its own; see **B-9**. |
| B-4 | headline sourced to a file not containing it | **CLOSED, verified.** Comment `5385766947` created `2026-08-23T11:31:08Z`, `updated` identical — never edited. Quote is verbatim, "or the top of arm B" restored, both timestamps cited and both correct (`f573ee3` `11:51:08Z`, `ecc77e5` `11:55:52Z`). |
| B-5 | #643's body still stated AC-2/3/5 unqualified | **CLOSED, verified.** Body carries the amendment section with the three-row disposition table and the #650 sequencing paragraph. Body `updated_at` `2026-08-23T13:57:04Z`. |
| B-6 | #617/#638/#639 sequenced behind a ticket that no longer owns the decision | **NOT CLOSED** — see **B-8**. |

Warnings W-1/W-2/W-3 are all discharged: the commit-order gloss is corrected and the 20-minute
prior is cited instead; the launch-level rate is bounded rather than declined (floor 18, 6 T,
`>= 0.667`); the *Robustness* section enumerates seven readings.

## Blockers

### B-7 — two of the four class-`M` rows are contradicted by their own logs

`M` is defined as "spawned onto already-completed work". Two rows do not meet it, and the
disproof is in the sources the rows themselves cite.

**`533-lean-spawn-1-build.log`.** The evidence line reads "spawned onto #533 after PR #556 had
landed". PR #556 merged at `2026-08-16T17:35:50Z` and #533 closed at `17:35:51Z`. That spawn's
`entry` row is `2026-08-16T16:29:11Z` — **66 minutes before the merge** — and its progress record
then walks milestones 1–4 to `satisfied` before milestone 5 fails at `17:41:10Z` with "no open PR
found". It was not dispatched onto completed work; the ticket closed underneath a running spawn.

**`530-lean-spawn-4-build.log`.** The evidence line reads "spawned onto #530 after a concurrent
lane had already merged it". The log's own first paragraph says the opposite: "while I was mid-run
(running `bash G all 530` from the worktree to check remaining milestones), a different run of
this same issue completed underneath me."

`530-5` and `549-6` survive the check and are genuine `M`: both were the *next* `SPAWN_N` inside a
launch whose previous spawn had already terminated after the close (`530-4` ends `18:54:18Z`,
`530-5` ends `18:54:46Z`, #530 closed `18:52:03Z`; `549-6` ends `20:54:38Z`, #549 closed
`20:49:38Z`), and each opens by reporting the closure it found on arrival.

Two further claims fall with this. "Class M's four rows sit in this set" — the set being the 8
build logs with no `entry` record — is false for `533-1`, which has an accepted `entry` row; and
the mechanism offered for that set, "a mis-dispatch that `entry` refused with rc 10", does not
describe it either. `rc 10` is real (`build-lean/SKILL.md:17`), but it did not fire here, because
at `16:29:11Z` there was nothing to refuse.

**Recomputed before raising, and the arm does not move.** `M` = 2, clean = 49, total still 63.
`M1ᵗ` is untouched (`M` was never charged): **0.873–0.905**, keep row. The naive reading goes
`0.746 → 0.778`, still B. The *Robustness* row "all mis-dispatches charged to the scheduler" goes
`0.810–0.841 → 0.841–0.873`, still C. Launch floor 18, the post-#566 nine and the `D-5`-unamended
row are all unaffected. **Every reading still lands in B or C and arm A stays unreachable.**

What needs correcting: the two evidence lines, the `M` count in the *Classification tally* and in
limitation 3, the naive rows in *What the attribution rubric changed* and in *Robustness*, and the
"Class M's four rows sit in this set" sentence.

The correction is worth more than the two rows. Limitation 3's illustration — "one of them
collided with a concurrent lane" — is one of the two reclassified spawns, so the shape the audit
reports as a *mis-dispatch* is mostly a different defect: **a ticket that closes under a running
spawn with no mid-run staleness re-check.** `lean-gate.sh:2502` already has the refusal for it
(`staleness`, rc 7) and nothing on the build path calls it between milestones. That is evidence
#650 wants, and it is currently folded into the wrong bin.

### B-8 — round 1's B-6 is not discharged (carried)

Verified against the API, not the PR body: the latest sequencing comments on **#617**
(`2026-08-22T11:49:57Z`), **#638** (`11:49:58Z`) and **#639** (`11:50:00Z`) all still read
"**Sequenced behind #643.**" No re-point comment exists on any of the three.

#643's body amendment does state the re-point durably, and it is reachable from all three tickets
via the link they already carry — that is a real partial remedy. It is not the whole one: `Closes
#643` fires on merge, and a reader of #617 sees a blocker pointing at a closed ticket with no
successor named at the point of reference. Per round 1's rule, a scope blocker with no code remedy
is **carried to the merge boundary, not waived in synthesis**, and the operator has stated in this
round that it is not yet discharged and has sanctioned the three comments landing before merge.
Recorded as outstanding, owned by the operator, no branch change required.

### B-9 — the decision table is two-valued at exactly `M1ᵗ = 0.80`

`R3-2` rebuilds the table to close round 1's B-3 and states it "is now total over its domain". It
is total; it is not single-valued. Rows `>= 0.80` and `0.50 – 0.80` overlap at the endpoint, so a
run with `M1ᵗ = 0.80` and `attention(a) < attention(b)` is selected as **C** by row 1 and **B** by
row 3.

The overlap is inherited from revision 2 (`:75`–`:77`), not introduced by revision 3 — but
revision 3 is the amendment written to remove exactly this class of hole, and it re-published the
boundary unchanged while asserting totality. `0.80` is not a measure-zero curiosity on a nine-run
campaign: it is `4/5`, `8/10`, `12/15`. #650 selects an arm from this table, and at that one value
the criterion hands the choice back to a post-hoc judgement call — the discretion the
pre-registration exists to remove. One row-label edit closes it.

## Warnings

- **W-4 — the Decision Ledger table is split in two.** `docs/plans/second-shift-643-lean.md:67` is
  a blank line between `D-6` and `D-7`. On GitHub, `D-7` and `D-8` render as literal pipe text, not
  table rows — and they are the two rows carrying this round's central admission. `ledger-lint.sh`
  reports `8 ledger row(s) / OK` because it matches rows by grep, so no gate catches it. Delete the
  blank line.
- **W-5 — the PR body leads with the pre-correction band.** The body's headline still says
  "Spawn-level `M1ᵗ` is 0.88–0.91"; the committed file says `0.873–0.905` and `R3-4` records the
  move explicitly. The corrected figure does appear further down, in the round-2 table, so the body
  states both. The body also cites `tee -a` at `:633`; the file and `orchestrate-lean.sh` say
  `:634` (the file is right — `:607`, `:621`, `:634` all verified against source).
- **W-6 — "Build-time amendment" is the wrong provenance label.** The operator states they authored
  #643's amendment section and that operator authorship is the deliberate point ("scope license
  comes from the operator, not the build"). The heading reads as build-authored, in the one place
  where provenance is the substance.

## AC scoring

| AC | Score | Basis |
| --- | --- | --- |
| AC-1 — pre-registration lands before any measurement | **satisfied** | `git log --reverse` puts `f573ee3` first; `git show --stat f573ee3` is prereg + spec, +210, no measurement. Comment `5385766947` created `11:31:08Z`, never edited, 20 min before the branch. |
| AC-2 — every corpus spawn classified, band stated, launch unit enumerated separately | **unsatisfied** | 63 rows present and the band is stated and correct, but two rows are misclassified — B-7. The launch half is delivered and verified. |
| AC-3 — no arm selected or executed | **satisfied** | No arm selected anywhere in the diff; `D-2` and the audit both say so explicitly. |
| AC-4 — `run-selftests.sh --full --exclude install-topology` green | **satisfied** | Run by me at the reviewed head `14db415`: `74 scored, 74 run, 0 served from cache, 0 failed`, rc 0. |
| AC-5 — front-door truth | **satisfied** | Departed per `D-3`; vacuous — the diff is docs-only and moves no front door. |
| AC-6 — `Changelog:` trailer | **satisfied** | `Changelog: none` on every commit of the branch. |
| AC-7 — the follow-up is filed and linked | **satisfied** | #650 open, `ready-for-dev`, linked from the PR body and from `D-1`/`D-2`/`D-3`. |
| AC-8 — every row carries the evidence that produced its class | **unsatisfied** | All 63 rows carry evidence, but two rows' evidence is contradicted by the source it cites — B-7. |

`D-8` amends AC-2 and AC-8 from "launch" to "spawn" *after* the fact. I scored that as bookkeeping
rather than as goal-post moving, and say so explicitly so it can be repudiated: both ACs were added
by this slice, the audit always in fact classified spawns, and the launch obligation was not
dropped — it was discharged in a new section and bounded in limitation 1. Had the launch unit
simply disappeared, this would have been a blocker on its own.

## What I verified by hand

Everything below was reproduced from sources, not read off the PR body: the 57-vs-63 glob/find
split and the 15-issue set; all 63 evidence rows re-tallied by class; the seven archived/live byte
sizes; the archived launch's strictly-increasing mtimes (`12:23:42Z → 13:18:53Z`), its
build/review alternation and its six-spawn completeness; all 15 rows of the launch-enumeration
table on both columns, plus both totals of 38; the recovered session `71e53c4e` at
`2026-08-22T12:07:51Z` and its absence from every live record; `2bae5cd` on `pr645`; every band in
the *Robustness* table recomputed (`0.746`, `0.873`, `0.905`, `0.857–0.905`, `0.810–0.841`,
`0.667`, `0.778`); the post-#566 set by mtime against `9f2b5d0` (`2026-08-21T12:29:09Z`) — exactly
9 spawns, exactly 2 T; the four pre-#566 T dates in UTC; the `SPAWN_N` two-role collision claim
(exactly #562 and #585 — the three #641 key collisions are archive-vs-live at the *same* role and
correctly excluded), and the floor-18 arithmetic; `:607`/`:621`/`:634` against
`orchestrate-lean.sh`; `grep -rn archive plugins/` = 0 hits; `ledger-lint.sh` on the spec; the
merge/close timestamps for #533, #530, #549 and PR #556; and AC-4 by execution.

Panel: none dispatched. The diff is 3 markdown files with no code surface, and round 1's panel on
this same shape returned one reviewer that declined the domain for want of code and one scope
gate — every finding that round came from hand verification. This round's three blockers came the
same way: from re-deriving the file's claims against the logs, the progress records and the
tracker, which is the only technique that can reach them. Recorded plainly so the choice is
visible rather than implied.
