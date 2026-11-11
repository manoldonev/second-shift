# Decision record — #1206 A review-lead report on someone else's PR can be posted on that PR, naming the head it reviewed

Receipt: v4

## Summary

review-lead names the head it reviewed on line 2 of its report. At the end of a review of a PR, it offers to post the report as a pending PR review. The review goes up as the reviewer's own account, with Critical and Warning findings inline where they fall in the diff. A new review-toolkit script does the posting, under a fake-gh selftest.

Open regions: OR-1, when the PR's base commit cannot be fetched, the review is posted with no inline comments and says so.

Provenance legend: `user-answered` = the operator chose. `codebase-derived` = a fact from the code or the docs, with its proof.

Open region legend: `reversible-default-and-flag` = the build uses the stated default.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | When is the report offered for posting? | At the end of every non-void dispatch-mode review of a branch with an open PR. This covers the reviewer's own PR and another's. There is no authorship test. Nothing posts without the reviewer's yes. | user-answered | intent |
| D-2 | As whom is it posted? | The reviewer's own account, through plain `gh`. Never `gh-bot.sh`. A failed create is reported with `gh`'s error and never retried, under any identity. | user-answered | intent |
| D-3 | What GitHub object carries it? | A pending PR review: a review created with no `event`, visible only to the reviewer until they submit it. It is not an issue comment. This reverses the ticket's first Out-of-scope line. | user-answered | intent |
| D-4 | Body only, or inline comments too? | The report is the review body. Each Critical or Warning finding whose site is inside a diff hunk is also an inline comment. Every other finding stays in the body only. | user-answered | intent |
| D-5 | Which parts of the report go into the body? | Line 1 `reviewed-by:`, line 2 `reviewed: <sha>`, every report section, the `## Notes` prose and the hidden machine line when present. The visible `dev: lane vs blind` block is dropped. The session keeps the whole report. | user-answered | intent |
| D-6 | Does the Knowledge-base contributions block go into the body? | Yes, as the report has it. The pending review is its only home that outlives the session. The lane verdict also posts it on the PR. | user-answered | intent |
| D-7 | Which commit does the review sit on? | `commit_id` is the sha review-lead reviewed. The script reads `headRefOid` just before posting. A sha that is a PR commit but not the head is posted, with a line saying the PR moved on. A sha outside the PR's commits is refused, with the reason. | user-answered | intent |
| D-8 | What happens to earlier second-shift reviews on the PR? | A pending review of the reviewer's on the PR blocks the post. Nothing is created or deleted, and the session names that review. Earlier submitted reviews are left alone. This ticket adds no minimize code. | user-answered | intent |
| D-9 | What does a void round do? | No join and no offer. A void decided at Routing does not start the plain review, and the session says so. A later void waits for the plain review, then shows its `verdict.md` as written, labeled as the blind review alone, or its `why`. | user-answered | intent |
| D-10 | Where does the posting logic live? | A checked-in script under `plugins/review-toolkit/scripts/`, with a selftest over a fake `gh` and a git fixture. review-lead's skill gets the final offer step that runs it. | user-answered | intent |
| D-11 | Who teaches the #1205 extractor to read a posted review? | #1205, not this ticket. The new channel and its marks are noted there: https://github.com/manoldonev/second-shift/issues/1205#issuecomment-6795634501 | user-answered | intent |
| D-12 | Is a report that never went through the join offered? | Yes, the same way, with the same two head lines and no machine line. A review-toolkit-only install can post. | user-answered | intent |
| D-13 | Where does the `reviewed: <sha>` line come from? | review-lead writes it into its own report as line 2 in dispatch mode, as a plain line, never a `## ` heading. The script reads the sha from that line. Synthesis-only mode stays headerless. | user-answered | intent |
| D-14 | Inline sites are checked against the hunks of which diff? | `<PR baseRefOid>...<reviewed sha>`, the diff at the reviewed sha. A review on an older `commit_id` anchors to that diff. | user-answered | intent |
| D-15 | Where are those hunks read from? | A local `git diff <baseRefOid>...<sha>` in the reviewer's checkout. The script fetches `baseRefOid` first when it is missing. | user-answered | intent |
| D-16 | What counts as a mention to escape? | GitHub's own rule. An `@` that follows no word character and starts `[A-Za-z0-9-]+` with an optional `/team`, outside inline code and fenced blocks, is wrapped in backticks. | user-answered | intent |
| D-17 | How is the offer made? | One `AskUserQuestion` with "Post as pending review" first. With no person to answer, or no `AskUserQuestion` tool, there is no offer and the session says the report was not posted. | user-answered | intent |
| D-18 | Where does a finding anchor? | At its first `path:line`, as `verdict-join.sh`'s `loc()` reads it. A range anchors at its first line. A finding gets one inline comment at most, on the right side. | user-answered | intent |
| D-19 | What does an inline comment say? | The reviewer tag and the description, plus the finding's continuation lines. The `path:line`, the confidence and the source tag are dropped. A `[blind]` finding reads `[Blind review] <description>`. | user-answered | intent |
| D-20 | How is the branch's open PR found? | `gh pr view` on the current branch, the lookup review-lead already uses. No PR means no offer. The session says so and suggests `gh pr checkout <n>`. | user-answered | intent |
| D-21 | Does a `reviewed:` line 2 survive the join? | Yes. `--format report` passes every line above the first `## ` through unchanged. run: `verdict-join.sh lr.md '' --format report \| sed -n 1,2p` → `reviewed-by: second-shift review-lead (v1)` / `reviewed: 0123456789abcdef0123456789abcdef01234567` | codebase-derived | fact |
| D-22 | Can a posted report be taken for a lane verdict? | No. run.sh binds only a body whose line 1 is `verdict: approve\|needs-work`. run: `grep -n 'test("^verdict: (approve\|needs-work)$")' plugins/dev-pipeline/skills/run/run.sh` → `1513` | codebase-derived | fact |
| D-23 | How does the script get `loc()` without dev-pipeline? | A copy of `loc()` held as a LOCKSTEP pair with `verdict-join.sh`. The repo checks such pairs. run: `ls scripts/check-lockstep-pairs.sh; grep -n 'function loc' plugins/dev-pipeline/tools/verdict-join.sh` → `scripts/check-lockstep-pairs.sh` / `55:  function loc(` | codebase-derived | fact |
| D-24 | Which sha is the reviewed head? | The `<head sha>` the plain review uses: what `git rev-parse HEAD` printed for the head reviewed. cited (convention): plugins/review-toolkit/skills/review-lead/SKILL.md:493 | codebase-derived | fact |
| D-25 | Does the head line touch the review-lead-synth eval? | No. Synthesis-only mode writes no header lines. cited (convention): plugins/review-toolkit/skills/review-lead/SKILL.md:709 | codebase-derived | fact |
| D-26 | How are AC-11 and AC-12 held? | Exempt. Both are skill prose, and CI runs no model session. The review scores them from the SKILL.md diff. | user-answered | intent |
| D-27 | How is AC-13 held? | Holds. A `verdict-join-selftest.sh` case keeps a report's two head lines. It passes without the change. | user-answered | intent |
| D-28 | Is the machine line mention-escaped? | No. The `<!-- plain-vs-lane: … -->` line is copied byte for byte. GitHub renders nothing inside an HTML comment, so it notifies no one. Added in build: escaping would change the JSON paths that the extractor reads. | user-delegated | intent |
| D-29 | How does the script read the PR's commits for D-7? | From the REST list of the PR's commits, paginated. GitHub returns at most 250 commits there, so a reviewed sha past the 250th is refused as off-PR. Added in build: the ticket names no source, and this list is documented with its ceiling. | user-delegated | intent |

