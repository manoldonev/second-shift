# Decision record — #1375 Build reply comments stay expanded on the PR after an approve, and may not need to be PR comments at all

Receipt: v5

## Summary

A build's reply to a review stays a PR comment, but it now starts with the line `build: reply`. When a verdict binds, `minimize-verdicts.sh` collapses marked lane replies posted before it, by the same rule it uses for verdicts. Both build paths post replies through the bot when it is on. Each later round also copies every request to the operator into `## Before you merge`.

Open regions: none.

Provenance legend: `user-answered` = the operator chose. `codebase-derived` = a fact from the code or the docs, with its proof.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Where the build's reply lives | A PR comment, as today. It is minimized when a verdict binds. The account is not moved off the PR, so no scratch-dir or body store is built. Departs from the ticket's Proposed change: part 2 read "Decide whether the reply must be a PR comment at all", with the account written to the run's scratch dir. | user-answered | intent |
| D-2 | How replies are minimized | By `minimize-verdicts.sh` itself, in the same call that minimizes earlier verdicts. It uses the same lane-author filter and the same rule: posted before the kept verdict. Both call sites get it: `minimize_earlier_verdicts` in run.sh and step 8 of review/SKILL.md. The run block keeps its one line for that call. | user-answered | intent |
| D-3 | The reply marker | The first line of a reply is exactly `build: reply`. Inputs: a PR comment body (required), whose first line, with a trailing carriage return stripped, equals `build: reply`. The rest of the body is free text. Outputs: the minimize step treats the comment as a build reply. Errors: none — a comment without that first line is not a reply and stays expanded. | user-answered | intent |
| D-4 | Unmarked replies already on PRs | Out of scope. They stay expanded. No wider predicate is added, because a lane-authored non-verdict rule would also select notices and other bots' comments. | user-answered | intent |
| D-5 | Who posts a reply | Both build paths post each reply through the bot wrapper when its `--status` is `ok`, and through plain `gh` otherwise. The author filter of the script does not change. Through the bot, `api user` fails, so only Bot authors match. run: `bash plugins/dev-pipeline/tools/gh-bot.sh api user` → HTTP 403 "Resource not accessible by integration" | user-answered | intent |
| D-6 | A request to the operator inside a reply | In every round after the first, both build paths add each such request to the PR body's `## Before you merge` section. They create the section when the body has none. | user-answered | intent |
| D-7 | Drift between the two copies of the reply rule | The reply rule (D-3, D-5, D-6) is one LOCKSTEP block in run.sh and in build/SKILL.md. `bash scripts/check-lockstep-pairs.sh` passes with that block in both files. From: F-8 | user-answered | intent |
| D-8 | A reply posted without the marker | Accepted. The reply stays expanded, and nothing fails or reports it. No scheduler check reads the build's comments. From: F-30 | user-answered | intent |
| D-9 | The script's name | `minimize-verdicts.sh` keeps its name. Its header comment and review/SKILL.md lines 304-305 change to say that it also minimizes marked lane replies. | user-answered | intent |
| D-10 | The CLI of `minimize-verdicts.sh` | Unchanged. Inputs: `--repo <owner/name>` (optional), `<pr>` (required), `<kept-comment-id>` (required, a lane verdict). Outputs: one stdout line `minimized <id>` per comment minimized, verdict or reply. Errors: exit 1 when the comments cannot be read, the kept id is not a lane verdict, or a minimize fails. Exit 2 on usage. run: `sed -n 6,19p plugins/dev-pipeline/tools/minimize-verdicts.sh` → usage line, exit 0/1/2, stdout `minimized <id>` | codebase-derived | fact |
| D-11 | The review's read of the build's account | Unchanged in run.sh and review/SKILL.md. The round N+1 review reads reply N before verdict N+1 binds. A minimized comment's body still comes back in JSON. run: `gh pr view 1368 --json comments -q '.comments[]\|select(.isMinimized)\|.body[0:20]'` → bodies returned, `isMinimized` true | codebase-derived | fact |
| D-12 | Tests that the change needs | A run*-selftest case covers the run.sh prompt change, and `minimize-verdicts-selftest.sh` gets reply cases. cited (convention): CLAUDE.md:147 | codebase-derived | fact |
| D-13 | How each build path reaches the bot | The lane build already holds `Bash($GH *)` when the bot is on, so its allowlist does not change. The interactive build calls the wrapper the way the manual review does. cited (convention): plugins/dev-pipeline/skills/review/SKILL.md:208 | codebase-derived | fact |
| D-14 | The concrete posting command in the lane prompt | The LOCKSTEP block states the posting rule without a path. run.sh adds one line outside the block. With the bot on, it names `$GH pr comment <pr> --body-file <file>` by its literal path. With the bot off, it names `gh pr comment`. The lane build may run only `$GH *`, not `gh-bot.sh --status`. run: `grep -n 'BOT_OK" -eq 1 \] && echo\|Bash(\$GH \*)' plugins/dev-pipeline/skills/run/run.sh` → 1126 conditional bot-commit line, 1313 `Bash($GH *)` | codebase-derived | fact |
| D-15 | Where a later round creates `## Before you merge` | At its round-1 place: after the template or What this changes sections, before the Closes line, outside the second-shift fold. cited (convention): plugins/dev-pipeline/skills/run/run.sh:1132 | codebase-derived | fact |

