# Decision record — #1379 A later review verdict says nothing about the findings it saw resolved

Receipt: v5

## Summary

A later review lists every finding the PR had that is now resolved, in a fold in `## Notes`, before the knowledge-base block. Each review adds the resolved findings and later-round notes of the latest verdict, and copies that verdict's resolved lines. An empty `## Findings` with resolved lines reads `None open. <n> resolved, listed in ## Notes.`, and `verdict-check.sh` holds the count. `verdict-join.sh` drops that line when a blind finding is added.

Open regions: OR-1, a finding listed as resolved that a later round raises again. The build removes its resolved line while it is open.

Provenance legend: `user-answered` = the operator chose. `codebase-derived` = a fact from the code or the docs, with its proof. `deferred` = not decided yet, under an open region.

Open region legend: `reversible-default-and-flag` = the build uses the stated default.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Which resolved findings a later verdict lists | Every resolved finding the PR had, chained. The review adds the latest verdict's findings that are now resolved, and copies every `- resolved:` line of the latest verdict. Verdicts written before this change carry no resolved lines, so their findings are not listed. Departs from the ticket's Proposed change: it listed only "each finding of the latest lane verdict that is now resolved". | user-answered | intent |
| D-2 | How a long resolved list stays readable, and where it sits | Always a fold, after the prose notes and before the knowledge-base block, with no `###` heading of its own. Its first line is `<details><summary><n> resolved</summary>`, then the resolved lines, then `</details>`. A verdict with no resolved line has no fold. The knowledge-base block stays last. | user-answered | intent |
| D-3 | The exact resolved line | `- resolved: <file:line> — <defect> — <how>`. `<how>` is `fixed`, `rebuttal accepted: <why>` or `ticket edited`. The line has no finding id and no sha. Ids restart in every verdict, and a rebase removes the shas. Departs from the ticket's Proposed change: it gave `- resolved: <id> <file:line> — <how>` with `fixed in <sha>`. | user-answered | intent |
| D-4 | The `## Findings` line when nothing is open but resolved lines exist | Exactly `None open. <n> resolved, listed in ## Notes.` in place of `None.`, in an approve or a needs-work. `verdict-check.sh` accepts it as no finding. `verdict-join.sh` drops it when it adds a blind finding, as it drops `None.`. A verdict with no resolved line keeps `None.`. The grammar sentence changes in both verdict-grammar copies. run: `sed -n '158p;262p'` on verdict-check.sh and verdict-join.sh → `if ($0 == "None.")` and `if (s == "None." && nadd + naddn > 0) continue` | user-answered | intent |
| D-5 | A fixed later-round note of the latest verdict | It gets a resolved line in the same form. The sentence "Do not mention a fixed one" in review-later-round changes in both copies. Departs from the ticket's Proposed change: it covered only the findings of the latest lane verdict. | user-answered | intent |
| D-6 | Which lockstep copies change | review-later-round and verdict-grammar in `run.sh` and `review/SKILL.md`. verdict-style in `run.sh`, `review/SKILL.md` and `review-lead/SKILL.md`: each copy exempts the resolved lines and the two fold lines from the 150-word Notes count and from the six-sentence limit under a sub-heading. The review-lead copy changes in text only. run: `grep -c 'Write at most six sentences under it' plugins/dev-pipeline/skills/run/run.sh plugins/dev-pipeline/skills/review/SKILL.md plugins/review-toolkit/skills/review-lead/SKILL.md` → 1 in each. From: F-21 | codebase-derived | fact |
| D-7 | The resolved count | `verdict-check.sh` fails a verdict whose `<n>` in the `None open.` line or in the fold's summary differs from the number of `- resolved:` lines. The grammar names the count in both places, so the style rule "State each fact once" does not apply to it. run: `grep -n 'State each fact once' plugins/dev-pipeline/skills/run/run.sh` → 1303. From: F-24 | user-answered | intent |
| D-8 | An AC block for the ticket | AC-1 to AC-6 and PM-1 were added to the ticket body on the operator's yes. Proposed change and Where it lands were rewritten in place to state D-1 to D-7. | user-answered | intent |
| D-9 | How the review-prompt half is proven | AC-1 and AC-2 are exempt from a per-AC test, because they are review-prompt behavior. The build runs one replay through the Agent tool and never posts it: the new prompt on #1376's last needs-work verdict, reviewed `12b5cfd4`, against head `b33c970f`. The PR body reports the replay's draft. PM-1 reads real runs after the release. | user-answered | intent |
| D-10 | The test form of AC-6 | `holds`. A first-review approve with `None.` passes today, so its test stays off the fails-without-the-change check and still gets a test task. | user-answered | intent |
| D-11 | The `verdict-check.sh` interface | Unchanged. Inputs: the verdict body file (required), then the record at the head and at the first commit (optional, together). Outputs: one line per broken rule. Errors: exit 1 when a rule breaks, exit 2 on a usage error or an unreadable file, exit 0 on a pass. run: `sed -n '47,49p' plugins/dev-pipeline/tools/verdict-check.sh` → `exit 2` on usage and on an unreadable file | codebase-derived | fact |
| D-12 | A finding listed as resolved that a later round raises again | Parked under OR-1. Owner: the build, which uses the stated default and flags it in the PR before review. | deferred | open |
| D-13 | What `verdict-check.sh` enforces besides the count | It fails a bare `None.` beside resolved lines. It fails resolved lines with no fold, a fold with no resolved line, and `None open. 0 resolved`. It does not check where the fold sits, because the join appends its own lines after it. | user-answered | intent |
| D-14 | The `<file:line>` slot of a finding that had none | The rule or row id that the finding named, as the finding itself did, for example `- resolved: D-4 — <defect> — fixed`. The checker counts by prefix, so it is unaffected. | user-answered | intent |
| D-15 | A blank line after the fold's summary line | Yes, as the rows fold has. GitHub renders the Markdown list inside an HTML block only after a blank line. run: `sed -n '130,132p' plugins/dev-pipeline/tools/verdict-check.sh` → the rows fold fails when no blank line follows its summary line | codebase-derived | fact |
| D-16 | Which verdict the D-9 replay treats as the latest | The needs-work verdict that reviewed `12b5cfd4`. The replay hands it to the review as the latest lane verdict and leaves out the later approve, which has no finding to resolve. run: `gh pr view 1376 --json comments` → the last two verdicts are needs-work on 12b5cfd4, then approve on b33c970f | codebase-derived | fact |
| D-17 | A resolved fold with no `</details>` line | `verdict-check.sh` fails it as `resolved fold not closed`, as it fails a rows fold with no `</details>`. It adds one shape rule to D-13's list. Added in build: an open fold hides the knowledge-base block and the join's `lane vs blind:` line, and the last review raised it. | user-delegated | intent |