Options weighed:
- D-1: a per-run opt-in, a repo config switch, a config default with an override, or always. The operator chose an offer on every run.
- D-2: the reviewer's own account, the bot when `gh-bot.sh` is ok, or the bot only. The operator chose the own account.
- D-3: an issue comment or a pending review. The operator chose a pending review.
- D-4: body plus inline where possible, body only, or inline only. The operator chose body plus inline.
- D-5: the report minus the dev block, the whole joined report, or findings only. The operator chose the report minus the dev block.
- D-6: in the body, or in the body folded. The operator chose in the body.
- D-7: refuse only off-PR shas, or post only on the head. The operator chose to refuse only off-PR shas.
- D-8: guard the draft and leave the rest, guard and auto-collapse, or replace the draft. The operator chose to guard and leave the rest.
- D-9: no join and no offer, or join and no offer; then show the labeled blind draft, or never show it. The operator chose no join and the labeled draft.
- D-10: a script with a selftest, or skill prose. The operator chose the script.
- D-11: a note on #1205, a separate follow-up, or nothing. The operator chose the note.
- D-12: offer it, or offer only joined reports. The operator chose to offer it.
- D-13: in the report, or only in the posted body. The operator chose the report.
- D-14: the diff at the reviewed sha, or the PR's current diff. The operator chose the reviewed sha.
- D-15: local git, or the compare API. The operator chose local git.
- D-16: GitHub's rule, or every `@` outside code. The operator chose GitHub's rule.
- D-17: `AskUserQuestion` with no offer when headless, or a plain-text question. The operator chose `AskUserQuestion`.
- D-18: the first site as `loc()` reads it, or every in-hunk site. The operator chose `loc()`.
- D-19: the finding verbatim, or a cleaned description with the reviewer tag only or with both tags. The operator chose the cleaned description with the reviewer tag only.
- D-20: the branch lookup, or the branch then the sha. The operator chose the branch lookup.
- D-26: exempt, or unchecked with a post-merge smoke. The operator chose exempt.
- D-27: holds, or exempt. The operator chose holds.

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | The PR's base commit cannot be fetched into the reviewer's checkout | reversible-default-and-flag |

