# #643 — retrospective audit of the fixed corpus

**Scored 2026-08-23, against the criterion committed in
[`second-shift-643-preregistration.md`](second-shift-643-preregistration.md) — which landed as this
branch's first commit, before any of the numbers below were read.** `git log --reverse` is the check.

Per the pre-registration this audit **narrows** the arms; it does not select one. The prospective
per-arm runs select, and they are the follow-up's work.

## Headline: the prediction was wrong

The pre-registration recorded a prior of `M1ᵗ ∈ [0.30, 0.50]` — arm A, delete — and committed to
"if it comes back materially higher, that is evidence against my framing." It came back materially
higher. **At the spawn level the transport-attributed rate is 0.88–0.91, which is arm C territory.**

That reading does not survive contact with the launch-unit problem below, and the corpus is too
thin post-#566 to settle anything. But the direction is recorded plainly: the corpus does not
support the delete arm, and it was assembled by someone who expected it to.

## What the attribution rubric changed

| Reading | Rate | Arm it selects |
| --- | --- | --- |
| Naive — every non-clean spawn counts against the scheduler | 42/57 = **0.74** | B (reshape) |
| `M1ᵗ` — transport-attributed only, U optimistic | 52/57 = **0.91** | C (keep) |
| `M1ᵗ` — transport-attributed only, U pessimistic | 50/57 = **0.88** | C (keep) |

Both ends of the band land in the same row, which is the pre-registration's condition for the band
to be usable at all. **The rubric is what moved the answer**: three host-sleep deaths, one API 500
and four mis-dispatches are not the transport's fault, and revision 1 of the criterion — which had
no rubric — would have charged all eight to the scheduler and selected a different arm.

## Classification tally

| Class | Count | Counts against the scheduler? |
| --- | --- | --- |
| clean | 42 | — |
| **T** transport — turn ended with the milestone unmet | 5 | **yes, and only these** |
| **M** mis-dispatch — spawned onto already-completed work | 4 | see limitation 3 |
| **S** host sleep | 3 | no |
| **U** unattributable — empty log | 2 | widens the band |
| **I** infrastructure — API 500 | 1 | no |

## Three limitations that stop this corpus selecting an arm

**1. The launch unit is unrecoverable, and the launch unit is what the criterion specifies.**
`M1ᵗ` above is computed per *spawn*, not per *launch*, because `orchestrate-lean.sh` truncates each
spawn log before appending (`:621`, then `tee -a` at `:633`) and `SPAWN_N` resets per process
(`:607`). A re-launch overwrites its predecessor. The only recoverable launch signal is a collision
— the same `SPAWN_N` appearing under two different roles — which occurs for exactly two issues
(#562, #585), giving a floor of 17 launches across the 15 issues. The floor is known to be badly
low: #641 alone had **four** launches behind **three** logs. A launch dies whole when any spawn in
it dies, so the launch-level rate is necessarily worse than the spawn-level rate by an unknown
factor. **The scheduler destroys the evidence needed to audit the scheduler.**

**2. Four of the five T failures are pre-#566, and #566 deleted the mechanism.**
`530-1` (08-16), `562-2` (08-17), `581-1` and `581-2` (08-19) are one failure mode: the session
backgrounded milestone 3 and ended its turn, and under `claude -p` turn end is process exit. #566
landed 2026-08-21 (`9f2b5d0`) and made milestone 3 run inline. Only `641-3` (08-22) post-dates it,
and that one was waiting on hand-launched suites rather than milestone 3. **The post-#566 corpus is
three spawns and one T** — statistically empty. Whatever the transport's residual failure rate is,
this corpus measured mostly a mechanism that no longer exists.

**3. Class M is a scheduler cost that `M1ᵗ` does not charge it for.**
Four spawns landed on issues already closed and merged — one of them collided with a concurrent
lane mid-run. That is a real defect and a real cost, and it is *not* transport, so the rubric as
pre-registered excludes it. Recorded here rather than folded quietly into `X`, because it is
evidence the reshape arm would want and the delete arm would want, and the criterion cannot see it.

## Rubric amendment made during scoring

| id | change | direction |
| --- | --- | --- |
| D-5 | Class **I** (infrastructure: API 5xx, network) added alongside P/S/X as not-counting-against | favours the scheduler |
| D-6 | Class **M** (mis-dispatch) added and reported separately rather than folded into X | neutral to `M1ᵗ`; visible instead of hidden |

Both were forced by evidence the rubric had no bin for. Neither moves a threshold, and D-5 moves
the reading *toward* the arm the author predicted against — recorded so that can be checked.

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
| `530-lean-spawn-4-build.log` | 1227 | M | spawned onto #530 after a concurrent lane had already merged it |
| `530-lean-spawn-5-build.log` | 833 | M | spawned onto #530 after it was closed and merged |
| `533-lean-spawn-1-build.log` | 1033 | M | spawned onto #533 after PR #556 had landed |
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

## Note on this file

This is a dated one-shot audit artifact, not a register. Nothing reads it, nothing maintains it,
and it must never acquire a row-update ritual — that is the distinction #641 landed in the
manifesto, and this file is on the measurement side of it.
