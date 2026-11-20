# Decision record — #1342 An approve verdict carries actionable notes that nothing addresses

Receipt: v4

## Summary

The lane review reports only relevant findings: those a distinguished engineer who knew of them would definitely address before merge. Every reported finding gates, a `[note]` the same as a `[blocker]`. So an approve carries no finding, and the build fixes or rebuts every finding.

Both tags keep their meaning as the kind of problem. The verdict checker, the join of the blind review and the planted eval scorer change to match.

The ticket asked to keep non-actionable notes on an approve and to list them in the run report. The operator dropped both: an approve now has no findings to list.

Open regions: OR-1 a note also gets a `Fix:` line. OR-2 the join matches and adds blind notes. OR-3 the planted plain arm stays as it is. OR-4 non-findings go to `## Notes`. OR-5 the new scoring covers the lane and joined arms.

Provenance legend: `user-answered` = the operator chose. `codebase-derived` = a fact from the code or the docs, with its proof.

Open region legend: `reversible-default-and-flag` = the build uses the stated default.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Which findings the verdict reports, and which gate | Only relevant findings: one a distinguished engineer who knew of it would definitely address before merge. Every reported finding makes the verdict needs-work, `[blocker]` or `[note]`. An approve carries no finding. Departs from the ticket's Scope bullet 1: the bar is the operator's distinguished-engineer test, not the 80/20 test. Departs from the ticket's Scope bullet 2: no non-actionable note rides on an approve. | user-answered | intent |
| D-2 | The kind rules that pin a kind to `[note]` | A maintainability, test-coverage, repo-convention, over-engineering or performance-bound finding is reported only when it passes the D-1 bar. Then it gates like any finding. The "never a `[blocker]`" and "always a `[note]`" rules pick the tag only. | user-answered | intent |
| D-3 | What is not a finding | A stale or wrong PR title or description is one line in `## Notes`, which never gates. A break that the ticket or a record row accepts is not a finding. Its row's Evidence cell quotes the acceptance. A test-intent exemption is not a finding. Dismissed and suppressed findings are not listed. | user-answered | intent |
| D-4 | The tags, and what `verdict-check.sh` enforces | Both tags stay, with no relabeling. `verdict-check.sh` fails an approve that carries any `[blocker]` or `[note]`. It passes a needs-work whose only findings are `[note]`s. Inputs: the body file, the record at the head and the record at the first commit, all required. Outputs: exit 0 when the body passes. Errors: exit 1 with one line per broken rule, among them an approve that carries a `[note]`. Exit 2 on usage or an unreadable file. run: `grep -n 'approve with a blocker\|needs-work with no blocker' plugins/dev-pipeline/tools/verdict-check.sh` → 167 fails an approve on blockers only. 171 fails a needs-work with no blocker | user-answered | intent |
| D-5 | The blind review and the join | `plain-review.md` applies the D-1 bar to both tags and drops "that does not block merge" from its `[note]` line. With `--format verdict`, `verdict-join.sh` adds an unmatched blind `[note]` to `## Findings` as a `[blind]` note, and it flips an approve as a blind blocker does. `--format report` does not change. Inputs: the lane draft and the plain draft, both required. The optional flags do not change. Outputs: the joined body and the `plain-vs-lane` machine line. Errors: none new. Its exit codes do not change. run: `grep -n 'flip = ' plugins/dev-pipeline/tools/verdict-join.sh` → 306 flips on `nadd`, which counts blind blockers only | user-answered | intent |
| D-6 | What the needs-work build does | The build fixes or rebuts every finding, `[note]`s included. This applies to `run.sh:1143` and `build/SKILL.md:63`. "A `[note]` requires nothing" leaves the verdict-grammar and verdict-style blocks. run: `grep -n 'requires nothing' plugins/dev-pipeline/skills/run/run.sh plugins/dev-pipeline/skills/build/SKILL.md` → run.sh 1143, 1269, 1303. build/SKILL.md 63 | user-answered | intent |
| D-7 | The run report on an approve | It adds nothing: an approve has no finding to list. Departs from the ticket's Scope bullet 4 and the second case of Scope bullet 5. | user-answered | intent |
| D-8 | The round budget | `MAX_ROUNDS` stays 3. The rates of `rounds-spent` and `checks-red-spent` are read from runs after the release. A change to the budget is its own ticket. run: `grep -n 'MAX_ROUNDS=3' plugins/dev-pipeline/skills/run/run.sh` → 100 | user-answered | intent |
| D-9 | Which copies of the rule change | Every copy changes in the same PR. `review-correctness` has three copies: `review/SKILL.md`, `run.sh` and the bench arm `lane-review.md`. `verdict-grammar` and `verdict-style` have two each. The notes-pass sentence has two unmarked copies, at `run.sh:1218` and `review/SKILL.md:94`. `scripts/check-lockstep-pairs.sh` fails unless each marked copy is byte-equal. run: `grep -c 'LOCKSTEP-BEGIN review-correctness' plugins/dev-pipeline/skills/review/SKILL.md plugins/dev-pipeline/skills/run/run.sh plugins/review-toolkit/evals/code-review-bench-eval/arms/lane-review.md` → 1, 1, 1 | codebase-derived | fact |
| D-10 | How the relevance call is checked | `planted.py` counts a `[note]` as send-back, as it counts a `[blocker]`. A hit is right, an unmatched one is noise, and one on a control case is harm. The lane and joined arms accept a needs-work that holds only notes through `verdict-check.sh`. `plain_problems` keeps the plain arm's contract: a needs-work with no `[blocker]` is unscorable, because `planted/arms/plain.md` still requires one (OR-3). PM-1 runs the replay after the release. It compares with the last lane baseline re-scored by `planted.py --rescore`. run: `grep -n 'severity"\] == "blocker"\|cls == "P5"' plugins/review-toolkit/evals/code-review-bench-eval/planted/planted.py` → 811, 871 blockers only. 885 the P5 note branch. Changed in build: a `plain_problems` that accepts a note-only needs-work scores records that break the unchanged plain prompt, which raises plain's best net and moves the gate for reasons outside the lane. | user-delegated | intent |
| D-11 | What a scheduler selftest can prove | The scheduler half only. The review in `run-selftest.sh` is a fake that posts canned bodies, and no plan posts a note-only verdict. So Scope bullet 5's first case is a canned needs-work whose only finding is a convention `[note]`. Today it is rejected and the run ends `review-unbound`. With the change it starts round 2. run: `grep -n 'review-approve\|review-needs-work' plugins/dev-pipeline/skills/run/run-selftest-lib.sh` → 258, canned verdict plans | codebase-derived | fact |
| D-12 | The checker's rule name for a needs-work with nothing to fix | `verdict-check.sh` prints `needs-work with no finding`, not `needs-work with no blocker`. It fires on a needs-work with no finding, no violated or undeterminable row and no reason line. Added in build: a note-only needs-work now passes, so the old name misstated the rule. | user-delegated | intent |
| D-13 | Where a row's performance bound goes when it is not relevant | A bound that breaks no caller, no stored data and no row is a `[note]` when it passes the D-1 bar, and one line in `## Notes` when it does not. Added in build: the prompt required every bound stated as a finding, and D-2 makes a bound below the bar no finding. | user-delegated | intent |
| D-14 | How `planted.py` scores a stored lane approve that carries a `[note]` | On the lane and joined arms a `[note]` sends back only on a needs-work. A stored approve with a note is an approve: no harm on a control, wrong on a planted case. Added in build: `--rescore` reuses old lane records, and counting their notes as send-back skews PM-1's baseline. | user-delegated | intent |
| D-15 | How a mechanism or a cost risk that the operator decided leaves the gate | An over-engineering point on a mechanism that the ticket's text prescribes, or that a `user-answered` or `ticket-sourced` row prescribes, is one line in `## Notes` that starts with its file:line and quotes the decision. A performance bound within a risk that such a row accepts takes the same line. With `--format verdict`, `verdict-join.sh` leaves out a blind note within 3 lines of a site that starts a lane `## Notes` line, and counts it in `plain_notes_dropped`. Added in build: under D-1 every note gates, so a note on a decision the build must keep came back each round and spent the round budget. | user-delegated | intent |

