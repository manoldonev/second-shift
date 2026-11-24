# Decision record — #1374 Later review rounds re-review the whole diff, so new notes on unchanged code keep a run from converging

Receipt: v5

## Summary

A review of a PR that already has a lane verdict narrows which findings gate. Only findings on lines changed since the latest verdict's reviewed head gate, with two exceptions: a finding of the latest verdict that is still open, and a new blocker that pass 1 raises. A new note on unchanged code goes to `## Notes` with a `## Summary` action line for the merger. Pass 2 does not raise again what an earlier verdict accepted, and the join gates a plain finding only on a changed line.

Open regions: OR-1 and OR-2, six details the build fixes with a stated default.

Provenance legend: `user-answered` = the operator chose. `codebase-derived` = a fact from the code or the docs, with its proof. `deferred` = not decided yet, under an open region.

Open region legend: `reversible-default-and-flag` = the build uses the stated default.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | When a review narrows | A review narrows when the PR already has a lane verdict, from any run or from a hand review. The first review of a PR stays a full blind review. run: `grep -n 'ROUND=0' plugins/dev-pipeline/skills/run/run.sh` → 148: the round counter resets at every run start. Departs from the ticket's Proposed change rule 1: "The review of round N > 1" — this row keys on the PR's earlier verdicts, not on the run's round counter. | user-answered | intent |
| D-2 | Which review sessions narrow | Pass 1 and the plain review keep the whole base...head diff and stay record-blind. `run.sh` and `/dev-pipeline:review` hand pass 2 the latest verdict's reviewed sha and the changed-line set (D-6). Pass 2 and `verdict-join.sh` apply the narrowing. run: `grep -n '^review_prompt()' plugins/dev-pipeline/skills/run/run.sh` → 1189: it takes no reviewed sha today. From: F-1. Departs from the ticket's Proposed change rule 2: "It reviews only the lines changed since the last reviewed head" — the blind sessions still read the whole diff, and only the gate narrows. | user-answered | intent |
| D-3 | Where a new `[note]` on unchanged code goes | One `## Notes` line in a fixed shape: its file:line, then the defect. It does not gate. `## Summary` gets one action line for the human who merges. The build prompt says these lines are optional for the build. Both verdict-grammar copies change. run: `grep -n 'FINDINGS="\$STATE/verdict-findings.md"' plugins/dev-pipeline/skills/run/run.sh` → 2157: the build reads the whole verdict body, `## Notes` included. From: F-10 | user-answered | intent |
| D-4 | How rule 4 and the plain findings work in a later review | Pass 2 drops a finding that an earlier verdict accepted, unless its code changed. Accepted means a rebuttal the verdict agreed with, or a finding it turned into a ticket edit. Pass 2 decides this by judgment, with no marker. Both review-record-grounds copies gain this ground and the D-3 ground. In a later review, `verdict-join.sh` adds a plain finding only when its site is on a changed line. Inputs: the lane draft and the plain draft as today, plus an optional new flag that names a changed-line file (paths and line ranges). Outputs: the joined verdict. With the file, a plain finding outside it is left out of the body and counted in the plain-vs-lane line. Errors: exit 2 on usage or an unreadable lane draft, as today. An unreadable changed-line file follows OR-1. run: `sed -n 209,221p plugins/dev-pipeline/tools/verdict-join.sh` → plain notes are dropped near a lane Notes site, and every unpaired plain blocker is added. run: `grep -c 'Only three record grounds' plugins/dev-pipeline/skills/run/run.sh plugins/dev-pipeline/skills/review/SKILL.md` → 1 each. run: `gh pr view 1355 --json comments --jq '[.comments[].body \| select(test("verdict-check.sh:168"))] \| length'` → 10. From: F-9, F-10, F-24, F-25, F-26. Departs from the ticket's Proposed change rule 3: "A new finding on code unchanged since the last reviewed head is allowed only as a [blocker]" — a blocker there that only the plain review raises does not gate. | user-answered | intent |
| D-5 | How rule 1 checks the latest verdict's findings | Pass 2 judges each finding of the latest verdict against the head and the build's comments. A finding that is neither fixed nor validly rebutted is raised again and gates, even on unchanged code. A fixed finding is not mentioned. The verdict gets no new section. run: `grep -n '## Prior Round Context' plugins/review-toolkit/skills/review-lead/SKILL.md` → 764: review-lead has the same step. From: F-17 | user-answered | intent |
| D-6 | What counts as a changed line | A line within 3 lines of a hunk of `git diff <reviewed> <head>`, new side. The two-dot content diff survives a rebase and marks the base's own edits as changed. A reviewed sha whose object cannot be read gives a full review. run: `grep -n '^rebase_onto_base()' plugins/dev-pipeline/skills/run/run.sh` → 1482: the scheduler can rewrite the branch. From: F-28 | user-answered | intent |
| D-7 | When pass 2 reads the earlier verdicts | Last, with the build's account, in the step that reconciles departures and rebuttals. Rules 1 and 4 run inside that step, in the review prompt of `run.sh` and in step 8 of `review/SKILL.md`. | user-answered | intent |
| D-8 | The 150-word cap on `## Notes` | `verdict-check.sh` leaves the D-3 lines out of the word count. The verdict-style copies state the same exemption. run: `grep -n 'Notes of 150 words' plugins/dev-pipeline/tools/verdict-check.sh` → 175. From: F-12, F-18, F-29 | user-answered | intent |
| D-9 | Which verdict gives the last reviewed head | The latest comment by the bot or the operator account whose line 1 is `verdict:` and line 2 is `reviewed: <sha>`. It uses the bound-verdict filter of `run.sh` without its time window. A voided verdict counts, because it reviewed its own sha in full. run: `grep -n 'pr comment "\$PR" --body-file' plugins/dev-pipeline/skills/run/run.sh` → 1608: a verdict is posted before it binds. From: F-3 | user-answered | intent |
| D-10 | How the prompt half is proven | Selftests cover the scripts. The build replays the new pass 2 once on a later-round head of #1355 or #1368, with the earlier verdict's sha as the base. The PR shows that an accepted finding is not raised again and an open one is. PM-1 reads run outcomes after the release. run: `ls plugins/review-toolkit/evals/code-review-bench-eval/planted` → `__pycache__` only, so no multi-round harness exists. From: F-23 | user-answered | intent |
| D-11 | An AC block for the ticket | AC-1 to AC-7 and PM-1 were added to the ticket body, assembled from these rows, on the operator's yes. | user-answered | intent |
| D-12 | Test exemptions | AC-4, AC-6 and AC-7 are exempt from a per-AC test, because they are prompt behavior. The D-10 replay shows AC-4 and AC-6. | user-answered | intent |
| D-13 | The test form of AC-2 | `holds`. The behavior exists today, so its test stays off the fails-without-the-change check and still gets a test task. | user-answered | intent |
| D-14 | Which lockstep copies change | verdict-grammar, verdict-style and review-record-grounds, in `review/SKILL.md` and `run.sh`, plus verdict-style's third copy in `review-lead/SKILL.md`. A new block, review-later-round, holds the pass-2 rules of D-4, D-5 and D-16 in `review/SKILL.md` and `run.sh`. review-correctness does not change (D-2). `scripts/check-lockstep-pairs.sh` fails unless each group agrees. run: `grep -rl 'LOCKSTEP-BEGIN verdict-style' plugins` → 3 files. Changed in build: verdict-style has a third copy that the checker requires to match, and the later-review rules are stated in both review paths, so a lockstep block keeps them equal. | user-delegated | fact |
| D-15 | The D-3 line token, and the join on an unreadable changed-line file | Parked under OR-1. Owner: the build, which uses the stated default and flags it in the PR before review. | deferred | open |
| D-16 | A new blocker that pass 2 itself raises on unchanged code | It gates. This covers a row-reach blocker at an untouched caller, an untraced test-expectation change and a design-seat finding. Rows are still scored in full each round. | user-answered | intent |
| D-17 | A plain finding with no file:line in a later review | It gates, as today. The join cannot place it against the changed-line set, so it keeps it. | user-answered | intent |
| D-18 | A verdict with a `reason:` line as the last reviewed head | It is skipped. The last reviewed head comes from the latest lane verdict that has no `reason:` line, because a reason-line review did not finish. | user-answered | intent |
| D-19 | How many `## Summary` action lines the D-3 notes get | One line for all of them, which names their count and points at `## Notes`. It never presses the 8-line Summary cap. | user-answered | intent |
| D-20 | How the build runs the D-10 replay | Through the Agent tool, with the new pass-2 prompt rendered for a later-round head of #1368 or #1355 and an earlier verdict as input. The draft goes to the build's scratch and is never posted. The PR body shows its findings beside the earlier verdict's. | user-answered | intent |
| D-21 | Four implementation details that the code supports | Parked under OR-2. Owner: the build, which uses the stated defaults and flags them in the PR before review. | deferred | open |
| D-22 | The hunk that D-6 measures from | `tools/changed-lines.sh` reads `git diff -U0 <reviewed> <head>`, so a hunk is the changed lines alone, and marks each head line within 3 lines of one. A pure deletion marks the 3 lines on each side of the gap. Added in build: with the default 3 context lines, "within 3 lines of a hunk" would reach 6 lines from a change, which is not the join's proximity rule that D-6 reuses. | user-delegated | intent |
| D-23 | How the join places a site against the changed-line set | A site matches a range when its path equals the range's path or ends it after a `/`, and its line is inside the range. Added in build: a blind finding can name a file by a shorter path, and a missed match would leave out a finding on a changed line. | user-delegated | intent |
| D-24 | A verdict-shaped comment that a build session posts | It sets the last reviewed head like any comment that passes the D-9 filter. `changed-lines.sh` adds no review window and no `second-shift/review` status condition. The build prompt forbids the post, and pass 1, pass 2 and the row scores still gate as D-16 states. A status condition does not stop a bot-identity build: `run.sh:1331` grants it `Bash($GH *)`, which can post that status too. It would also drop the voided verdicts that D-9 counts. Without a bot, the build cannot post a status, so a status condition would stop it there; this row accepts that risk. Added in build: the review raised a build-posted verdict, and D-9 does not name the case. | user-delegated | intent |