OR-1 default: the review is posted with no inline comments, and the script's output says why. The agent chose it at intake. Reversing it costs one branch in the script and its selftest case.

## Test intent

ACs: AC-1 AC-2 AC-3 AC-4 AC-5 AC-6 AC-7 AC-8 AC-9 AC-10 AC-11 AC-12 AC-13

AC-1: given a joined report whose sha is the PR head and no pending review, the script makes one create-review call with no event and that sha as commit_id
AC-2: the created body's line 1 is the report's reviewed-by line, line 2 its reviewed line, and commit_id equals line 2's sha
AC-3: the created body keeps every report section, the KB block and the machine line, and has no dev block, cost line or blind draft
AC-4: a bare @handle and @org/team are backticked in the body and inline text, while jdoe@example.com and an @ in code are unchanged
AC-5: a Critical finding in a hunk of base...sha gets one right-side inline comment at its loc() line, and one outside every hunk stays body-only while the create still happens
AC-6: a sha that is a PR commit but not the head posts and prints the moved-on line, and a sha outside the PR's commits creates nothing and exits non-zero
AC-7: an existing pending review of the caller's means no create, no delete, a non-zero exit and its id in the output
AC-8: a failing create prints gh's error, exits non-zero, makes one create call only and never calls gh-bot.sh
AC-9: the fake gh records no statuses call and no write besides the one review create
AC-10: a report with no machine line is posted with both head lines
AC-11: exempt — skill prose: the report's line 2 and the offer step are scored from the SKILL.md diff
AC-12: exempt — skill prose: the void path is scored from the SKILL.md diff
AC-13: holds — verdict-join --format report keeps a report's reviewed-by line 1 and reviewed line 2 unchanged

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | The offer question in the session | decided (D-17) |
| S-2 | The pending review body on the PR | decided (D-5) |
| S-3 | The KB contributions block in that body | decided (D-6) |
| S-4 | Inline comments on the PR | decided (D-19) |
| S-5 | The moved-on line when the PR head changed | decided (D-7) |
| S-6 | The refusal when the sha is off the PR | decided (D-7) |
| S-7 | The notice that a pending review already exists | decided (D-8) |
| S-8 | The session message on a failed post | decided (D-2) |
| S-9 | The report's head line in the session | decided (D-13) |
| S-10 | The void round's session output | decided (D-9) |
| S-11 | The no-offer message: no PR for the branch | decided (D-20) |
| S-12 | The no-offer message: headless or synthesis-only | decided (D-17) |
| S-13 | The submitted review as colleagues see it | out-of-scope — the reviewer edits and submits it in the GitHub UI. |
| S-14 | Extractor rows for a submitted review | out-of-scope — #1205 owns reading it, per D-11. |

