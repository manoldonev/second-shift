# Decision record — #1383 A departure the operator decides during the build leaves the ticket stale, and the run re-reviews an unchanged head until rounds-spent

Receipt: v5

## Summary

The run gets a `no-progress` stop. In a round after the first of a launch, a build that leaves the head at the last reviewed sha ends the run before the checks and the review. The interactive build amends the ticket when the operator steers a departure from it. The `build-paused` detail line tells the operator to amend the ticket when the answer departs from it. A build-time departure row keeps the ticket's original text.

Open regions: none.

Provenance legend: `user-answered` = the operator chose. `codebase-derived` = a fact from the code or the docs, with its proof.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | When the run stops instead of re-reviewing | In every round after the first of a launch, a build that leaves the pushed head at the sha of the latest verdict this run bound stops the run. The check runs after the build is collected, before the checks run again. It reads no build reply and no tracker. The first round of every launch, `--resume` included, always gets a review. run: `grep -n "json title,body,comments" plugins/dev-pipeline/skills/run/run.sh` → 1205: pass 2 reads the ticket and its comments live. From: F-7, F-10, F-12. Departs from the ticket's Scope bullet 2: "When a round's build ends with the head unchanged since the last lane verdict, and every open blocker of that verdict names a ticket edit as its fix, the run stops". | user-answered | intent |
| D-2 | Which session amends the ticket | The interactive `/dev-pipeline:build` amends the ticket for a steer and for a pause answer given in its session. The lane build never amends the ticket. The `build-paused` detail line tells the operator to amend the ticket when the answer departs from it. Departs from the ticket's Scope bullet 1: "the build amends the ticket body" for "a `pause-and-ask` answer" also in the unattended lane. | user-answered | intent |
| D-3 | Form of a build-time departure row | The row carries `Departs from AC-n: <original text>.` or `Departs from the ticket's <part>: <original text>.` before its closing `Changed in build:` or `Added in build:` sentence. Both sites change: the record rules in run.sh `build_prompt` and build/SKILL.md step 3. | user-answered | intent |
| D-4 | An AC block for this ticket | The Receipt added AC-1 to AC-7 and PM-1 to the ticket body, after the operator saw the text. Plan coverage and the fails-without-the-change check then apply to this ticket. | user-answered | intent |
| D-5 | The new terminal | `no-progress`, rc 1. Inputs: none — it fires inside an existing run and adds no flag. Outputs: the last stdout line `terminal: no-progress`, exit code 1, and the D-6 detail in the run log, the PR's run block (D-14) and, under github, the ticket's closing comment. Errors: none — the stop is itself the exit; the worktree and the claim stay in place. Departs from the ticket's Scope bullet 2: "a new terminal (for example `ticket-edit-needed`, rc 1)". | user-answered | intent |
| D-6 | The `no-progress` detail line | The verdict URL, then each open finding's id with its first sentence, cut at about 600 characters in total. Then the recovery: edit the ticket or push a fix, then `--resume`, or run `/dev-pipeline:review <pr>` to weigh a rebuttal. An open finding is a `- [blocker] B<n>` or `- [note] N<n>` line of that verdict. | user-answered | intent |
| D-7 | How a build amends the ticket | Mirror the intake Receipt step: rewrite the departed text in place, keep its id and position, and change nothing else. On github, `gh issue view --json body`, edit, `gh issue edit --body-file`. Under jira, edit the description. cited (convention): plugins/intake-toolkit/skills/intake/receipt.md:66 | codebase-derived | fact |
| D-8 | Amend under jira `tracker.writes: false` | The interactive build makes no ticket write. It adds the ticket-edit request to the PR body's `## Before you merge`, as it does today. run: `grep -n "make no Jira write" plugins/dev-pipeline/skills/build/SKILL.md` → 87. From: F-21, F-22 | codebase-derived | fact |
| D-9 | Where a new rc-1 slug is listed | A line in the run.sh header exit table and the run SKILL.md rc-1 row. `exit_code_for` needs no edit, because an unlisted slug maps to 1. `terminal()`, herdr-adapter.sh and doctor read any slug. run: `grep -n '\*) echo 1 ;;' plugins/dev-pipeline/skills/run/run.sh` → 140. From: F-13, F-14 | codebase-derived | fact |
| D-10 | Selftest support for an unchanged head | run-later-round-selftest.sh is the later-round suite, and its one case (lr1) has no round with an unchanged head. The fake build mode `build-nothing` pushes nothing. run: `grep -n 'build-nothing' plugins/dev-pipeline/skills/run/run-selftest-lib.sh` → 211: build-nothing) : ;; From: F-11, F-15 | codebase-derived | fact |
| D-11 | Test for AC-4 | Exempt. The two tables are prose, and a test would be a prose-presence guard. | user-answered | intent |
| D-12 | Test for AC-6 | Exempt, plus PM-1 in the ticket body. The amendment is prompt text for an interactive session, which no selftest can run. | user-answered | intent |
| D-13 | Test for AC-7 | Exempt. The sentence is prompt text at two sites, and no script parses it. | user-answered | intent |
| D-14 | The `no-progress` detail on the PR | The run appends the D-6 detail to `RUN_NOTES` before the stop, so the PR's run block shows it. Other terminals keep a slug-only block. Under jira, the run block is the detail's only public place. | user-answered | intent |
| D-15 | Where the interactive build reads the amend step | Two sites: build/SKILL.md step 3 for a steer, and the `build_prompt` pause branch printed only under `--handoff` for a pause answer. The lane takes the other branch, so it gets no amend step. run: `grep -nF 'if [ "$HANDOFF" -eq 0 ]; then' plugins/dev-pipeline/skills/run/run.sh` → 1887: the scratch dir, and the lane pause branch, exist only without `--handoff` | codebase-derived | fact |