Options weighed:

- D-1: (a) any earlier bound verdict, from any run or a hand review — run 2 of the evidence would narrow; (b) round > 1 of one run — a relaunch starts full again; (c) earlier run.sh verdicts only — needs a way to tell the two apart. The operator chose (a) because the evidence's non-convergence crossed run boundaries.
- D-2: (a) pass 2 and the join only — blind prompts and the bench arm unchanged; (b) blind sessions get the narrow diff — fewer new blockers found on unchanged code; (c) blind sessions see earlier verdicts — leaks the record through the rows table. The operator chose (a) because rule 3 still wants new blockers on unchanged code, and only a full read finds them.
- D-3: (a) Notes line and a Summary action — the merger owns it, and an approve can carry real work; (b) do not report it — real gaps like #1368's are lost; (c) Notes line and a follow-up issue — a tracker write with a jira path; (d) keep gating — needs-work rounds on such notes alone continue. The operator chose (a) twice, the second time after the #1368 evidence, because convergence is the goal and the notes stay visible with an owner.
- D-4: (a) pass 2 judges, and the join gates plain only on changed lines — no marker, and a blocker only plain sees on unchanged code does not gate; (b) pass 2 judges and the join is unchanged — plain's re-raises still gate; (c) a written withdrawn marker — more grammar and Notes cap pressure. The operator chose (a) because one join rule covers rules 3 and 4 for plain.
- D-5: (a) judge and write nothing new — mirrors review-lead's step; (b) a new earlier-findings section — grammar, checker and selftest changes. The operator chose (a) because it adds no section.
- D-6: (a) changed hunks, ±3 lines — reuses the join's proximity rule; (b) changed files — about 40% of the narrowing is lost; (c) full review after any rewrite — every rebase resets narrowing. The operator chose (a) because it reuses the existing proximity rule.
- D-7: (a) last, with the build's account — no new step; (b) first, before reviewing — earlier conclusions anchor the review. The operator chose (a) because it keeps the framing protection of step 8.
- D-8: (a) exempt those lines from the cap — a checker, fixture and selftest change; (b) no change — the cap can re-spawn the review. The operator chose (a) because the cap already exempts the knowledge-base block for the same reason.
- D-9: (a) the latest lane verdict comment — one read, the same in both paths; (b) the latest one with a review status — exact about binding, and falls back to a full review when a status post failed. The operator chose (a) because a voided verdict still reviewed its own sha in full.
- D-10: (a) one replay, then a post-merge read — one review session of cost (an estimate); (b) a post-merge read only — the prompt ships unproven; (c) a paired replay with k≥4 — a new harness. The operator chose (a) because a reviewer-prompt change is replayed before it ships.
- D-11: (a) add the AC block — the plan-coverage check and the probe apply; (b) no AC block — no plan-coverage check and no probe. The operator chose (a) because each line comes from a decision already made.
- D-12: (a) exempt AC-4, AC-6 and AC-7 — the replay proves the prompt half; (b) exempt AC-7 only — needs a mirror harness for pass 2. The operator chose (a) because prose-presence guards are not allowed.
- D-13: (a) holds — the test stays off the fails-without check; (b) a behavior line — the fails-without check goes red. The operator chose (a) because the behavior exists today.
- D-16: (a) it gates — rule-derived blockers do not churn and the record's guarantee holds; (b) Notes only — a violated row has no finding behind it. The operator chose (a) because rows are scored in full each round.
- D-17: (a) it gates — the conservative choice, and rare; (b) dropped — a siteless defect is lost. The operator chose (a) because the plain rubric requires a site, so the case is rare.
- D-18: (a) skip it — one more filter condition; (b) take it anyway — narrows against a head no review finished. The operator chose (a) because a reason-line review did not finish.
- D-19: (a) one line total — never presses the Summary cap; (b) one line per note — needs a second cap exemption. The operator chose (a) because the Summary cap is 8 lines.
- D-20: (a) the build runs it as an Agent — not the exact lane session shape; (b) the operator replays before merge — costs operator time; (c) post-merge only — reverses D-10. The operator chose (a) because the build has the Agent grant and the replay tests the prompt rules.

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | The token that marks a D-3 Notes line, and the join's exit on an unreadable changed-line file | reversible-default-and-flag |
| OR-2 | Four implementation details that the code supports | reversible-default-and-flag |

