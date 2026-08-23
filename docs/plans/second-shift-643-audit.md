# #643 — retrospective audit of the fixed corpus

**Scored 2026-08-23, against the criterion committed in
[`second-shift-643-preregistration.md`](second-shift-643-preregistration.md), which landed as this
branch's first commit.** `git log --reverse` is the check, and it is worth being exact about what it
checks: the pre-registration commit `f573ee3` (`11:51:08Z`) precedes the scoring commit `ecc77e5`
(`11:55:52Z`) by 4m44s. **That establishes commit order, not read order** — the 57 logs that pass
had in hand could not be classified in four minutes, so some reading necessarily preceded the
criterion's commit. The
ordering evidence that does carry weight is elsewhere and is stronger: the prediction below was
recorded at `11:31:08Z`, twenty minutes before the branch existed, and it was refuted.

This file was revised on 2026-08-23 after round 1 of the independent review on PR 651 — the corpus,
the bands and limitation 1 all moved; see *Corpus enumeration* — and again after round 2, when two
of the four class-`M` rows turned out to be contradicted by the logs they cite; see *Classification
correction*. `M1ᵗ` survived both revisions unchanged; the readings that charge `M` did not.

Per the pre-registration this audit **narrows** the arms; it does not select one. The prospective
per-arm runs select, and they are the follow-up's work.

## Headline: the prediction was wrong