Options weighed:

- D-1: (a) all, chained — the review copies the latest verdict's resolved lines and adds its newly resolved findings, a dropped line is gone for good; (b) all, rebuilt each time — reads every earlier verdict each round, more tokens; (c) only the latest verdict's — smallest, most history stays hidden. The operator chose (a) because it matches the kb-contributions carry rule and fixes the 15-verdict example.
- D-2: (a) always fold — short to read, count visible, fold lines exempt; (b) plain lines — 20 or more lines bury the prose notes; (c) fold above a count — a threshold and two forms to check. The operator chose (a) because it keeps the approve short and shows the count. On the place: (a) before the knowledge-base block — the kb-last rule and the checker's kb skip stay; (b) after it — three style copies and the checker change; (c) its own `###` heading — the heading words count toward 150. The operator chose (a) because nothing else must change.
- D-13: (a) shape, not position — about four rules, a misshapen verdict costs one re-review; (b) count only — a bare `None.` beside resolved lines passes again; (c) shape and position — most likely to fail a sound verdict for nothing. The operator chose (a) because it blocks the misleading `None.` without a position rule the join breaks.
- D-14: (a) the rule or row id — the exact shape holds, the merger sees the subject; (b) drop the slot — a second shape, and the ticket changes again. The operator chose (a) because it keeps one shape.
- D-3: (a) no id, no sha — defect text says what it was, nothing links to a commit; (b) id qualified by verdict sha — longer, sha useless once collapsed; (c) the ticket's example — ids collide, sha unspecified, no defect text. The operator chose (a) because the merger needs what was wrong and how it was closed.
- D-4: (a) a new exact line — fixes the misleading `None.`, costs a checker and a join change; (b) keep `None.` — no change, still misleading. The operator chose (a) because a bare `None.` is what the ticket calls misleading.
- D-5: (a) yes, same form — one sentence changes; (b) no — a note the merger saw earlier disappears with no trace. The operator chose (a) because the merger was asked to read those notes.
- D-7: (a) check the count — one rule and a selftest, a miscount costs one re-review; (b) do not check — a wrong count reaches the merger. The operator chose (a) because a wrong count misleads as a bare `None.` does.
- D-8: (a) amend with the AC block — the probe and plan coverage get ids; (b) amend without ACs — no probe, no ids; (c) leave the ticket — the first pass grades against overruled text. The operator chose (a) because the first-pass review reads the ticket alone.
- D-9: (a) replay plus PM-1 — a few dollars more per build, behavior seen before shipping; (b) PM-1 only — a no-op prompt ships unnoticed; (c) selftests only — the review behavior is never checked. The operator chose (a) because a reviewer-prompt fix is replayed before it ships.
- D-10: (a) holds — a selftest keeps the plain `None.` approve passing; (b) exempt — no test. The operator chose (a) because the case costs nothing and guards today's behavior.

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | A finding listed as resolved that a later round raises again | reversible-default-and-flag |