Options weighed:

- D-1: (a) relaunch rule — no tracker reads, works under jira, a rebuttal-only round stops; (b) read the tracker and skip build replies — GitHub reads, jira never stops; (c) every new PR comment counts — the build replies every round, so the stop rarely fires; (d) the ticket rule plus "ticket unchanged" — needs a new Fix marker, mixed blockers still burn; (e) the ticket rule as written — stops a run whose ticket was just fixed. user-answered chose (a) because it needs no Fix marker, reads no tracker, and the operator's relaunch signals an outside change.
- D-2: (a) in-session amend plus a note in the build-paused detail — smallest, no new lane grant; (b) in-session plus the lane build amends — needs a write grant and opens a trust gap; (c) in-session only — the lane pause path stays stale. user-answered chose (a) because the operator already edits the record by hand on that path.
- D-3: (a) add a `Departs from` sentence — the record keeps the original text; (b) keep `Changed in build:` only — the original text lives only in tracker history. user-answered chose (a) because the review reads the record, not the tracker history.
- D-4: (a) add an AC block at the Receipt — the scheduler's test checks apply; (b) keep the Scope bullets — `ACs: none`, judgment only. user-answered chose (a) because the plan coverage and fails-without-the-change checks need an AC block.
- D-5: (a) `no-progress`, rc 1 — names what the scheduler saw; (b) `ticket-edit-needed`, rc 1 — misleads when the open finding needs code; (c) `no-progress`, rc 4 — groups it with spent budgets, departs from rc 1. user-answered chose (a) because the stop also fires for a code fix that the build gave up on.
- D-6: (a) ids, first sentences and the recovery — act without opening the PR; (b) ids, URL and the recovery — shorter, the verdict must be opened. user-answered chose (a) because it follows the `pause_detail` pattern.
- D-11: (a) exempt — no prose-presence guard; (b) a test that greps `run.sh -h` — a prose-presence guard. user-answered chose (a) because the repo's test rules forbid prose-presence guards.
- D-12: (a) exempt plus PM-1 — the next real build confirms it; (b) exempt only — nothing records the behavior; (c) PM-1 only — pass 1 has no AC to score the prompt change. user-answered chose (a) because the review judges the diff and PM-1 checks the effect.
- D-13: (a) exempt — no prose-presence guard; (b) a test that greps the prompt — a prose-presence guard. user-answered chose (a) because the repo's test rules forbid prose-presence guards.
- D-14: (a) also in the run block through `RUN_NOTES` — only this slug's block changes, visible under jira; (b) as every terminal — log and github closing comment only. user-answered chose (a) because under jira no closing comment is posted.