## Checks

No ticket-specific checks. The configured checks cover this change.

## Intake steps

Requirements: the ticket body as written, then amended twice on the operator's yes. spec-reviewer: needs spec work. Its three blockers became interview questions.

Split: not triggered at first. No epic label and one deliverable. The register then passed 10 decisions. Split re-ran: not split, one script and its one caller step.

Explore: done. Read review-lead's report and plain-review steps, verdict-join.sh, minimize-verdicts.sh, gh-bot.sh, plain-review-tools.sh, #1204 and #1205.

Fan-out: ran — 27 items, see Fan-out

Dup-scan: no candidates at or above threshold 12

Post-merge scan: no post-merge AC

Sizing: opus

<details>
<summary>Intake evidence: knowledge source and fan-out</summary>

## Knowledge source

Knowledge source: none declared

## Fan-out

Refuter: cross (opus/fable alternating)
Lenses: comment-stream-readers opus 4/6 · reviewed-head-identity fable 5/6 · report-grammar-roundtrip opus 6/6 · write-path-and-authority fable 6/6 · premortem fable 6/6
Tally: rows added 3 · snapshot claims overturned 1 · questions added 3

| ID | Angle | Claim | Tag | Disposition |
| --- | --- | --- | --- | --- |
| F-1 | comment-stream-readers | run.sh binds only a `verdict:` line 1, so a report never binds (`run.sh:1511-1514`) | new | became D-22 |
| F-2 | comment-stream-readers | minimize-verdicts.sh refuses a report as the kept comment (`minimize-verdicts.sh:39-42`) | new | shaped the options of D-8 |
| F-3 | comment-stream-readers | The join passes lines above the first `## ` through (`verdict-join.sh:193-212`) | already-had | became D-21 |
| F-4 | comment-stream-readers | No in-repo code reads the machine line from PR comments (`verdict-join.sh:24`) | new | became the marks noted under D-11 |
| F-5 | reviewed-head-identity | The reviewed sha can differ from headRefOid both ways (`SKILL.md:111`) | already-had | became D-7 |
| F-6 | reviewed-head-identity | A push during the review goes unseen, while the lane rechecks headRefOid (`review/SKILL.md:286`) | new | became the recheck in D-7 |
| F-7 | reviewed-head-identity | On a fork PR, only pull/N/head equals headRefOid | not material | not material — D-7 refuses an off-PR sha |
| F-8 | reviewed-head-identity | review-lead's base can differ from the PR's base (`SKILL.md:111`) | not material | not material — out of scope, what review-lead reviews |
| F-9 | reviewed-head-identity | The skill has two definitions of the head (`SKILL.md:105` vs `:493`) | already-had | became D-24 |
| F-10 | report-grammar-roundtrip | A plain head line above the first `## ` leaves the join output identical (`verdict-join.sh:244-255`) | already-had | became D-21 |
| F-11 | report-grammar-roundtrip | A head line written as `## ` breaks the join (`verdict-join.sh:198-203`) | new | became the plain-line rule in D-13 |
| F-12 | report-grammar-roundtrip | A void report through the join gains a `[blind]` blocker (`verdict-join.sh:215`) | overturned (snapshot: "a void emits no report structure") | became D-9 |
| F-13 | report-grammar-roundtrip | Verdict readers select by line position, so a report is never taken for one (`run.sh:1513`) | new | same as F-1, became D-22 |
| F-14 | report-grammar-roundtrip | The synth eval never sees the head line (`SKILL.md:709`) | not material | not material — D-25 records it |
| F-15 | report-grammar-roundtrip | Where the head line goes is open (`SKILL.md:709`) | already-had | became D-13 |
| F-16 | write-path-and-authority | review-toolkit has no GitHub write, and the posting tools live in dev-pipeline | new | became D-10 |
| F-17 | write-path-and-authority | review-lead reaches dev-pipeline only through `plain-review-tools.sh:19-38` | new | became D-23 |
| F-18 | write-path-and-authority | A review-toolkit-only install has no path to dev-pipeline tools (`plain-review-tools.sh`) | new | became D-12 |
| F-19 | write-path-and-authority | The lane picks its identity from `gh-bot.sh --status` (`run.sh:251-263`) | already-had | became D-2 |
| F-20 | write-path-and-authority | minimize-verdicts.sh counts only `verdict:` comments by a Bot or `$GH`'s login (`minimize-verdicts.sh:39-43`) | new | same as F-2, shaped D-8 |
| F-21 | write-path-and-authority | A standalone review-lead session has no grant to post (`.claude/settings.json`) | not material | not material — the permission prompt is a second yes |
| F-22 | premortem | A void round can post something that reads as a review (`verdict-join.sh:215`) | overturned (snapshot: "a void emits no report structure") | became D-9 |
| F-23 | premortem | Earlier reports stay expanded beside a later verdict (`minimize-verdicts.sh:39-42`) | new | became D-8 |
| F-24 | premortem | The report can name a head that is not the PR's (`SKILL.md:493`) | already-had | became D-7 |
| F-25 | premortem | Bare @handles in findings would ping accounts (`verdict-join.sh:80`) | new | became D-16 |
| F-26 | premortem | The dev block carries cost, lane wording and a second head line (`verdict-join.sh:149-184`) | new | became D-5 |
| F-27 | premortem | The gh-bot.sh precedent invites a retry as another identity (`gh-bot.sh:141`) | new | became D-2 |