OR-1 default: the review removes the finding's resolved line while the finding is open again in `## Findings`, and writes a new resolved line when it is resolved again. The intake agent chose it. Reversing it is one sentence in the review-later-round copies.

## Test intent

ACs: AC-1 AC-2 AC-3 AC-4 AC-5 AC-6

AC-1: exempt — review-prompt behavior; the D-9 replay shows it, and no test can prove it
AC-2: exempt — review-prompt behavior; the D-9 replay shows it, and no test can prove it
AC-3: verdict-check accepts an approve whose empty Findings holds `None open. 2 resolved, listed in ## Notes.` with two resolved lines in the fold, and fails the same approve when either count reads 3 or when Findings holds a bare `None.`
AC-4: verdict-check passes an approve whose Notes reach 150 words only through resolved lines and the two fold lines
AC-5: verdict-join on a lane approve with the `None open.` line and a blind blocker drops that line, and the joined body passes verdict-check
AC-6: holds — verdict-check accepts a first-review approve whose empty Findings holds `None.`

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | The later-review verdict comment the merger reads | decided (D-1) |
| S-2 | The resolved fold in `## Notes` | decided (D-2) |
| S-3 | One resolved line | decided (D-3) |
| S-12 | A misshapen resolved list in a draft verdict | decided (D-13) |
| S-4 | An empty `## Findings` with resolved lines | decided (D-4) |
| S-5 | A first review's empty `## Findings` | decided (D-10) |
| S-6 | `verdict-check.sh` CLI, args and exit codes | contract (D-11) |
| S-7 | The joined body `verdict-join.sh` writes | decided (D-4) |
| S-8 | The hand review `/dev-pipeline:review` | decided (D-6) |
| S-9 | review-lead's report on a foreign PR | out-of-scope — it is a single round with no earlier verdict, and only its verdict-style text changes. |
| S-10 | The build reading a needs-work verdict's resolved lines | out-of-scope — the lines sit in `## Notes`, which counts toward nothing, and the build answers only finding lines. |
| S-11 | Scripts that read only lines 1 and 2 of a verdict | out-of-scope — minimize-verdicts.sh, changed-lines.sh and the bound-verdict filter never read the body. |