Options weighed:
- D-1: keep non-actionable notes with a why-left reason, as the ticket wrote, or report only relevant findings and gate on all of them. The operator chose relevant findings only.
- D-2: yield the code kinds, yield only the named kind rule, or yield everything including PR text. The operator chose the code kinds.
- D-3: a stale PR text gates, or it moves to `## Notes`. The operator chose that PR text and record grounds never gate.
- D-4: write every finding as `[blocker]`, or keep both tags and gate on both. The operator chose both tags.
- D-5: the same bar for the blind review, or leave its notes dropped. The operator chose that every relevant finding is addressed, blind ones included.
- D-8: keep 3 rounds and measure, or raise the default to 4. The operator chose to keep 3.
- D-10: a post-merge replay with the scorer fixed in the PR, a replay before merge, or no replay. The operator chose the post-merge replay.

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | The `Fix:` line on a `[note]` finding | reversible-default-and-flag |
| OR-2 | How the join matches, adds and counts blind notes | reversible-default-and-flag |
| OR-3 | The planted eval's plain arm, `planted/arms/plain.md` | reversible-default-and-flag |
| OR-4 | Where a non-finding the review must still show is written | reversible-default-and-flag |
| OR-5 | Which planted arms the new scoring covers, and the P5 approve rule | reversible-default-and-flag |