The prior was recorded in [revision 1 of the criterion](https://github.com/manoldonev/second-shift/issues/643#issuecomment-5385766947)
at `2026-08-23T11:31:08Z`, twenty minutes before this branch's first commit, and is carried verbatim
into the committed file by revision 3:

> M1 lands between 0.30 and 0.50 — arm A, or the top of arm B. **If it comes back materially higher,
> that is evidence against the framing above, and the arm the table selects beats the prediction.**

It came back materially higher. **At the spawn level the transport-attributed rate is 0.873–0.905,
which is arm C territory** — not arm A, and not the top of arm B either.

That reading does not survive contact with the launch-unit problem below, and the post-#566 corpus
is nine spawns. But the direction is recorded plainly: the corpus does not support the delete arm,
and it was assembled by someone who expected it to.

## What the attribution rubric changed

| Reading | Rate | Arm it selects |
| --- | --- | --- |
| Naive — every non-clean spawn counts against the scheduler | 49/63 = **0.778** | B (reshape) |
| `M1ᵗ` — transport-attributed only, U optimistic | 57/63 = **0.905** | C (keep) |
| `M1ᵗ` — transport-attributed only, U pessimistic | 55/63 = **0.873** | C (keep) |

Both ends of the band land in the same row, which is the pre-registration's condition for the band
to be usable at all. **The rubric is what moved the answer**: three host-sleep deaths, one API 500
and two mis-dispatches are not the transport's fault, and revision 1 of the criterion — which had
no rubric — would have charged all six to the scheduler and selected a different arm.

Note what this table does *not* do: it selects no arm. Under revision 4's decision table arm C
additionally requires `attention(a) < attention(b)`, which this slice does not measure at all.

## Classification tally

| Class | Count | Counts against the scheduler? |
| --- | --- | --- |
| clean | 49 | — |
| **T** transport — turn ended with the milestone unmet | 6 | **yes, and only these** |
| **M** mis-dispatch — spawned onto already-completed work | 2 | see limitation 3 |
| **S** host sleep | 3 | no |
| **U** unattributable — empty log | 2 | widens the band |
| **I** infrastructure — API 500 | 1 | no |

63 spawns across 15 issues. The tally sums to 63; see *Corpus enumeration* for why it is 63 and not
the 57 this file first reported.

## Corpus enumeration

This file first reported 57 spawn logs. The corpus is 63.

`D-4` fixes the corpus by a **rule** — "all launches since #548 introduced spawn logging,
2026-08-16 → 08-22" — and the 57 was a miscount of that rule rather than a second definition of it.
The two commands disagree:

```
find .claude/pipeline-state -maxdepth 1 -name '*lean-spawn-*.log' | wc -l   # 57
find .claude               -name '*lean-spawn-*.log' | wc -l                # 63
```

The six-log difference is `.claude/pipeline-state/archive-641-pr645-20260822T141642Z/`, a complete
six-spawn launch of #641 archived by hand on `2026-08-22T14:16:42Z` when PR 645 was abandoned. They
are **not duplicates of the live files of the same name** — archived spawns 1/2/3 are 2300/3021/1666
bytes against the live 1919/2591/142 — they are a different, earlier launch.

Correcting an enumeration toward *more* data is not re-opening a fixed corpus; dropping members
would be. The no-drop rule is unchanged and every band in this file is restated on 63. **The arm does
not move** (0.873–0.905, still the keep row); what moves is the tally, the post-#566 sample, and
limitation 1, which had asserted these transcripts were gone.

The lesson is worth more than the six rows: **when a document declares a corpus, enumerate the
corpus yourself.** A top-level glob and a recursive `find` disagreed, and the difference is where
the only end-to-end-observable launch in the entire corpus was hiding.

## Classification correction — two `M` rows were alive across the close

`M` is "spawned onto already-completed work". Two of the four rows first reported do not meet that
definition, and the disproof is in the sources the rows themselves cite. Both were re-derived here
from the logs, the gate's progress records and the tracker.

**`533-lean-spawn-1-build.log` — reclassified `clean`.** PR #556 merged `2026-08-16T17:35:50Z` and
#533 closed `17:35:51Z`. This spawn's `entry` row in `533-lean-progress.md` is `16:29:11Z` —
**66 min 39 s earlier** — and it is an *accepted* entry, so `entry`'s rc-10 refusal never fired and
could not have: at `16:29:11Z` there was nothing to refuse. The record then walks milestone 1
(`16:52:12Z`), 2 (`16:52:17Z`), 3 (`16:58:38Z`) and 4 (`17:33:57Z`) to `satisfied`, all of it before
the merge, and only milestone 5 fails at `17:41:10Z` with "no open PR found for branch
claude/second-shift-533". Teardown `17:42:18Z`; the log's own mtime is `2026-08-16T17:42:24Z`
(`20:42:24` local `+0300` — the offset is worth stating, because reading that stamp as UTC turns a
seven-minute overhang into a three-hour one). A 73-minute run that straddles the close is not a
dispatch onto completed work.

**`530-lean-spawn-4-build.log` — reclassified `clean`.** The log's first paragraph says the
opposite of its evidence line: "while I was mid-run (running `bash G all 530` from the worktree to
check remaining milestones), a different run of this same issue completed underneath me", and it
goes on to explain that "the build worktree … was torn down mid-command — that's why my gate call's
output devolved into `No such file or directory` … the directory disappeared out from under the
running shell, not a real test regression". `530-lean-progress.md` corroborates mechanically: the
final block starts milestone 1 at `18:45:00Z` and milestone 3 concludes `rc=1` at `18:53:48Z`,
straddling #530's close at `18:52:03Z`. Log mtime `18:54:18Z`.