Options weighed:

- D-1: (a) PR body section — replies in the second-shift fold, replaced each round, prompt edits only, earlier rebuttals only in edit history; (b) minimize marked replies — script, selftest, 2 prompts and the review skill change, replies must post through the bot, rebuttals stay one click away; (c) run-state file — the manual review reads no account, new scheduler plumbing; (d) both 1 and 2 — the extra part covers almost nothing, the most files. user-answered chose (b) because the operator wants one minimize mechanism for verdicts and replies.
- D-3: (a) first line `build: reply` — visible, the same predicate shape as the verdict line; (b) hidden `<!-- build-reply -->` — not rendered, a forgotten marker gives no visible sign. user-answered chose (a) because it matches the verdict precedent.
- D-4: (a) out of scope — only PRs open at ship time are affected, no code; (b) wider predicate — must recognize every notice form, a miss collapses a notice. user-answered chose (a) because the wider rule risks the notices #946 keeps.
- D-5: (a) post through the bot — 2 prompts change, the filter stays; (b) widen the author filter — changes the filter, adds a second gh read, collapses any hand-written marked comment. user-answered chose (a) because lane writes go through the bot.
- D-6: (a) route to Before you merge — one channel for operator action, 2 prompts change; (b) exempt asking replies — the build judges, mixed replies stay expanded; (c) accept the loss — breaks the ticket's third constraint. user-answered chose (a) because the body stays the one place to act.
- D-7: (a) LOCKSTEP pair — the checker fails on drift, a few more lines; (b) two plain copies — smaller, can drift unseen. user-answered chose (a) because three rules in two copies drift.
- D-8: (a) accept — no code, worst case is today's behavior; (b) scheduler reports it — a comment read, a run-block line and a selftest case. user-answered chose (a) because a miss costs one expanded comment.
- D-9: (a) keep the name — the smallest diff, the name stays narrower than the behavior; (b) rename — both callers, the selftest and docs change. user-answered chose (a) because a rename is a label-only gain.

## Open Regions

No open regions. Every decision in scope is settled.

## Test intent

ACs: AC-1 AC-2 AC-3 AC-4

AC-1: minimize-verdicts.sh minimizes a `build: reply` comment by a Bot posted before the kept verdict, and one by the `$GH` account when that account resolves
AC-2: minimize-verdicts.sh leaves expanded a marked reply after the kept verdict, an unmarked lane comment, a marked comment by another author and the kept verdict itself
AC-3: run.sh's later-round build prompt tells the build to start each reply with `build: reply`, and names the bot wrapper when the bot is on and plain gh when it is off
AC-4: run.sh's later-round build prompt tells the build to add each operator request from a reply to `## Before you merge`, and to create that section when it is absent

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | The PR conversation a merging human sees at an approve | decided (D-1, D-2) |
| S-2 | The `build: reply` first line that the minimize step parses | contract (D-3) |
| S-3 | `minimize-verdicts.sh` args, exit codes and stdout | contract (D-10) |
| S-4 | `## Before you merge` in rounds after the first | decided (D-6) |
| S-5 | The run-block line after the minimize call | decided (D-2) |
| S-6 | The review's step that reads the build's account | decided (D-11) |
| S-7 | Unmarked replies on PRs open at ship time | decided (D-4) |
| S-8 | The interactive build's reply instructions | decided (D-5, D-6, D-7) |
| S-9 | Notices and the manual review's failure comments | decided (D-3) |
| S-10 | Terminal exits before a verdict binds | out-of-scope — no verdict binds there, so nothing is minimized, the same as for verdicts today. |