OR-1 default: a D-3 line reads `- later-round note: <file:line> — <defect>`, and an unreadable changed-line file makes `verdict-join.sh` exit 2, as an unreadable lane draft does. The intake agent chose both. Reversing either is a one-line change in the script and in the grammar copies.

OR-2 default: the intake agent chose each of these. Reversing any one is a change of a few lines.

- The D-3 sentence goes in both build prompts: `run.sh` and `build/SKILL.md`, which reads the same verdict.
- The join counts the plain findings it leaves out under a new key of the hidden plain-vs-lane JSON, and the JSON version goes up by one.
- The D-9 reader drops the filter's match on the current head and keeps its unedited-comment condition.
- A review that cannot read the PR comments is a full review, as AC-2 states for an unreadable reviewed sha.

## Test intent

ACs: AC-1 AC-2 AC-3 AC-4 AC-5 AC-6 AC-7

AC-1: with a lane verdict on the PR, the review gets that verdict's reviewed sha and a changed-line set that covers each line within 3 lines of a hunk of `git diff <reviewed> <head>`
AC-2: holds — with no earlier lane verdict, or an unreadable reviewed sha, the review gets no changed-line set and the join output is unchanged
AC-3: given a changed-line set, `verdict-join.sh` leaves out a plain blocker and a plain note sited outside it, and adds one sited inside it
AC-4: exempt — prompt behavior, shown by the D-10 replay
AC-5: `verdict-check.sh` passes an approve whose `## Notes` reaches 150 words only through D-3 lines
AC-6: exempt — prompt behavior, shown by the D-10 replay
AC-7: exempt — a build-prompt sentence that no test proves without a prose-presence guard

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | `verdict-join.sh` command line | contract (D-4) |
| S-2 | The `## Notes` word count of `verdict-check.sh` | decided (D-8) |
| S-3 | Verdict Notes and Summary lines the merger reads | decided (D-3) |
| S-4 | How the build reads the verdict body | decided (D-3) |
| S-5 | The pass-2 prompt in both review paths | decided (D-5) |
| S-6 | The last reviewed sha and changed-line set | decided (D-2) |
| S-7 | The first review of a PR | decided (D-1) |
| S-8 | The hidden plain-vs-lane JSON line | decided (D-4) |
| S-9 | review-lead's report join | out-of-scope — it passes no changed-line set, so the join behaves as today (AC-3). |
| S-10 | The pass-1 and plain prompts, and the bench arm | out-of-scope — D-2 keeps them unchanged. |
| S-11 | Run terminals and the round budget | out-of-scope — this ticket adds no terminal and keeps the round budget. |