**`530-lean-spawn-5` and `549-lean-spawn-6` survive the check and stay `M`.** Each is the *next*
`SPAWN_N` in a launch whose previous spawn had already terminated after the close, and each opens by
reporting the closure it found on arrival rather than discovering it mid-run — `530-5` (mtime
`18:54:46Z`, 28 s after `530-4`) leads with "Issue #530 is already **closed and merged**"; `549-6`
(mtime `20:54:38Z`, after `549-5`'s `20:54:07Z`) leads with a state table reading `CLOSED` /
`MERGED` / "Worktree none for 549 (already swept)". #549 closed `20:49:38Z`, PR #560 merged
`20:49:37Z`. **That opening is how the two shapes are told apart:** discovered-on-arrival is `M`;
discovered-mid-run is the staleness shape.

**Recomputed before it was written up, and the arm does not move.** Corrected tally: clean 49, T 6,
M 2, S 3, U 2, I 1 — still 63. `M1ᵗ` is **untouched at 0.873–0.905** because `M` was never charged
against it. What moves is every reading that *does* charge `M`: the naive row `47/63 = 0.746 →
49/63 = 0.778` (still B) and *Robustness*'s all-mis-dispatches-charged row `0.810–0.841 →
0.841–0.873` (still C). The launch floor of 18, the `0.667` launch bound, the post-#566 nine-spawn
`0.778` and the `D-5`-unamended `0.857–0.905` are all untouched — none of them is a function of `M`,
and both corrected spawns are 08-16, outside the post-#566 set. **Every reading still lands in arm B
or arm C, and arm A stays unreachable.** Recorded as `D-9`, and the direction is stated in
*Rubric amendment*: dropping rows out of `M` moves the naive reading *toward* keep, which is the arm
this file's author predicted against.

## Launch enumeration — B2's consequence, discharged late

The criterion's B2 correction requires a launch enumeration "from sources outside the corpus …
committed before scoring", with unrecoverable launches marked. **That ordering was violated** — no
enumeration was committed before the scoring commit `ecc77e5`, and this section is the late
discharge. Recorded as departure `D-7` rather than restated as met. Revision 3 also strikes
`cost-log.jsonl` from the named sources: the lean lane writes no row to it by design, and
empirically its last row is `2026-07-31T21:40:35Z` — three weeks before the window opens, with none
of the 15 corpus issues present.

The source that does work is the **gate's progress records** (`<issue>-lean-progress.md`), written
by `lean-gate.sh` and not by the scheduler, so genuinely outside the spawn-log corpus. Each `entry`
stamps a UTC timestamp and a session id.

| issue | build sessions recorded | build spawn logs surviving | delta |
| --- | --- | --- | --- |
| 141 | 1 | 2 | −1 |
| 517 | 3 | 3 | 0 |
| 530 | 1 | 4 | −3 |
| 533 | 1 | 1 | 0 |
| 542 | 2 | 2 | 0 |
| 549 | 3 | 4 | −1 |
| 562 | 5 | 4 | **+1** |
| 565 | 4 | 1 | **+3** |
| 575 | 1 | 2 | −1 |
| 581 | 2 | 3 | −1 |
| 582 | 1 | 1 | 0 |
| 583 | 4 | 2 | **+2** |
| 585 | 4 | 3 | **+1** |
| 597 | 2 | 1 | **+1** |
| 641 | 4 | 5 | −1 |
| **total** | **38** | **38** | — |

#641's row folds in the archive on both sides: 3 live sessions + 1 recovered from the archived
progress record, against 2 live + 3 archived build logs. The recovered session
(`71e53c4e`, `2026-08-22T12:07:51Z`) appears in **no** live record — the hand-archival *moved* the
progress file rather than copying it, so the operating record is itself segmented and only the
archive holds the first segment. That is an operator action, not a scheduler defect, but it means
the corpus boundary silently dropped a progress segment as well as six spawn logs.

**What this enumerates, and what it does not.** The unit here is the *build session*, not the
launch. One launch spawns a build session per round, so 38 over-counts launches; and the record
cannot distinguish a scheduler-spawned session from a hand-run one, so it over-counts scheduler
work too. It is an upper bound that cannot be converted into a launch count. **No surviving source
enumerates launches** — that is the finding, and it is now established from outside the corpus
rather than from a signal inside it.

Both directions of the delta are informative, and neither is visible in the spawn logs alone:

- **8 recorded build sessions have no surviving build transcript** (#562, #565, #583, #585, #597).
  Some are hand-runs that were never spawned; the rest are destroyed transcripts. Either way the
  spawn-log corpus is not a census of build sessions.
- **8 build spawn logs have no `entry` record at all** (#141, #530, #549, #575, #581, #641) — a
  spawn that died before the gate's first call, or a mis-dispatch that `entry` refused with rc 10.
  This set is **not** a mechanical check on class `M`: #533 does not appear in it, yet
  `533-lean-spawn-1` was classified `M` — which is how the misclassification corrected below was
  first visible from inside this file's own tables.

**Unrecoverable launches, marked as B2 requires:** all of them except one. The single launch
recoverable end to end is the archived #641 launch, and it is recovered only because a human copied
it aside.

## Three limitations that stop this corpus selecting an arm

**1. The launch unit is not enumerable from any surviving source, and the launch unit is what the
criterion specifies.**
`M1ᵗ` above is computed per *spawn*, not per *launch*, because `orchestrate-lean.sh` truncates each
spawn log before appending (`:621`, then `tee -a` at `:634`) and `SPAWN_N` resets per process
(`:607`). A re-launch overwrites its predecessor. In-corpus, the only launch signal is a collision —
the same `SPAWN_N` appearing under two different roles — which occurs for exactly two issues (#562,
#585); with the archived #641 launch recovered below that gives a floor of **18** launches across
the 15 issues. **The scheduler destroys the evidence needed to audit the scheduler**, and that
finding is unchanged.

Two corrections to how this file first stated it, both against its own argument:

**(a) "The earlier launches' transcripts are gone" is false for the case this file names as its
worst.** The criterion's B2 correction cites #641's four-launches-behind-three-logs as the
illustration that a launch is unrecoverable. One of those four survives *in full* —
`.claude/pipeline-state/archive-641-pr645-20260822T141642Z/` holds spawns 1–6 with strictly
increasing mtimes (12:23:42Z → 13:18:53Z), alternating build/review, no gaps: one complete launch,
hand-archived when PR 645 was abandoned. The mechanism destroys transcripts; it did not destroy
this one, because a human copied it out of the way first. **Nothing in the repo archives** —
`grep -rn archive plugins/` is empty — so this is a one-off rescue, not a property of the system.

**(b) "A launch dies whole when any spawn in it dies" is refuted by the one launch we can observe
end to end.** The recovered launch contains a class-T spawn — archived `641-lean-spawn-3-build.log`,
which ended its turn holding an unpushed PR-body update — and **it did not die**. Spawns 4, 5 and 6
ran on and the launch reached a round-3 `approve`. Its code commit had been pushed; only the PR-body
update was stranded, so the T cost part of a round rather than the launch.

That matters for the bound, because the premise was doing all the work. Taking it at face value on
the corrected numbers: floor 18 launches, 6 class-T spawns, so launch-level `M1ᵗ >= 1 − 6/18 =
**0.667**` — the reshape row, not the keep row, and worth stating plainly since this file previously
declined to bound it at all. But the premise is the pessimistic extreme, and the single launch that
can be checked against it violates it. **The true launch-level rate lies somewhere in 0.667–0.905,
and every point in that interval is in arm B or arm C. Arm A is not reachable from this corpus under
any reading of the launch unit** — including the one most hostile to the scheduler. The delete arm
needs the prospective runs, not a harsher reading of this corpus.

**2. Four of the six T failures are pre-#566, and #566 deleted the mechanism.**
`530-1` (08-16), `562-2` (08-17), `581-1` and `581-2` (08-19) are one failure mode: the session
backgrounded milestone 3 and ended its turn, and under `claude -p` turn end is process exit. #566
landed `2026-08-21T12:29:09Z` (`9f2b5d0`) and made milestone 3 run inline. The two T spawns that
post-date it are both #641 on 08-22 — live `641-3` and archived `641-3` — and **neither was waiting
on milestone 3**: one was waiting on hand-launched suites, the other on a full sweep before pushing
a PR-body edit. The mechanism #566 deleted does not appear after #566; a *different* shape of the
same turn-boundary death does.

**The post-#566 corpus is nine spawns and two T** — `1 − 2/9 = 0.778`, the reshape row. The archive
tripled it from the three spawns this file first reported, which is the single largest thing the
corpus correction bought. Nine spawns still settles nothing, and it is the number that most deserves
the prospective runs: it is the only part of this corpus that measures the transport as it exists
today, and it is the part that reads worst for the scheduler.

**3. Two scheduler costs sit outside `M1ᵗ`, and the smaller one was hiding the larger.**
`M` as reported first covered four spawns; on re-derivation only **two** are mis-dispatches —
`530-5` and `549-6`, each of which opens by reporting a closure it found on arrival. Two spawns
landed on genuinely open work and were still running when the ticket closed under them
(*Classification correction*). Both are real scheduler costs, both are *not* transport, and the
rubric as pre-registered excludes both — but they are **different defects with different remedies**:

- **mis-dispatch** (`M`, 2 spawns) — the scheduler starts a spawn against work that is already
  finished. The remedy is at dispatch time.
- **no mid-run staleness re-check** (2 spawns) — the scheduler starts a spawn correctly and never
  re-checks; the ticket closes underneath it and the spawn burns a full run discovering that at
  milestone 5. The remedy is a mid-run call, and the refusal already exists —
  `lean-gate.sh:2502` (`staleness`, rc 7) — with nothing on the build path calling it between
  milestones.

The illustration this limitation first offered — "one of them collided with a concurrent lane
mid-run" — was in fact an instance of the *second* shape, filed under the first. Recorded here
rather than folded quietly into `X`, because it is evidence the reshape arm would want and the
delete arm would want, and the criterion cannot see either shape. **Neither is wired up in this
slice** — this slice adds no shell and no gate — and the staleness re-check is routed to **#650**,
which owns the campaign these readings feed.

## Robustness — every defensible reading of this corpus

`D-5` was flagged so it could be checked rather than trusted. Here is the check, across every
variation of the rubric that can be argued for, on the corrected 63-spawn corpus:

| Reading | Rate | Arm |
| --- | --- | --- |
| Naive — every non-clean spawn charged to the scheduler | 49/63 = **0.778** | B |
| `M1ᵗ` pessimistic (U counted against) | 55/63 = **0.873** | C |
| `M1ᵗ` optimistic (U clean) | 57/63 = **0.905** | C |
| `D-5` unamended — API 500 scored `U` rather than `I` | 0.857–0.905 | C |
| Both mis-dispatches charged to the scheduler | 0.841–0.873 | C |
| Launch level, floor 18, assuming a T kills its launch | **0.667** | B |
| Post-#566 spawns only (9 spawns, 2 T) | **0.778** | B |

**Every reading lands in arm B or arm C. None reaches arm A.** The delete arm the author predicted
is not reachable from this corpus under any variation, including the ones most hostile to the
scheduler — and that is a materially stronger statement than the single band, because it does not
depend on the rubric choices a motivated author made.

The two readings that land in B are also the two that matter most for #650: the launch unit, and the
corpus that measures the transport as it exists after #566. Neither is settled here.

## Rubric amendment made during scoring

| id | change | direction |
| --- | --- | --- |
| D-5 | Class **I** (infrastructure: API 5xx, network) added alongside P/S/X as not-counting-against | favours the scheduler |
| D-6 | Class **M** (mis-dispatch) added and reported separately rather than folded into X | neutral to `M1ᵗ`; visible instead of hidden |
| D-9 | Two of D-6's four `M` rows reclassified `clean` — they were alive across the close, not dispatched after it | favours the scheduler: `M1ᵗ` is untouched, but the naive row moves `0.746 → 0.778` and the all-`M`-charged row `0.810–0.841 → 0.841–0.873` |

All three were forced by evidence: D-5 and D-6 by shapes the rubric had no bin for, D-9 by two rows
whose evidence contradicted the bin they had been put in. None moves a threshold, and D-5 and D-9
both move the reading *toward* the arm the author predicted against — recorded so that can be
checked rather than trusted.

## Per-spawn evidence

Every row carries the evidence that produced its class, per AC-8. `clean` rows quote the session's
own terminal text; classified rows quote the specific signal.

| spawn log | bytes | class | evidence |
| --- | --- | --- | --- |
| `141-lean-spawn-1-build.log` | 2818 | clean | ot exist yet. Both selftest lanes (ubuntu and macOS bash 3.2) pass. Next: **`/dev-pipeline:review-lean 599`** in a fresh session. I cannot author that record.  |
| `141-lean-spawn-2-review.log` | 2575 | clean | er-fire fails loudly on the next run rather than producing a false green. 3. **Nit** — one case's comment header says `(lt5a)` while the case emits `(lt5b)`.  |
| `141-lean-spawn-3-build.log` | 2222 | clean | s` label stays as designed; the repo's unclaim workflow releases it when the issue closes. The PR is approved and closed out — merging is yours to authorize.  |
| `517-lean-spawn-1-build.log` | 2315 | clean | UDE_CODE_ENABLE_TELEMETRY`, so there are no datapoints to recover. Milestone 4 arrives from outside this session. Next: ``` /dev-pipeline:review-lean 592 ```  |
| `517-lean-spawn-2-review.log` | 2959 | clean | have not merged or asked for a merge; the loop now goes back through a build session, and the next verdict must come from a fresh review context, not this one.  |
| `517-lean-spawn-3-build.log` | 2703 | clean | ich predates this feature, not a regression; the branch copy under `LEAN_GATE_OBSERVE=1` reports `8 bound, 8 carried, 0 departure(s)` against the real receipt.  |
| `517-lean-spawn-4-review.log` | 2769 | clean | ` had not re-run against the new approve record when I finished, so the PR's checks still show the round-1 red until that lane completes. I did not wait on it.  |
| `517-lean-spawn-5-build.log` | 2743 | clean | the repo's unclaim workflow releases it when the item closes. **PR 592 is ready to merge, but I have not merged it and won't without your explicit go-ahead.**  |
| `530-lean-spawn-1-build.log` | 51 | T | ends "Waiting for the background selftest run to finish." — turn ended holding a detached milestone-3 job |
| `530-lean-spawn-2-build.log` | 2413 | clean | te's own suggested remediation. **Next step, per [[never-wait-for-ci-before-review]]: run `/dev-pipeline:review-lean 559` next — do not wait for CI first.**  |
| `530-lean-spawn-3-review.log` | 2557 | clean | ates` was red on exactly one arm — the missing verdict record — which this round has now supplied. Panel: six reviewers selected, six returned, none dark.  |
| `530-lean-spawn-4-build.log` | 1227 | clean | opens "while I was mid-run … a different run of this same issue completed underneath me"; the progress record has this session in milestone 3 from `18:45:00Z`, failing `18:53:48Z` as the worktree was torn out from under it — #530 closed `18:52:03Z`. Alive across the close, not dispatched after it; see *Classification correction* |
| `530-lean-spawn-5-build.log` | 833 | M | spawned onto #530 after it was closed and merged |
| `533-lean-spawn-1-build.log` | 1033 | clean | `entry` accepted `16:29:11Z`, 66 min BEFORE PR #556 merged `17:35:50Z`; milestones 1–4 all reach `satisfied` (m4 `17:33:57Z`) and only m5 fails `17:41:10Z` "no open PR found". Ran to completion across the close; see *Classification correction* |
| `533-lean-spawn-2-review.log` | 188 | S | "API Error: Your computer went to sleep mid-response." after committing and pushing the record |
| `542-lean-spawn-1-build.log` | 3022 | clean | n-slow-suites.tsv`. Adding the row would defer that guard to nightly — less PR-lane coverage of a file this PR touches — so I judged it not this PR's call.  |
| `542-lean-spawn-2-review.log` | 2432 | clean | Next step is yours: `/dev-pipeline:run-lean` will pick the verdict up at milestone 4, or you can drive the merge boundary directly. I have not merged anything.  |
| `542-lean-spawn-3-build.log` | 2210 | clean | itative one there. `second-shift-delta-guard.sh` scored 9 applied / 9 killed / 0 survived locally. I did not merge — that needs your explicit authorization.  |
| `549-lean-spawn-1-build.log` | 3376 | clean | e `--cache-dir` lever, but that's a scope decision and it's yours. Review of the probe record itself can proceed in parallel: `/dev-pipeline:review-lean 560`.  |
| `549-lean-spawn-2-review.log` | 3053 | clean | ession stops here — a build session addresses the findings, and a fresh review context produces the next verdict. The one thing only you can unblock is OR-1.  |
| `549-lean-spawn-3-build.log` | 2900 | clean | et describes. I got it green by relaunching in a genuinely new process session, which is a wrapper fix, not a transport one. Worktree and claim left in place.  |
| `549-lean-spawn-4-review.log` | 2531 | clean | t a PR's closing keyword resolves. A backticked, indented or fenced trailer passes every gate on the way to merge, and the ticket silently survives its own PR.  |
| `549-lean-spawn-5-build.log` | 2797 | clean | thing verifies that a PR's closing keyword actually resolves, which is a one-line `closingIssuesReferences` assertion at the merge boundary — worth a ticket.  |
| `549-lean-spawn-6-build.log` | 1198 | M | spawned onto #549 after issue CLOSED and PR #560 MERGED |
| `562-lean-spawn-1-build.log` | 2234 | clean |  step:** a new `/dev-pipeline:review-lean 573` session, from outside this build session — I can't produce that verdict myself (P9/P10 authorship separation).  |
| `562-lean-spawn-2-build.log` | 159 | T | ends "I'll simply wait — the harness will notify me when the backgrounded milestone-3 run completes." |
| `562-lean-spawn-2-review.log` | 161 | I | "API Error: 500 Internal server error." — server-side, unrelated to the transport |
| `562-lean-spawn-3-build.log` | 1469 | clean | n PR #573 **Next: `/dev-pipeline:review-lean 573`** — milestone 4 is external by design; I don't wait on CI first (pr-gates can't be green pre-handoff yet).  |
| `562-lean-spawn-4-review.log` | 3482 | clean | ve overlapping remedies — reusing `resolve_sibling` inherits `(rs)`'s coverage and largely dissolves #2, leaving one bold-form fixture case as separate work.  |
| `562-lean-spawn-5-build.log` | 91 | S | "API Error: Your computer went to sleep mid-response." |
| `565-lean-spawn-1-build.log` | 3010 | clean | ne by design:** OR-2 (27 of 51 records stop before milestone 4) is flagged, not fixed — the follow-up issue gets filed at close-out, after the verdict lands.  |
| `565-lean-spawn-2-review.log` | 2732 | clean | and cost a round**. That next round is a re-stamp of an already-approved diff, not a re-review — unless the resolution touches more than the manifest append.  |
| `565-lean-spawn-3-review.log` | 2427 | clean | s [one PR comment](https://github.com/manoldonev/second-shift/pull/603#issuecomment-5349380623) under the bot identity. Probe worktree removed. Memory updated.  |
| `575-lean-spawn-1-build.log` | 2546 | clean | n rejoining — two consecutive reaps made zero progress. It completed only once launched as a harness-tracked background command and polled on the `.rc` file.  |
| `575-lean-spawn-2-review.log` | 2568 | clean | ean-evidence] ✗ no committed verdict record` — this record's own absence. It should go green on the re-run; everything else was already green on `262a3af`.  |
| `575-lean-spawn-3-build.log` | 2775 | clean | ave used it. I've recorded the refinement (the escape is safe *only* when the marker already exists and you've checked it). Both findings are saved to memory.  |
| `581-lean-spawn-1-build.log` | 288 | T | ends "detached background task since it exceeded the 120s foreground window; I'll pick this back up automatically" |
| `581-lean-spawn-2-build.log` | 1006 | T | ends "harness-tracked background task ... resuming from an earlier interrupted evaluation. I'll pick this back up automatically" |
| `581-lean-spawn-3-build.log` | 2007 | clean | one 4 outstanding. **Next: run `/dev-pipeline:review-lean 602`** in a fresh session. Don't wait for `pr-gates` to go green first — it can't be, pre-handoff.  |
| `581-lean-spawn-4-review.log` | 2853 | clean |  review session was spawned before this one and died producing nothing. No verdict record existed on the branch, so this correctly ran as round 1, not round 2.  |
| `581-lean-spawn-5-review.log` | 3174 | clean |  needs a code change on the branch first; if you were after something else here — a second opinion on round 1's two warnings, or the merge — tell me which.  |
| `582-lean-spawn-1-build.log` | 0 | U | empty-file — 0 bytes; either never written or truncated by a later launch's ( : > "$log" ) |
| `582-lean-spawn-2-review.log` | 2973 | clean |  probe evidence). And `pr-gates` was red before this push for exactly one reason, the missing verdict record; it should clear on the re-run this push triggers.  |
| `582-lean-spawn-3-review.log` | 3083 | clean | e round 2 it would hand the reviewer the full branch diff instead of a delta. Possibly correct-by-design for a root round; worth a look if #582 gets a round 2.  |
| `583-lean-spawn-1-build.log` | 3297 | clean | tmp/*.sh` probe scripts. Happy to remove them if you want. `lint-and-selftests` was still pending on CI when I finished — I didn't wait, per the usual rule.  |
| `583-lean-spawn-2-review.log` | 0 | U | empty-file — 0 bytes; same two candidates, not separable |
| `583-lean-spawn-3-build.log` | 255 | S | "API Error: Your computer went to sleep mid-response." mid-probe |
| `585-lean-spawn-1-build.log` | 2827 | clean | t come from outside this session, and per the lane rule I'm not waiting on CI, which cannot be green before handoff. **Next:** `/dev-pipeline:review-lean 588`  |
| `585-lean-spawn-2-build.log` | 3518 | clean |  is the same shape as #585's own D-2 (a fixture register whose final line lacks a trailing newline), and it's already diagnosed. That trade is yours, not mine.  |
| `585-lean-spawn-2-review.log` | 2529 | clean | heck were mine. `pr-gates` was red for exactly one reason pre-handoff (`no committed verdict record`); that record now exists, so the lane should re-run clean.  |
| `585-lean-spawn-3-build.log` | 2564 | clean | , correctly). A `git fetch --prune` would let it actually reclaim those; right now the cleanup commands it prints are the only real path and nothing runs them.  |
| `597-lean-spawn-1-build.log` | 2371 | clean | out `CLAUDE_CODE_ENABLE_TELEMETRY`, so 1240 in-fence rows exist from other sessions and none from this one — the datapoints for this run cannot be recovered.  |
| `597-lean-spawn-2-review.log` | 2746 | clean | ose D-5 is `user-answered`, so a warning not a blocker), and the two new `verdict-progress-unreadable` branches in `orchestrate-lean.sh` have no covering case.  |
| `597-lean-spawn-3-review.log` | 2825 | clean | -lean/lean-gate.sh 4 597` (the #363 bootstrap). Then a genuine round 2 grades the resolving merge plus the CI evidence that has never existed for this branch.  |
| `641-lean-spawn-1-build.log` | 1919 | clean | fixed as out-of-scope for a guard-mass slice. Milestone 4 (independent review) is now up to a separate `/dev-pipeline:review-lean` session — not mine to do.  |
| `641-lean-spawn-2-review.log` | 2591 | clean | went dark (turn budget, no text on either attempt) — noted as a coverage gap, though its domain is where blockers 2 and 3 came from, which I probed directly.  |
| `641-lean-spawn-3-build.log` | 142 | T | ends "I'll wait for both test suites to finish, then ... proceed to finalize the AC-7 documentation and commit." |

Six rows recovered from `.claude/pipeline-state/archive-641-pr645-20260822T141642Z/` — one complete
launch of #641 against PR 645, missed by this file's first pass. Same rubric, scored the same way.

| spawn log (archived) | bytes | class | evidence |
| --- | --- | --- | --- |
| `641-lean-spawn-1-build.log` | 2300 | clean | "**Next step (not mine to do in this session):** milestone 4 needs an independent review from a fresh session — `/dev-pipeline:review-lean 645`." |
| `641-lean-spawn-2-review.log` | 3021 | clean | "Review complete. Verdict record committed and pushed; findings posted." Round 1 `needs-work`, handed back. |
| `641-lean-spawn-3-build.log` | 1666 | **T** | ends "PR body update is staged locally, ready to push once the full sweep confirms nothing else broke. **I'll pick this back up when the sweep finishes.**" — turn ended on incomplete work at exit 0. Weaker than the other five T rows: commit `2bae5cd` *was* pushed, so only the PR-body edit was stranded. Scored T anyway — the rubric's T fires on "exit 0 on incomplete work", and reading it down would be the motivated call. |
| `641-lean-spawn-4-review.log` | 2521 | clean | "**Round 2: `needs-work`.** Verdict record `b804b36` pushed as the last commit" — findings comment posted. |
| `641-lean-spawn-5-build.log` | 1855 | clean | "Clean and pushed. Round-3 fix is complete." Both round-2 blockers closed. |
| `641-lean-spawn-6-review.log` | 2950 | clean | "Round 3 review complete: **approve**." |

PR 645 was later closed unmerged on design grounds. That is class **X** at the PR level — content,
not transport — and it is why the launch was archived by hand. It does not change any row above:
the launch itself ran to an approve.

## Note on this file

This is a dated one-shot audit artifact, not a register. Nothing reads it, nothing maintains it,
and it must never acquire a row-update ritual — that is the distinction #641 landed in the
manifesto, and this file is on the measurement side of it.
