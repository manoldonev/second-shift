# Decision record — #1204 The verdict's machine line lists each finding and counts the other reviewers' comments already on the PR

Receipt: v4

## Summary

The `plain-vs-lane` machine line that verdict-join.sh prints moves to v3. It gains a capped `findings` list with one entry per finding of each review, and an `other_comments` object. A new dev-pipeline tool counts the PR's comments by authors other than the lane, as of the review's start. run.sh, `/dev-pipeline:review` and review-lead each take that count and pass it to the join. Path extraction in verdict-join.sh keeps balanced bracket segments, which changes the pairing on route-style paths.

Open regions: none.

Provenance legend: `user-answered` = the operator chose. `codebase-derived` = a fact from the code or the docs, with its proof.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | The unit of the `findings` list | One entry per finding of each review, `src` lane or blind. Entries the join matched share a `pair` number, merged blind blockers included. An unmatched finding has `"pair":null`. A lone lane dismissal has an entry. Every lane finding has an entry when the blind review did not return. An added blind blocker also carries `posted_as`. There is no `both` source value. | user-answered | intent |
| D-2 | The order of the entries | The dev list's sorted pair order, disagreements first. A pair's lane entry comes first, then its blind entries, merged ones included. Lone lane dismissals go last. With no blind draft, the lane draft's order. | user-answered | intent |
| D-3 | The size bound of the list | At most 150 entries. `findings_omitted` counts the entries left out. A selftest proves a joined verdict of 320 findings stays under 65,536 characters. | user-answered | intent |
| D-4 | Ids under `--format report` | A lane entry in report format has `"id":null`, because its class already carries the section. An added blind blocker has `"posted_as":"[blind]"`, as the body shows it. A missing id (`?`) is `null` in both formats. | user-answered | intent |
| D-5 | Which comments count as other reviewers' | Every comment not by the lane's accounts counts. The lane's accounts are `<appName>[bot]` and the login of the operator's gh, the `GH_READ` gh in run.sh. The count is recorded per author login, plus a total. | user-answered | intent |
| D-6 | Where the tool gets the bot's appName | The same resolution as bot-commit.sh: `$SECOND_SHIFT_CONFIG`, then the committed config, then the main checkout's local config. `<appName>[bot]` is excluded whenever a name resolves, even with the bot disabled. With no name, only the gh login is excluded. A missing config is not a failed read. | user-answered | intent |
| D-7 | The moment of the count | Comments created at or before the review's start count. A review counts by its `submitted_at`. The start is recorded as `at`, so the extractor can re-derive a later count against the verdict's own time. | user-answered | intent |
| D-8 | The comment surfaces the count reads | Issue comments, inline review comments and review bodies. A review whose body is empty is not counted, because it only wraps its inline comments. | user-answered | intent |
| D-9 | How each caller reads the count | One new dev-pipeline tool reads the three surfaces and applies D-5 once. It writes `{at, total, by_author}` to a file. It exits non-zero and writes nothing when any read fails, the login read included, so no 0 stands for a failure. run.sh calls it at the review's start. The two skills call it at their start step, write to their scratch dir and never print it. | user-answered | intent |
| D-10 | How strictly verdict-join.sh reads the count file | It emits `other_comments` only for an object with a string `at`, a numeric `total` and an object `by_author`. No flag, an unreadable file, invalid JSON or any other shape gives `null`. | user-answered | intent |
| D-11 | review-lead against an older dev-pipeline | review-lead passes the count flag only when verdict-join.sh's usage line names it. It skips the count when the counting tool is absent. The tool is not added to plain-review-tools.sh's required set. | user-answered | intent |
| D-12 | Path extraction in verdict-join.sh | Fixed in this ticket. A segment may hold a balanced `[..]`, `[[..]]` or `(..)` group of path characters other than `/`, also inside a segment such as `[id].tsx`. `[x](src/a.ts:10)` yields `src/a.ts:10`. The first path:line in the text still wins. The rule feeds the pairing, the body tags and the list. | user-answered | intent |
| D-13 | The ticket's AC block and the JSON names | AC-1 to AC-11 were added to the issue body, assembled from these rows. Where the body's earlier text differs, the ACs and this record win. The operator approved the names `findings`, `pair`, `posted_as`, `findings_omitted` and `other_comments`. | user-answered | intent |
| D-14 | Test intent forms | AC-9 is exempt, because it is SKILL.md text a session follows, and the repo forbids prose-presence guards. AC-11 holds, because the existing check already passes a long line. | user-answered | intent |
| D-15 | The machine line's place and version | Two printf calls in `devblock()` print it, with `"v":2`. It becomes 3. run: `grep -c 'v\\":2' plugins/dev-pipeline/tools/verdict-join.sh` → 1 | codebase-derived | fact |
| D-16 | The line's readers | Only two selftests read it, each with a one-line sed. So the list stays on that one line. run-joined-selftest.sh asserts `.v == 2` and must change with the bump. run: `grep -rl 'plain-vs-lane: \\(' plugins` → run-joined-selftest.sh, verdict-join-selftest.sh | codebase-derived | fact |
| D-17 | The selftest gh fake | It answers any `api` path holding `comments` from one comments.json, and any `pulls` path with one object. AC-8's case needs separate routes for issue comments, inline comments and reviews. run: `grep -n 'comments\*)' plugins/dev-pipeline/skills/run/run-selftest-lib.sh` → 102 | codebase-derived | fact |
| D-18 | Existing reads of inline review comments | No checked-in script reads them today, so the tool is a new read. run: `grep -rlE 'pulls/[^ ]*/comments' --include='*.sh' plugins \| wc -l` → 0 | codebase-derived | fact |
| D-19 | Where run.sh reads the count | run.sh's own bash reads it, never the review session, whose allowlist has no `gh api`. run: `sed -n '/^review_allowlist/,/^}/p' plugins/dev-pipeline/skills/run/run.sh \| grep -c 'Bash(gh api'` → 0 | codebase-derived | fact |
| D-20 | The review's start in run.sh | It is `start="$(now)"` in the review loop, after `plain_start`. `now()` prints ISO-8601 UTC, which compares as a string with GitHub's times. run: `grep -n '^now()' plugins/dev-pipeline/skills/run/run.sh` → `now() { date -u +%Y-%m-%dT%H:%M:%SZ; }` | codebase-derived | fact |
| D-21 | The blind `ticket-unavailable` note | It has no entry, as it is in no count and no row today. cited (convention): plugins/dev-pipeline/tools/verdict-join.sh:26 | codebase-derived | fact |
| D-22 | The lane bot's login form | It is `<appName>[bot]`. run: `grep -n 'APP_NAME}\[bot\]' plugins/dev-pipeline/tools/bot-commit.sh` → `185:BOT_LOGIN="${APP_NAME}[bot]"` | codebase-derived | fact |
| D-23 | The run.sh test rule | The run.sh change lands with a `run*-selftest.sh` case that fails without it. cited (convention): CLAUDE.md:132 | codebase-derived | fact |
| D-24 | The tool's name and the join's flag | The tool is `tools/other-comments.sh`. verdict-join.sh takes its file as `--other-comments <file>`. A comment whose author account was deleted (`user: null`) counts under `ghost`. Added in build: no row named the tool, the flag or a deleted author. | user-delegated | intent |
| D-25 | How verdict-join.sh writes the count | It writes only the `at`, `total` and `by_author` keys of the file. It writes `<` and `>` as `<` and `>`, so a value cannot close the HTML comment that holds the line. Added in build: D-10 checks the shape but does not say what is written. | user-delegated | intent |
| D-26 | review-lead with no PR | review-lead counts only when `gh pr view --json number` prints a PR number for the branch. With none, it writes no file, and the field is null. Added in build: review-lead takes no PR number as input. | user-delegated | intent |