## Checks

- `bash scripts/check-lockstep-pairs.sh`

## Intake steps

Requirements: the ticket body as written. spec-reviewer: not implementable as written. Its five blockers were design choices that the ticket left open, and the interview settled them. The ticket got an AC block and PM-1 on the operator's yes, and rules 1 to 3 were amended for D-1, D-2 and D-4. The implementability probe covered every AC and found 9 guess-points. Five became rows D-16 to D-20 on the operator's answers, and four got stated defaults under OR-2.

Split: not triggered. The ticket has no epic label and one deliverable. The register reached 13 intent rows, 3 of them AC bookkeeping, all on one review path, so it did not go back to Split.

Explore: done. Read the round loop, `review_prompt`, `blind_inputs` and `verdict()` in `run.sh`, `review/SKILL.md`, the pass-1 and plain prompts, `verdict-join.sh`, `verdict-check.sh`, `minimize-verdicts.sh` and the record of #1342.

Fan-out: ran — 30 items, see Fan-out

Dup-scan: no candidates at or above threshold 12

Post-merge scan: no AC needed moving. PM-1 was written with the new AC block (D-11).

Sizing: opus

<details>
<summary>Intake evidence: knowledge source and fan-out</summary>

## Knowledge source

Knowledge source: none declared

## Fan-out