### Snapshot

    | ID | Decision | Resolution |
    | --- | --- | --- |
    | D-1 | When a report is posted | open: per-run opt-in, a repo config switch, or always; recommend off by default with an explicit per-run opt-in |
    | D-2 | As whom | open: the reviewer's own gh account, or gh-bot.sh when its status is ok; recommend the reviewer's own account |
    | D-3 | What is posted | open: the whole joined report, or findings plus the merge answer with the rest folded |
    | D-4 | A later report collapses the earlier one | open: recommend minimize earlier reports by the same posting account only, keyed on the report's first line |
    | D-5 | Which PR and which head | open: PR = gh pr view on the current branch; head = the local HEAD reviewed; recommend refusing to post when it differs from the PR's headRefOid |
    | D-6 | What counts as someone else's PR | open: recommend no authorship test; the opt-in is the gate |
    | D-7 | The head line | open: recommend `reviewed: <full sha>` on line 2, under `reviewed-by:` |
    | D-8 | A report the join never ran on | open: plain review disabled or its tools missing; recommend post it, the absent machine line is the signal |
    | D-9 | Who parses a posted report | open: #1205 reads only `verdict:` comments; recommend out of scope here, follow-up on the extractor |
    | D-10 | Where the post mechanism lives | open: skill prose or a checked-in review-toolkit script with a fake-gh selftest; recommend the script |
    | D-11 | A failed post | reported in the session, never retried as another identity (ticket constraint) |
    | D-12 | Commit status | none (ticket constraint) |
    | D-13 | A void round | posts nothing; a void emits no report structure (review-lead SKILL.md:670) |
    | D-14 | review-lead-synth fixtures | unaffected; synthesis-only mode writes no header line (SKILL.md:709) |
    | D-15 | verdict-join report grammar | a line above the first `## ` passes through unchanged (verdict-join.sh report()) |
    | D-16 | Callers of review-lead in dispatch mode | humans only; no dev-pipeline skill invokes it |

</details>