Options weighed:

- D-1: one entry per pair row, or the ticket's single class with source `both`. The operator chose per finding, per review.
- D-2: lane first, then blind. The operator chose the dev-list order.
- D-3: uncapped with a tested bound. The operator chose a cap of 150.
- D-4: the section label as id and `posted_as` null. The operator chose id null and `posted_as` "[blind]".
- D-5: a total only, or every comment that is not a lane verdict. The operator chose per author plus a total.
- D-6: each caller passes `--bot <name>`. The operator chose the bot-commit.sh resolution.
- D-7: two counts at start and end, or a count with no time. The operator chose the start plus `at`.
- D-8: the ticket's two surfaces, or every review. The operator chose three, skipping empty reviews.
- D-9: inline reads in each caller, or run.sh only. The operator chose one shared tool.
- D-10: any valid JSON passed through. The operator chose a shape check.
- D-11: accept the plugin skew. The operator chose the usage-line guard.
- D-12: leave the paths and file a ticket, or add the four characters as-is. The operator chose balanced groups here.
- D-14: a behavioral test for the skill blocks, or AC-11 as a behavior AC. The operator chose exempt and holds.

## Open Regions

No open regions. Every decision in scope is settled.

## Test intent

ACs: AC-1 AC-2 AC-3 AC-4 AC-5 AC-6 AC-7 AC-8 AC-9 AC-10 AC-11