Lenses: round-state-provenance opus 6 · blind-sessions-and-join opus 6 · gate-enforcement-inventory opus 6 · measure-catch-and-convergence opus 6 · premortem opus 6
Tally: rows added 8 · snapshot claims overturned 0 · questions added 3 (D-8, D-9, D-10)

| ID | Angle | Claim | Tag | Disposition |
| --- | --- | --- | --- | --- |
| F-1 | round-state-provenance | `review_prompt` takes no reviewed sha or changed range from the earlier round (`run.sh:1189`) | new | became D-2 |
| F-2 | round-state-provenance | Pass 2 can read minimized earlier verdicts with `gh pr view`, and the blind sessions cannot (`run.sh:1323`) | already-had | already had — D-2 |
| F-3 | round-state-provenance | A verdict posted and then voided is minimized like a bound one (`run.sh:1608`, `minimize-verdicts.sh:43`) | new | became D-9 |
| F-4 | round-state-provenance | The reviewed sha can stop being an ancestor of the head after a rebase (`run.sh:1482-1509`) | already-had | already had — D-6 |
| F-5 | round-state-provenance | `ROUND` resets on every launch, so a rule on `ROUND > 1` misfires (`run.sh:148`) | already-had | already had — D-1 |
| F-6 | round-state-provenance | The hand review minimizes earlier verdicts before its head-moved check (`review/SKILL.md:300-311`) | not material | not material — a pre-existing order bug, surfaced to the operator |
| F-7 | blind-sessions-and-join | The blind sessions see only the diff, the stripped ticket and a tree with no `.git` (`plain-review.sh:47-62`) | already-had | already had — D-2 |
| F-8 | blind-sessions-and-join | Pass 2 may read earlier verdicts, but no prompt line asks it to (`run.sh:1198`) | already-had | already had — D-2 |
| F-9 | blind-sessions-and-join | The join adds every unpaired plain blocker, and no Notes line drops one (`verdict-join.sh:209-221`) | new | became D-4 |
| F-10 | blind-sessions-and-join | review-record-grounds allows three grounds only, and the build reads `## Notes` too (`run.sh:1208`, `:2157`) | new | became D-3, D-4 |
| F-11 | blind-sessions-and-join | Giving blind sessions the earlier verdicts leaks the record through the rows table (`review/SKILL.md:218`) | already-had | already had — D-2 |
| F-12 | blind-sessions-and-join | Moved notes can break the 150-word Notes cap and re-spawn the review (`verdict-check.sh:175`) | new | became D-8 |
| F-13 | gate-enforcement-inventory | `verdict-check.sh` fails an approve with any finding, and its selftest pins that (`verdict-check.sh:193-199`) | new | no decision — D-3 lines are not findings |
| F-14 | gate-enforcement-inventory | The gate rule lives in two lockstep groups and four unlocked copies (`scripts/check-lockstep-pairs.sh`) | already-had | already had — D-14 |
| F-15 | gate-enforcement-inventory | The lane review has no round input, so only pass 2 or the join can narrow (`run.sh:1189`) | already-had | already had — D-2 |
| F-16 | gate-enforcement-inventory | Selftest cases j2n and vc8 pin today's join gating (`run-joined-selftest.sh:66-74`) | new | no decision — those cases pass no changed-line set |
| F-17 | gate-enforcement-inventory | review-lead already has a Prior Round Context step (`review-lead/SKILL.md:764`) | new | became D-5 |
| F-18 | gate-enforcement-inventory | Moved notes press on the Notes cap, and the list of files that change together (`verdict-check.sh:175`) | new | became D-8 |
| F-19 | measure-catch-and-convergence | 55 of 79 later-round findings in #1050-#1368 point at unchanged code (`gh api compare`) | new | shown in the D-3 and D-6 questions, no row |
| F-20 | measure-catch-and-convergence | On #1368, two later-round notes on untouched files were real gaps that the build fixed (#1368 comments) | already-had | already had — D-3 |
| F-21 | measure-catch-and-convergence | No data tells a note that is safe to defer from one a review must catch (`docs/review-panel-yield.md:244`) | already-had | already had — D-3 |
| F-22 | measure-catch-and-convergence | The plain-vs-lane JSON has no round or reviewed sha (`verdict-join.sh:27-36`) | not material | not material — PM-1 reads run outcomes, not this line |
| F-23 | measure-catch-and-convergence | No harness replays a multi-round review, and `planted/` is gone (`code-review-bench-eval/planted`) | new | became D-10 |
| F-24 | measure-catch-and-convergence | On #1355 one blocker on an unchanged file was raised on verdict after verdict (#1355 comments) | new | became D-4 |
| F-25 | premortem | With pass 2 alone, the plain review still gates new notes and re-raised blockers (`verdict-join.sh:222`) | new | became D-4 |
| F-26 | premortem | Rules 3 and 4 contradict review-record-grounds unless both copies change (`run.sh:1207-1209`) | new | became D-4 |
| F-27 | premortem | A rule keyed on the run's round lets each relaunch start with a full review (`run.sh:148`) | already-had | already had — D-1 |
| F-28 | premortem | After a rebase a two-dot diff marks base edits as changed, and a three-dot diff shows the whole PR (`run.sh:1469-1504`) | new | became D-6 |
| F-29 | premortem | Notes lines from rules 3 and 4 can exceed the cap and end the run review-unbound (`verdict-check.sh:175`) | new | became D-8 |
| F-30 | premortem | Notes moved to `## Notes` have no owner on an approve (`run.sh:2149`, `:2157`) | already-had | already had — D-3 |