## Open Regions

No open regions. Every decision in scope is settled.

## Test intent

ACs: AC-1 AC-2 AC-3 AC-4 AC-5 AC-6 AC-7

AC-1: a run where round 1 gets needs-work and the round-2 build pushes nothing ends `terminal: no-progress` with rc 1, and no second review starts
AC-2: a `--resume` launch whose round-1 build pushes nothing still starts a review
AC-3: the `no-progress` detail line carries the verdict URL, each open finding's id with its first sentence, and the recovery text
AC-4: exempt — the run.sh header table and the run SKILL.md table are prose, and a test would be a prose-presence guard
AC-5: the `build-paused` detail line asks the operator to amend the ticket when the answer departs from the ticket text
AC-6: exempt — prompt text for an interactive session that no selftest can run; PM-1 checks it after the merge
AC-7: exempt — prompt text at two sites that no script parses

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | `terminal: no-progress` exit line and code | contract (D-5) |
| S-2 | The `no-progress` detail text | decided (D-6) |
| S-13 | The PR run block on a `no-progress` stop | decided (D-14) |
| S-3 | The first round of a `--resume` launch | decided (D-1) |
| S-4 | run.sh header table and run SKILL.md rc table | decided (D-9) |
| S-5 | The `build-paused` detail line | decided (D-2) |
| S-6 | The ticket body after an interactive-build departure | decided (D-7) |
| S-7 | A build-time departure row in the record | decided (D-3) |
| S-8 | PR body `## Before you merge` under jira writes false | decided (D-8) |
| S-9 | Review prompt and verdict grammar | out-of-scope — the ticket keeps the review rule, and D-1 reads no Fix line. |
| S-10 | Lane build allowlist for ticket writes | out-of-scope — the lane build never amends the ticket (D-2). |
| S-11 | Intake Receipt amend step under jira writes false | out-of-scope — an intake-toolkit gap the pool found (F-22), not this ticket's change. |
| S-12 | README terminal table | out-of-scope — it lists launch-time terminals only, and no rc-1 stop. |

## Checks

- `bash plugins/dev-pipeline/skills/run/run-rows-selftest.sh`
- `bash scripts/check-lockstep-pairs.sh`

## Intake steps

Requirements: the ticket body as written. No design handoff. spec-reviewer: not implementable as written, with two blockers. The stop rule fired after the ticket was fixed, and no Fix marker exists. Both became interview questions (D-1). The Receipt amended Scope bullets 1 and 2 and added AC-1 to AC-7 and PM-1. implementability-probe: every AC covered, no meaning changed. Its two guess-points became D-14 (asked) and D-15 (fact).

Split: not split. About four files in two dev-pipeline areas, and both bullets edit run.sh. codebase-explorer mapped them.

Explore: done. Read run.sh's round loop, terminals, build prompt, pause path and allowlist, build/SKILL.md, changed-lines.sh and the run selftest lib.

Fan-out: ran — 30 items, see Fan-out

Dup-scan: no candidates at or above threshold 12

Post-merge scan: the ticket had no AC block. The new AC-6 stays an AC, and its observed effect became PM-1 (D-12).

Sizing: opus

<details>
<summary>Intake evidence: knowledge source and fan-out</summary>

## Knowledge source

Knowledge source: none declared

## Fan-out