- OR-1 default: every finding ends with `Fix: <one instruction>`, a `[note]` too, because the build now addresses it. The intake chose it. Reversal is one verdict-style line in two copies.
- OR-2 default: a blind note is matched against every lane finding, notes included, by the existing site rule. A matched one is not listed twice. An unmatched one is added as a `[blind]` note with the next `N<n>` id. The machine line keeps every key. `plain_only` counts added blind blockers and notes. `plain_notes_dropped` counts the blind notes the join leaves out, which is 0 in the new flow. The intake chose it. Reversal is a few awk lines.
- OR-3 default: `planted/arms/plain.md` stays as it is, because it is the comparison baseline. The intake chose it. Reversal is one edit and a new baseline row.
- OR-4 default: a break that only the ticket text accepts, a test-intent exemption and a process note each get one line in `## Notes`. A break a record row accepts is quoted in that row's Evidence cell. The intake chose it. Reversal is one prompt sentence per case.
- OR-5 default: a `[note]` counts as send-back for the lane and joined arms only. The plain arm keeps today's scoring, as OR-3 keeps its prompt. For the lane and joined arms, an approve that misses a planted P5 case is wrong. The intake chose it. Reversal is a `--rescore` of the stored results.

## Test intent

ACs: none — the ticket has no AC-n block. Its Scope bullets and the D-n rows carry the behavior.

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | The lane verdict's `## Findings` grammar | contract (D-4) |
| S-2 | `verdict-check.sh` arguments and exit codes | contract (D-4) |
| S-3 | `verdict-join.sh` joined body and machine line | contract (D-5) |
| S-4 | The blind review prompt `plain-review.md` | decided (D-5) |
| S-5 | The round-2 build prompt and the `/dev-pipeline:build` handoff | decided (D-6) |
| S-6 | The PR run block and the `approved` terminal line | decided (D-7) |
| S-7 | The manual `/dev-pipeline:review` prompt and status post | decided (D-9) |
| S-8 | The bench eval's lane arm `lane-review.md` | decided (D-9) |
| S-9 | The planted eval scorer `planted.py` | decided (D-10) |
| S-10 | The planted eval's plain arm | decided (D-10) |
| S-11 | The review-lead foreign-PR report | out-of-scope — it emits no `verdict:` line, and its join flips on "Ready to merge?". |