## Checks

- `bash scripts/check-lockstep-pairs.sh`

## Intake steps

Requirements: the ticket body as written, filed this session on the operator's word. spec-reviewer: not implementable as written; its three blockers became D-1, D-3 and D-4, and its gaps D-5, D-6 and D-8. The implementability probe ran on the amended AC block and found five guess-points: three became D-2, D-13 and D-14 on the operator's answers, and two became the fact rows D-15 and D-16.

Split: not split. The work is one deliverable in one review grammar.

Explore: done. Read the review-later-round, verdict-grammar and verdict-style copies, verdict-check.sh, verdict-join.sh and the verdicts on #1376.

Fan-out: ran — 30 items, see Fan-out

Dup-scan: no candidates at or above threshold 12

Post-merge scan: no post-merge AC. PM-1 was written as a post-merge check when the AC block was added.

Sizing: opus

<details>
<summary>Intake evidence: knowledge source and fan-out</summary>

## Knowledge source

Knowledge source: none declared

## Fan-out

Lenses: verdict-readers opus 6 · checker-contract opus 6 · multi-round-replay opus 6 · resolution-evidence opus 6 · premortem opus 6
Tally: rows added 2 · snapshot claims overturned 0 · questions added 0

| ID | Angle | Claim | Tag | Disposition |
| --- | --- | --- | --- | --- |
| F-1 | verdict-readers | verdict-check.sh rejects any Findings line but `None.` or a finding (`verdict-check.sh:158`). | already-had | already had — D-4 |
| F-2 | verdict-readers | `- resolved:` lines count toward the 150-word Notes cap today (`verdict-check.sh:170`). | already-had | already had — D-6 |
| F-3 | verdict-readers | verdict-join.sh drops only an exact `None.` when it adds a blind finding (`verdict-join.sh:262`). | already-had | already had — D-4 |
| F-4 | verdict-readers | The build prompt names only later-round notes as non-findings (`build/SKILL.md:62`). | not material | not material — Notes counts toward nothing; the build answers finding lines |
| F-5 | verdict-readers | The later-round note and kb-contributions rules are carry-forward precedents (`run.sh:1258,1292`). | already-had | already had — D-1 |
| F-6 | verdict-readers | minimize-verdicts.sh, changed-lines.sh and the bound-verdict filter read only lines 1-2. | not material | not material — they never read the body; scoped out as S-11 |
| F-7 | checker-contract | The proposed Findings line fails verdict-check; a bare `None.` passes (`verdict-check.sh:158`). | already-had | already had — D-4 |
| F-8 | checker-contract | A needs-work with `None open.` and no finding fails `needs-work with no finding`. | not material | not material — the correct failure; review-lead never writes the line |
| F-9 | checker-contract | A fold does not exempt lines; fold lines add words (`verdict-check.sh:170`). | already-had | already had — D-2 |
| F-10 | checker-contract | The join would keep `None open.` beside blind findings (`verdict-join.sh:262`). | already-had | already had — D-4 |
| F-11 | checker-contract | review-later-round and verdict-grammar copies must stay byte-equal (`scripts/check-lockstep-pairs.sh`). | already-had | already had — D-6 |
| F-12 | checker-contract | A fixed later-round note is also never mentioned (`run.sh:1258`). | already-had | already had — D-5 |
| F-13 | multi-round-replay | On #1376, N1 names 4 different findings and B1 names 3 across verdicts. | already-had | already had — D-3 |
| F-14 | multi-round-replay | Carry-forward makes the #1376 approve's resolved list 8 lines, 81 words. | already-had | already had — D-1 |
| F-15 | multi-round-replay | 4 of 5 carried `fixed in <sha>` values are gone from #1376 after the rebase. | already-had | already had — D-3 |
| F-16 | multi-round-replay | The later-round carry rule came from #1376's B2, the same defect (`run.sh:1258`). | already-had | already had — D-1 |
| F-17 | multi-round-replay | In run-1342 a finding was absent from a verdict and came back as a blocker. | not material | not material — the review checks each finding against the head |
| F-18 | multi-round-replay | A fix often has no build reply to quote (`build-1.1.json`). | already-had | already had — D-3 |
| F-19 | resolution-evidence | Nothing tells the review which sha fixed a line (`run.sh:1250`). | already-had | already had — D-3 |
| F-20 | resolution-evidence | The new Findings line needs verdict-check and verdict-join changes (`verdict-check.sh:158`). | already-had | already had — D-4 |
| F-21 | resolution-evidence | verdict-style limits a sub-heading to six sentences, so a long list breaks it (`run.sh:1319`). | new | became D-6 |
| F-22 | resolution-evidence | A ticket-edit outcome has no `<how>`, and later-round notes are not covered (`run.sh:1256,1258`). | already-had | already had — D-3, D-5 |
| F-23 | resolution-evidence | A resolved id can repeat a new finding id and still pass (`verdict-check.sh:159`). | already-had | already had — D-3 |
| F-24 | resolution-evidence | verdict-style says "State each fact once", and the count appears twice (`run.sh:1303`). | new | became D-7 |
| F-25 | premortem | A second rejected verdict ends the run review-unbound (`run.sh:315`). | already-had | already had — D-4 |
| F-26 | premortem | Fixing verdict-check alone leaves the join path broken (`verdict-join.sh:262`). | already-had | already had — D-4 |
| F-27 | premortem | Ids restart at B1/N1 in every #1376 verdict. | already-had | already had — D-3 |
| F-28 | premortem | The 150-word rule lives in three verdict-style copies (`review-lead/SKILL.md:745`). | already-had | already had — D-6 |
| F-29 | premortem | A needs-work's resolved lines may lead the build to re-rebut closed findings (`run.sh:1143`). | not material | not material — the build answers finding lines; Notes count toward nothing |
| F-30 | premortem | Identity across rounds could let the scheduler check completeness mechanically. | not material | not material — beyond the ticket; the later-round carry is prompt-only too |