AC-1: a joined verdict's machine line carries "v":3, a findings array and every v2 field, under both --format verdict and --format report
AC-2: each entry carries src, id, class, path, line and pair, with null for a missing id or site
AC-3: two blind blockers merged onto one lane blocker share its pair number, and an added blind blocker carries posted_as
AC-4: a lone lane dismissal has an entry, and with no blind draft every lane finding has one
AC-5: a join of 320 findings lists 150 entries, sets findings_omitted, and stays under 65,536 characters
AC-6: the counting tool counts another author's inline comment before the start, excludes the lane's accounts, and writes nothing on a failed read
AC-7: no flag, an unreadable file and a wrongly shaped file each give "other_comments":null
AC-8: run.sh passes the start-time count to the join, so the posted line counts another reviewer's inline comment (a run-joined-selftest case)
AC-9: exempt — SKILL.md instructions a session follows; no selftest proves them without a prose-presence guard
AC-10: app/users/[id]/page.tsx:12 is read whole, [x](src/a.ts:10) yields src/a.ts:10, and two route files at one line do not pair
AC-11: holds — a joined verdict carrying the v3 line passes verdict-check.sh

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | The `findings` list in the machine line | decided (D-1) |
| S-2 | A verdict with more than 150 findings | decided (D-3) |
| S-3 | Report-format entries from review-lead | decided (D-4) |
| S-4 | A verdict whose blind review did not return | decided (D-1) |
| S-5 | The `other_comments` object in the machine line | decided (D-5) |
| S-6 | The count when a read fails or the file is wrong | decided (D-10) |
| S-7 | The count file in a skill's scratch dir | decided (D-9) |
| S-8 | review-lead's report against an older dev-pipeline | decided (D-11) |
| S-9 | Sites in the dev list and the body's `[lane+blind]` tags | decided (D-12) |
| S-10 | The verdict's `## Findings` and Summary prose | out-of-scope — only the machine line and the path rule change; the body text is untouched |
| S-11 | run.sh's run log and run block | out-of-scope — the count lives in the verdict alone; no ticket asks for a log line |
| S-12 | A run with `run.joinedReview` false | out-of-scope — no join runs, so no machine line exists |

## Checks

No ticket-specific checks. The configured checks cover this change.

## Intake steps

Requirements: the ticket body as written, a written ticket. spec-reviewer: three blockers and five gaps. Each needed the operator, so each went to the interview.

Split: not split. Both deliverables edit one machine line and one version, and the list alone is too thin for its own run.

Explore: done. Read verdict-join.sh, run.sh's review loop, joined_post and verdict(), both skills' join blocks and the selftest gh fake.

Fan-out: ran — 25 items, see Fan-out

Dup-scan: no candidates at or above threshold 12

Post-merge scan: no post-merge AC

Sizing: opus

<details>
<summary>Intake evidence: knowledge source and fan-out</summary>

## Knowledge source

Knowledge source: none declared

## Fan-out

Refuter: cross (opus/fable alternating)
Lenses: three-caller-contract opus 5/6 · github-comment-surface fable 4/6 · per-finding-fidelity opus 5/6 · machine-line-as-artifact opus 6/6 · premortem fable 5/6
Tally: rows added 6 · snapshot claims overturned 0 · questions added 3