## Checks

- `bash scripts/check-lockstep-pairs.sh`
- `bash plugins/dev-pipeline/tools/verdict-check-selftest.sh`
- `bash plugins/dev-pipeline/tools/verdict-join-selftest.sh`
- `bash plugins/review-toolkit/evals/code-review-bench-eval/planted/score-selftest.sh`

## Intake steps

Requirements: the ticket body as written. spec-reviewer: needs-spec-work, with 3 blockers. All three were design decisions for the interview, not spec failures. The interview settled them.

Split: not triggered. The ticket has no `epic` label and one deliverable.

Explore: done. Read `verdict-check.sh`, `verdict-join.sh`, the review prompts in `run.sh` and `review/SKILL.md`, `plain-review.md`, the build prompt, `run_report` and the planted scorer.

Fan-out: ran — 24 items, see Fan-out

Dup-scan: no candidates at or above threshold 12

Post-merge scan: the ticket had no post-merge AC. On the operator's answer, PM-1 was added to the ticket body: a planted-eval replay after the release.

Sizing: opus

<details>
<summary>Intake evidence: knowledge source and fan-out</summary>

## Knowledge source

Knowledge source: none declared

## Fan-out

Refuter: cross (opus/fable alternating)
Lenses: rule-carrier-inventory opus 6/6 · verdict-parsers fable 4/6 · round-loop-convergence opus 5/6 · operator-report-and-tests fable 4/6 · premortem fable 5/6
Tally: rows added 2 · snapshot claims overturned 0 · questions added 2

| ID | Angle | Claim | Tag | Disposition |
| --- | --- | --- | --- | --- |
| F-1 | rule-carrier-inventory | The review-correctness block has three copies, one in the bench arm (`lane-review.md:13-19`) | already-had | became D-9 |
| F-2 | rule-carrier-inventory | The verdict-grammar and verdict-style pairs each say a note requires nothing (`run.sh:1269,1303`) | new | became D-6 and D-9 |
| F-3 | rule-carrier-inventory | The notes-pass sentence has two unmarked copies, and only the run.sh one is tested (`run.sh:1218`) | new | became D-9 |
| F-4 | rule-carrier-inventory | The build's note-optional rule has two unmarked copies (`build/SKILL.md:63`) | already-had | became D-6 |
| F-5 | rule-carrier-inventory | The blind review defines a note as a problem the author would fix (`plain-review.md:40`) | new | became D-5 |
| F-6 | rule-carrier-inventory | The checker and the join gate on blockers only (`verdict-join.sh:306`) | already-had | became D-4 and D-5 |
| F-7 | verdict-parsers | A note-only needs-work fails the checker and ends review-unbound (`verdict-check.sh:171`) | already-had | became D-4 |
| F-8 | verdict-parsers | The checker cannot see a mark inside a finding's text (`verdict-check.sh:144-151`) | not material | not material — no mark is used, per D-4 |
| F-9 | verdict-parsers | The join drops blind notes and classes Dismissed and Suppressed apart (`verdict-join.sh:92,221`) | new | became D-5 and OR-2 |
| F-10 | verdict-parsers | The planted scorer counts only blockers as send-back (`planted.py:871-889`) | new | became D-10 |
| F-11 | round-loop-convergence | The checks-red counter is never reset between rounds (`run.sh:149`) | new | became D-8 |
| F-12 | round-loop-convergence | Whether a rebutted finding returns is each fresh review's judgment (`run.sh:1244`) | new | not material — measured after the release, per D-8 |
| F-13 | round-loop-convergence | The blind review cannot see rebuttals, so a blind finding can recur (`plain-review.sh:103`) | new | became D-8 question |
| F-14 | round-loop-convergence | A rejected verdict re-spawns once, then ends review-unbound (`run.sh:2152`) | already-had | became D-4 |
| F-15 | round-loop-convergence | The run prompt and the build skill both free the notes (`run.sh:1143`) | already-had | became D-6 |
| F-16 | operator-report-and-tests | The run report has four surfaces, and none is named (`run.sh:160-169`) | already-had | not material — report bullet dropped, per D-7 |
| F-17 | operator-report-and-tests | The checker rejects the body the ticket's first selftest case needs (`verdict-check.sh:171`) | already-had | became D-11 |
| F-18 | operator-report-and-tests | No fake plan posts an approve or a needs-work with only a note (`run-selftest-lib.sh:258`) | new | became D-11 |
| F-19 | operator-report-and-tests | The joined review is the default, and blind notes leave the body (`run.sh:309`) | new | became D-5 |
| F-20 | premortem | More findings gate, so more runs end rounds-spent (`gh` sample of verdicts) | new | became D-8 question |
| F-21 | premortem | The opposite rule appears in about nine places, not one (`run.sh:1212-1303`) | already-had | became D-2 and D-9 |
| F-22 | premortem | The fake review cannot show the relevance call (`run-selftest-lib.sh:4`) | already-had | became D-10 and D-11 |
| F-23 | premortem | On the joined path the invariant holds for the lane half only (`verdict-join.sh:13`) | new | became D-5 |
| F-24 | premortem | The run report is folded, and the session reads only the terminal (`run.sh:2182`) | already-had | not material — report bullet dropped, per D-7 |