### Snapshot

    | ID | Decision | Resolution |
    | --- | --- | --- |
    | D-1 | Which resolved findings a later verdict lists | open — ask: every one the PR had, chained from the latest verdict's resolved lines / rebuilt from all earlier verdicts / only the latest verdict's |
    | D-2 | A fold for a long resolved list | open — ask after D-1: always fold / plain lines |
    | D-3 | The exact resolved line | open — ask: `- resolved: <file:line> — <defect> — <how>`, no id, no sha / id qualified by the verdict sha / the ticket's example with id and `fixed in <sha>` |
    | D-4 | The `## Findings` line when nothing is open but something was resolved | open — ask: a new exact line, checker and join changed / keep `None.` |
    | D-5 | A fixed later-round note | open — ask: gets a resolved line / stays unmentioned |
    | D-6 | The verdict-style copies | fact: the 150-word sentence is in three byte-equal copies, review-lead's among them; its text changes, its report format does not |
    | D-7 | Test intent and post-merge check | open — ask at Receipt: selftests for verdict-check and verdict-join; reviewer behavior by replay or PM |

    Facts held:
    - verdict-check.sh:158 accepts only `None.`; verdict-join.sh:262 drops only `None.`.
    - verdict-check.sh:170 exempts later-round notes and the kb block from the Notes count.
    - run.sh:1290 kb-contributions carries the whole list on every verdict.
    - Finding ids restart in every verdict.
    - The build-side sentence for resolved lines is not material: Notes count toward nothing.

</details>