### Snapshot

    # Snapshot — #1374, before the fan-out pool is read

    | ID | Decision | Resolution |
    | --- | --- | --- |
    | D-1 | When a review is a "later round" (trigger) | open — ask: any earlier bound verdict on the PR (any run, hand review too) vs round > 1 of one run.sh run |
    | D-2 | Which sessions narrow, and who applies rules 3-4 | open — ask: scheduler hands blind sessions the incremental diff, pass 2 + join apply 3-4 / pass 2 + join only / blind sessions see prior verdicts |
    | D-3 | A new [note] on unchanged code (rule 3) vs #1342 D-1 "every reported finding gates" | open — ask: Notes line owned by the human at merge / drop it / follow-up issue / keep gating |
    | D-4 | How an accepted rebuttal or withdrawn finding is recorded and carried (rule 4) | open — ask: fixed `## Notes` line form / pass 2 infers from prior verdicts + build comments |
    | D-5 | How rule 1 matches last-verdict findings and records the outcome | open — ask: pass 2 judges; unresolved re-raised, accepted ones withdrawn (D-4), fixed unmentioned / new per-finding section |
    | D-6 | Unit of "unchanged", and the fallback when the reviewed sha cannot be read | open — ask: changed hunks of `git diff <reviewed> <head>` (content diff, survives rebase) with join's 3-line proximity / changed files |
    | D-7 | When pass 2 reads the earlier verdicts | open — ask: at pass-2 start / after scoring, with the build's account |
    | D-8 | AC block for the ticket | open — ask at Receipt: amend the ticket with AC-n assembled from rows |
    | D-9 | Which copies change | fact: lockstep blocks verdict-grammar, review-record-grounds in review/SKILL.md + run.sh; review-correctness in pass-1-review.md + bench lane-review.md; check-lockstep-pairs.sh enforces byte-equality |

    ## Facts held

    - `run.sh:148` `ROUND=0` at every run start; evidence spans three runs on one PR.
    - `run.sh:1564-1580` a bound verdict is a Bot / operator comment, line 1 `verdict:`, line 2 `reviewed: <head>`.
    - `gh pr view 1355 --json comments` returns minimized earlier verdicts with `isMinimized: true`, `minimizedReason: outdated` — earlier verdicts are readable.
    - `verdict-join.sh:209-221` drops a plain note only within 3 lines of a lane finding, or of a lane `## Notes` line that starts with a site and quotes; every other plain note is added `[blind]` and flips an approve.
    - `run.sh:1351-1355` blind sessions get `origin/<base>...<head>` diff, plans dir excluded; `plain_ticket` strips lines naming the plans dir → blind sessions are record-blind.
    - The verdict's rows table quotes record content → a prior verdict handed to a blind session leaks the record.
    - `run.sh:1482` `rebase_onto_base` rewrites branch history: a `reviewed:` sha can stop being an ancestor of the head.
    - #1342 (PR #1355) D-1: every reported finding gates, `[note]` too; D-3: stale PR title is a `## Notes` line; D-6: the build fixes or rebuts every note.
    - `run.sh:1140` the build rebuts a finding in a PR comment; pass 2 reads the build's comments last (review/SKILL.md step 8).
    - review-lead uses `verdict-join.sh --format report` (single round, foreign PRs) — must stay unchanged.
    - spec-reviewer: not implementable as written; 5 blockers are design choices (D-2..D-5), gaps D-1, D-6, D-7, D-8; nit lockstep copies (D-9).

</details>