## Checks

- `bash plugins/dev-pipeline/tools/minimize-verdicts-selftest.sh`
- `bash plugins/dev-pipeline/skills/run/run-selftest.sh`
- `bash plugins/dev-pipeline/skills/run/run-verdict-selftest.sh`
- `bash scripts/check-lockstep-pairs.sh`

## Intake steps

Requirements: the ticket body as written. spec-reviewer: needs operator decisions (part 2 undecided, no AC block, four part-1 gaps). The interview settled them, and the operator approved an AC block added to the ticket.

Split: not triggered. No epic label. Parts 1 and 2 were alternative mechanisms for one outcome, chosen in the interview.

Explore: done. Read minimize-verdicts.sh and its selftest, the build and review prompts in run.sh, build/SKILL.md, review/SKILL.md and other-comments.sh. Probed the bot's `api user` and a minimized comment's JSON.

Fan-out: ran — 30 items, see Fan-out

Dup-scan: no candidates at or above threshold 12

Post-merge scan: no post-merge AC

Sizing: opus

<details>
<summary>Intake evidence: knowledge source and fan-out</summary>

## Knowledge source

Knowledge source: none declared

## Fan-out

Lenses: reply-identity-and-recognition opus 6 · account-readers-across-entry-paths opus 6 · review-blindness-ordering opus 6 · merging-human-view-and-run-endings opus 6 · premortem opus 6
Tally: rows added 2 · snapshot claims overturned 0 · questions added 2 (D-7, D-8)