Lenses: operator-journeys opus 6 · round-loop-stop-condition opus 6 · terminal-contract-consumers opus 6 · write-authority-and-tracker-parity opus 6 · premortem opus 6
Tally: rows added 3 · snapshot claims overturned 0 · questions added 1 (D-1)

| ID | Angle | Claim | Tag | Disposition |
| --- | --- | --- | --- | --- |
| F-1 | operator-journeys | The interactive build writes user-answered rows and never writes the ticket (`build/SKILL.md:47-52`) | already-had | already had — D-2 |
| F-2 | operator-journeys | A lane pause answer is a hand-written row before `--resume`, with no ticket edit (`run.sh:509`) | already-had | already had — D-2 |
| F-3 | operator-journeys | Under the bot or jira, only prompt text keeps a lane build from editing the ticket (`run.sh:1344`) | not material | not material — the lane build never amends the ticket (D-2) |
| F-4 | operator-journeys | The round loop has no unchanged-head guard, and each launch gets new rounds (`run.sh:2095`) | already-had | already had — D-1 |
| F-5 | operator-journeys | The code cannot tell which path wrote the incident's user-answered rows (`run.sh:1881`) | not material | not material — D-2 covers both paths that can write the rows |
| F-6 | operator-journeys | The intake Receipt amend step is the procedure to mirror (`receipt.md:64-74`) | already-had | already had — D-7 |
| F-7 | round-loop-stop-condition | A collected build always re-runs the checks before the later-review comparison (`run.sh:2095`) | already-had | became D-1 |
| F-8 | round-loop-stop-condition | An empty changed set also matches a new commit with an identical tree (`changed-lines.sh`) | not material | not material — D-1 compares shas, not the changed set |
| F-9 | round-loop-stop-condition | The verdict grammar holds no machine-readable Fix field (`verdict-check.sh:40-42`) | already-had | already had — D-1 |
| F-10 | round-loop-stop-condition | A later review also reads the live ticket, its comments and build replies (`run.sh:1205`) | already-had | became D-1 |
| F-11 | round-loop-stop-condition | No selftest runs a later round whose build leaves the head unchanged (`run-later-round-selftest.sh:23`) | new | became D-10 |
| F-12 | round-loop-stop-condition | A pause answer enters only through `--resume`, and "unchanged" needs a defined test (`run.sh:2074`) | already-had | became D-1 |
| F-13 | terminal-contract-consumers | An unlisted slug maps to rc 1, and two tables list rc-1 slugs (`run.sh:132-142`) | new | became D-9 |
| F-14 | terminal-contract-consumers | terminal(), herdr-adapter and doctor read any slug (`herdr-adapter.sh:71-73`) | new | became D-9 |
| F-15 | terminal-contract-consumers | The fake mode `build-nothing` exists, and the later-round suite is the home (`run-selftest-lib.sh:211`) | new | became D-10 |
| F-16 | terminal-contract-consumers | A ticket-edit test would match prose unless the grammar gains a form (`review/SKILL.md:286`) | already-had | already had — D-1 |
| F-17 | terminal-contract-consumers | The build-reply prose is one LOCKSTEP pair checked in CI (`run.sh:1146`) | not material | not material — the build-reply text does not change |
| F-18 | terminal-contract-consumers | Only the handoff path has the operator answer a pause in-session (`run.sh:1160-1162`) | already-had | already had — D-2 |
| F-19 | write-authority-and-tracker-parity | A github lane build can edit the ticket only through the bot wrapper (`run.sh:1344`) | not material | not material — the lane build never amends the ticket (D-2) |
| F-20 | write-authority-and-tracker-parity | Under jira `writes: false` the lane build loses editJiraIssue (`run.sh:430-432`) | not material | not material — the lane build never amends the ticket (D-2) |
| F-21 | write-authority-and-tracker-parity | The interactive build keeps Jira write tools, and only prose forbids a write (`build/SKILL.md:87`) | new | became D-8 |
| F-22 | write-authority-and-tracker-parity | The Receipt amend step states no fallback for a write it cannot make (`receipt.md:57-74`) | new | became D-8 |
| F-23 | write-authority-and-tracker-parity | Only provenance marks a row the operator decided during the build (`plan-coverage.sh:50-55`) | not material | not material — the interactive session knows the operator steered |
| F-24 | write-authority-and-tracker-parity | Nothing stops a lane build from writing user-answered on its own decision (`run.sh:1158`) | not material | not material — the lane build never amends the ticket (D-2) |
| F-25 | premortem | The ticket's stop fires on the round that would approve after a ticket edit (`run.sh:2047-2049`) | already-had | already had — D-1 |
| F-26 | premortem | The lane build cannot carry out a ticket amend under github or jira defaults (`run.sh:1344-1345`) | not material | not material — the lane build never amends the ticket (D-2) |
| F-27 | premortem | The lane has no same session in which the operator decides (`run.sh:509`) | already-had | already had — D-2 |
| F-28 | premortem | A forged user-answered row plus an amend would clear the review guard (`run.sh:1221`) | not material | not material — the lane build never amends the ticket (D-2) |
| F-29 | premortem | Blind sessions write code fixes, so "every blocker names a ticket edit" fails (`run.sh:1318`) | already-had | already had — D-1 |
| F-30 | premortem | The fake gh drops a body edit, and no case shows "0 changed ranges" (`run-selftest-lib.sh:69`) | not material | not material — D-1 reads no ticket body |