### Snapshot

    | ID | Decision | Resolution |
    | --- | --- | --- |
    | D-1 | How the verdict marks an actionable finding | Recommend: an actionable finding is a `[blocker]`, whatever its kind; `[note]` means non-actionable only. verdict-check.sh is unchanged: it already derives needs-work from a `[blocker]` (verdict-check.sh:148,167,171) |
    | D-2 | Which "always a note" rules yield to the 80/20 test | Recommend: the kind rule (run.sh:1212), "over-engineering is always a note" (run.sh:1214) and the performance-bound "note otherwise" (run.sh:1236) yield. A stale PR title or description stays a note (not the diff). Operator-accepted breaks and test-intent exemptions stay (operator decisions) |
    | D-3 | Form of a non-actionable note's "why leave it" reason | Recommend: one `Left: <reason>` continuation line on each note that is not Dismissed/Suppressed; prompt-only, verdict-check.sh does not enforce it |
    | D-4 | Where the run lists the approve's remaining notes | Recommend: the terminal `approved` detail line (the driving session relays it; closing issue comment carries it) and the PR run block; run.sh extracts `- [note] N<n>` lines from $STATE/verdict-body.md; run/SKILL.md exit-0 row says to relay them |
    | D-5 | Which notes are listed | Recommend: notes that are not `Dismissed.`/`Suppressed.`; id, file:line (or the rule name), first sentence |
    | D-6 | Bench eval lane arm (lane-review.md) in the review-correctness LOCKSTEP group | Recommend: it takes the new text; check-lockstep-pairs.sh forces byte-equality across review/SKILL.md, run.sh and lane-review.md |
    | D-7 | How the actionable call is verified | Recommend: a planted-eval replay (P5 + control harm) as a post-merge check; run-selftest cases cover the scheduler parts only (report listing) |
    | D-8 | Round budget | Unchanged MAX_ROUNDS=3 (run.sh:100) |
    | D-9 | Manual /dev-pipeline:review path | Gets the 80/20 rule through the shared LOCKSTEP text; no extra notes listing |
    | D-10 | #1010 D-7 ("a [note] requires nothing") | Stays true under D-1: a note is non-actionable by definition; build prompt run.sh:1143 and build/SKILL.md:63 unchanged |
    | D-11 | Selftest strings that change | run-selftest.sh:64 (notes pass text) and :150-152 ((b3) note optional) follow any rewording |

</details>