| ID | Angle | Claim | Tag | Disposition |
| --- | --- | --- | --- | --- |
| F-1 | reply-identity-and-recognition | Through the bot, `api user` returns 403, so the author filter accepts only Bots (`minimize-verdicts.sh:33,39`) | already-had | already had — D-5 |
| F-2 | reply-identity-and-recognition | Neither build path names the identity that posts a reply (`run.sh:1140,1312-1313`) | already-had | already had — D-5 |
| F-3 | reply-identity-and-recognition | A lane-authored non-verdict rule selects other bots and failure comments (probe R1) | already-had | already had — D-4 |
| F-4 | reply-identity-and-recognition | A marker with no author filter selects a stranger's forged copy (probe R3) | already-had | already had — D-3 |
| F-5 | reply-identity-and-recognition | The scheduler posts only verdicts on a PR; its notices go to the issue (`run.sh:1608`) | not material | not material — confirms D-3 needs no notice rule |
| F-6 | reply-identity-and-recognition | Part 1 first needs a choice of reply identity (`run.sh:1140`) | already-had | already had — D-5 |
| F-7 | account-readers-across-entry-paths | Two build prompts tell the build to rebut in a PR comment (`run.sh:1140`, `build/SKILL.md:62`) | already-had | already had — D-7 |
| F-8 | account-readers-across-entry-paths | No LOCKSTEP block ties the two copies of the rebuttal rule (`run-selftest.sh:53-71`) | new | became D-7 |
| F-9 | account-readers-across-entry-paths | The scratch dir exists per run and is archived at exit (`run.sh:170-182`) | not material | not material — part 2 not chosen (D-1) |
| F-10 | account-readers-across-entry-paths | Only the PR is shared across the handoff and manual paths (`review/SKILL.md:30-46`) | not material | not material — part 2 not chosen (D-1) |
| F-11 | account-readers-across-entry-paths | other-comments.sh does not count lane replies (`other-comments.sh:8-9`) | not material | not material — no reply change affects that count |
| F-12 | account-readers-across-entry-paths | With the bot on, the reused author filter misses operator-posted replies (`run.sh:1641`) | already-had | already had — D-5 |
| F-13 | review-blindness-ordering | The pass-2 review can read PR comments at any time; only prose orders it (`run.sh:1323`) | not material | not material — the read order does not change (D-11) |
| F-14 | review-blindness-ordering | Build reply drafts can sit in the shared scratch dir (`run.sh:1109,1971`) | not material | not material — part 2 not chosen (D-1) |
| F-15 | review-blindness-ordering | Blind sessions are denied the lane scratch dir (`plain-review.sh deny`) | not material | not material — part 2 not chosen (D-1) |
| F-16 | review-blindness-ordering | Only a line-order test guards the account-last rule (`run-selftest.sh:70-71`) | not material | not material — the read order does not change (D-11) |
| F-17 | review-blindness-ordering | The manual review orders the account read by skill text only (`review/SKILL.md:85-87`) | not material | not material — the read order does not change (D-11) |
| F-18 | review-blindness-ordering | A moved account could reach the review before pass 2 (`run.sh:2000`) | not material | not material — part 2 not chosen (D-1) |
| F-19 | merging-human-view-and-run-endings | Later rounds never update Before you merge (`run.sh:1132,1140`) | already-had | already had — D-6 |
| F-20 | merging-human-view-and-run-endings | run.sh minimizes once, after a verdict binds (`run.sh:2146-2149`) | not material | not material — replies follow the same timing (D-2) |
| F-21 | merging-human-view-and-run-endings | Terminal exits before the bind minimize nothing (`run.sh:2121-2142`) | not material | not material — out of scope as surface S-10 |
| F-22 | merging-human-view-and-run-endings | A paused build's fresh replies are unread by any review (`run.sh:2030`) | not material | not material — they stay expanded until a verdict binds (D-2) |
| F-23 | merging-human-view-and-run-endings | The handoff build posts as the operator; the manual review minimizes as the bot (`review/SKILL.md:208,301`) | already-had | already had — D-5 |
| F-24 | merging-human-view-and-run-endings | The id rule also collapses replies from earlier runs (`minimize-verdicts.sh:43`) | already-had | already had — D-2 |
| F-25 | premortem | Operator-posted replies stay expanded with the bot on, and the tool reports success (`minimize-verdicts.sh:39`) | already-had | already had — D-5 |
| F-26 | premortem | A later-round ask is lost when its comment collapses (`run.sh:1140`) | already-had | already had — D-6 |
| F-27 | premortem | A later reader using `gh pr view` loses a minimized reply's text (`run.sh:1323`) | not material | not used — did not hold: `--json comments` returns minimized bodies |
| F-28 | premortem | The scratch dir dies with the run (`run.sh:170-181`) | not material | not material — part 2 not chosen (D-1) |
| F-29 | premortem | A moved account could be read before pass 2 (`run.sh:1969-1971`) | not material | not material — part 2 not chosen (D-1) |
| F-30 | premortem | The reply marker is enforced by a prompt line only (`run.sh:1140,1322`) | new | became D-8 |

### Snapshot

    | ID | Decision | Resolution |
    | --- | --- | --- |
    | Q-1 | Mechanism: minimize marked reply comments (part 1), move the build's account off PR comments (part 2, where it lives), or both | open — recommend part 2 via a section of the PR body, replaced each round |
    | Q-2 | (if part 1) the exact marker string of a reply comment | open |
    | Q-3 | (if part 1) unmarked replies already on PRs: out of scope, or matched by a wider predicate | open |
    | Q-4 | (if part 1) replies must be posted through $GH when the bot is on | open |
    | Q-5 | A request to the operator inside a rebuttal: later rounds route it to "Before you merge" | open |
    | Q-6 | (if part 2 in the body) the 500-word body limit and the new section | open |
    | Q-7 | AC block for the ticket (none today) | open |

    Facts held: minimize-verdicts.sh:39-40 predicate and author filter; two minimize call sites (run.sh:1636, review/SKILL.md:300-307);
    two build paths rebut in a PR comment (run.sh:1140, build/SKILL.md:62); two review paths read the account last (run.sh:1234,
    review/SKILL.md:202-206); build allowlist grants plain gh pr comment and $GH * only with the bot (run.sh:1312-1313);
    Before you merge is round-1 only (run.sh:1132 vs 1140); the 500-word body limit (run.sh:1129); the scratch dir is archived at
    exit (run.sh:169-181); review step 1 reads only tokens from the body; other-comments.sh counts only non-lane authors;
    the part-1 ordering is sound (verdict N+1 binds after the review read reply N).

</details>