| ID | Angle | Claim | Tag | Disposition |
| --- | --- | --- | --- | --- |
| F-1 | three-caller-contract | An unknown flag makes an older verdict-join.sh exit 2, and review-lead takes the highest installed copy (`plain-review-tools.sh:11-38`) | new | became D-11 |
| F-2 | three-caller-contract | Common count idioms print 0 on an empty or failed read (`jq -s 'add\|length'`, `wc -l`, `grep -c`) | new | became D-9 |
| F-3 | three-caller-contract | `gh pr view --json` has no inline-comment field, and its authors carry no type (`gh pr view --help`) | new | became D-9 |
| F-4 | three-caller-contract | Every caller joins at the end, so a count at join time includes mid-review comments (`run.sh` review loop) | already-had | became D-7 |
| F-5 | three-caller-contract | The cited filter counts the lane's own non-verdict comments as other (`minimize-verdicts.sh:39-40`) | already-had | became D-5 |
| F-6 | github-comment-surface | On a public PR, Greptile posted 0 issue comments, 1 review and 4 inline comments (`gh api .../pulls/N/reviews`) | already-had | became D-8 |
| F-7 | github-comment-surface | The filter's author half puts every third-party bot, Greptile included, on the lane side (`run.sh` verdict()) | already-had | became D-5 |
| F-8 | github-comment-surface | Under the GitHub App, `gh api user` returns 403, so `me` is empty (`gh-bot.sh api user`) | new | became D-5 |
| F-9 | github-comment-surface | The two lane filters disagree on CRLF and edits, and a review has `submitted_at`, not `created_at` | new | became D-7 |
| F-10 | per-finding-fidelity | Report-format lane labels are section names, and an added blind blocker prints as a bare `[blind]` (`verdict-join.sh:250`) | new | became D-4 |
| F-11 | per-finding-fidelity | Pair rows miss lone lane dismissals and merged blind blockers (`verdict-join.sh:106,120`) | already-had | became D-1 |
| F-12 | per-finding-fidelity | Agreement is many-to-one, and the first blocker within 3 lines wins, not the nearest (`verdict-join.sh:268`) | new | became D-1 |
| F-13 | per-finding-fidelity | With no blind draft there are no rows, and a blind finding is never classed dismissed (`verdict-join.sh:160`) | already-had | became D-1 |
| F-14 | per-finding-fidelity | A lane blocker without a B id is in no count or pair (`verdict-join.sh:256`) | not material | not material — verdict-check.sh requires a B id |
| F-15 | machine-line-as-artifact | loc() keeps only JSON-safe characters, so a path cannot break the line (`verdict-join.sh:56`) | already-had | no row — bracket characters stay JSON-safe |
| F-16 | machine-line-as-artifact | Pair rows are not one per finding, and ids carry `?` or a section label (`verdict-join.sh:229,250`) | already-had | became D-1 |
| F-17 | machine-line-as-artifact | Nothing checks body size, and 500 entries make a 64k line (`verdict-check.sh` has no length rule) | already-had | became D-3 |
| F-18 | machine-line-as-artifact | Two selftests read the line, and both assert `v` is 2 (`run-joined-selftest.sh:43`) | new | became D-16 |
| F-19 | machine-line-as-artifact | The scheduler's does-not-bind notice would count as another reviewer's comment (`run.sh` verdict_notice) | already-had | became D-5 |
| F-20 | machine-line-as-artifact | No checked-in script reads inline review comments (`grep pulls/*/comments` → none) | new | became D-18 |
| F-21 | premortem | loc() drops `[ ] ( )`, so two route files at one line pair as one blocker (`verdict-join.sh:56`) | new | became D-12 |
| F-22 | premortem | The pair matrix drops findings in three cases, so a row-built list is short (`verdict-join.sh:106,120,160`) | already-had | became D-1 |
| F-23 | premortem | Lane and blind ids collide, and an added blind blocker is renumbered in the body (`verdict-join.sh:269`) | new | became D-1 |
| F-24 | premortem | The literal filter counts above zero on PRs no other reviewer touched (`minimize-verdicts.sh:38-39`) | already-had | became D-5 |
| F-25 | premortem | The session can read comments posted mid-review, which a start count misses (`run.sh` review_allowlist) | new | became D-7 |

### Snapshot

    | ID | Decision | Resolution |
    | --- | --- | --- |
    | D-1 | Where the line is and its version | verdict-join.sh:187-189 prints it in two printf calls; v is 2 and becomes 3 |
    | D-2 | How readers parse the line | each reader matches one line with sed `^<!-- plain-vs-lane: (.*) -->$`; the list must stay on that one line |
    | D-3 | JSON escaping of a path | loc() keeps only [A-Za-z0-9_@./-] before `:<n>`, so a path needs no escaping; line is an integer |
    | D-4 | Unit of the per-finding list | open: per finding or per pair row; the pair matrix drops merged blind blockers (:106), lone lane dismissals (:120) and every row when no blind draft (:160) |
    | D-5 | What "other" comments are | open: the cited jq filter selects lane verdicts, not lane authors; its negation counts build rebuttals, verdict notices and CI bots |
    | D-6 | The moment of the count | open: run.sh `start` (:2039, after plain_start); review step 2; review-lead process step 6 |
    | D-7 | Which comment surfaces | open: issue comments and inline review comments per ticket; review bodies (pulls/N/reviews) unaddressed |
    | D-8 | A missing count | null, never 0: num() (:50) prints null for an empty value |
    | D-9 | review-lead with no PR | passes nothing; the field is null |
    | D-10 | Selftest fake for inline comments | the fake gh answers any *comments* path from one comments.json (run-selftest-lib.sh); it must serve pulls/N/comments apart |
    | D-11 | The ticket-unavailable note | in no row, following the existing rule (verdict-join.sh:26-27) |
    | D-12 | No AC block | open: the ticket has none; plan coverage and fails-without go not-applicable |
    | D-13 | Size bound | open: list uncapped vs capped; ~100 chars per entry |
    | D-14 | joinedReview false | no machine line at all; out of scope |

</details>