### Snapshot

    | ID | Decision | Resolution |
    | --- | --- | --- |
    | Q-1 | Stop condition for the no-progress terminal | open — ticket form (head unchanged + every open blocker's Fix names a ticket edit) stops wrongly after the ticket is fixed (spec-reviewer blocker 1); Fix is free prose (run.sh:1318), no marker (blocker 2). Candidates: ticket form; + ticket unchanged; general no-progress (head + ticket + PR comments unchanged) |
    | Q-2 | Terminal slug and rc | open — depends on Q-1; ticket suggests ticket-edit-needed rc 1; exit_code_for defaults unknown slugs to 1 |
    | Q-3 | How "ticket unchanged" is known across --resume and under jira | open — STATE is per run (run.sh:316); the scheduler snapshots the github body per review (plain_ticket, run.sh:1369); it reads no jira ticket |
    | Q-4 | Which sessions amend the ticket | open — interactive build step 3 writes user-answered (build/SKILL.md:49); handoff pause answer (run.sh:1162); lane pause answer arrives as an operator-written row before --resume (run.sh:509); lane build writes user-delegated only (run.sh:1154) |
    | Q-5 | Guard against a lane build amending the ticket on a user-answered row it wrote itself | open — depends on Q-4 |
    | Q-6 | Lane build's ticket-write grant | open — build_allowlist has gh issue view only (run.sh:1344); Bash($GH *) when the bot is ok (run.sh:1345) |
    | Q-7 | Departure sentence on build-time rows | open — intake rows end `Departs from AC-n:` (baseline "Departures"); build rows end `Changed in build:`/`Added in build:`; no script parses either |
    | Q-8 | AC block for this ticket | open — ticket has none; plan coverage and fails-without-change are not-applicable without one |

    Facts held:
    - jira tracker.writes defaults false (run.sh:241); Atlassian write tools disallowed then (run.sh:431); build/SKILL.md:87 forbids Jira writes under writes:false.
    - Amend procedure to mirror: receipt.md "3. Amend the ticket" (rewrite in place, keep id and position, change nothing else).
    - Out of scope: review rule run.sh:1221; user-delegated rows never amend.
    - A run.sh behavior change needs a run*-selftest.sh case that fails without it (CLAUDE.md).
    - Not split: ~4 files, 2 modules of dev-pipeline; both bullets edit run.sh.
    - Knowledge source: none declared.

</details>
