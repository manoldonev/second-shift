# The verdict's machine line lists each finding and counts the other reviewers' comments already on the PR

## Problem

A consumer repo is trialling Greptile beside second-shift's joined review, and the operator wants to compare the two by query. The verdict comment carries most of what a query needs, but two facts are missing from it and neither can be recovered after the review is posted.

**The machine line holds counts, not findings.** `verdict-join.sh` ends the folded block with `<!-- plain-vs-lane: {json} -->`, written "for scripts that aggregate across PRs". Its fields are totals (`lane_blockers`, `plain_only`, the `m_<lane>_<plain>` matrix). To get one row per finding, a script has to parse the `## Findings` bullets and the folded "blind review, as written" text, which is truncated at 8000 characters. The blind review's notes are dropped from the body (`plain_notes_dropped`), so they survive only in that fold.

**Nothing records whether another reviewer had already commented.** Pass 1 of the lane review is told not to open a PR comment or an earlier verdict, and the blind session has no `Bash`, so both are independent by design. That is an instruction, not a recorded fact: the review session's allowlist includes `gh pr view*`, and step 8 of `/dev-pipeline:review` reads the PR's comments after pass 2. On the observed PR, a lane blocker was posted 12 minutes after the other reviewer's finding at the same file and within 3 lines of it. The verdict cannot say whether that finding was on the PR when the review ran.

## What to build

Extend the machine line `verdict-join.sh` prints, for both `--format verdict` and `--format report`:

1. **A per-finding list.** One entry per finding of both reviews, the blind review's notes and the dismissed ones included: its id where it has one, its class (blocker, note, dismissed), its source (lane, blind, or both), its path and its line. A finding with no `path:line` carries nulls. The join already holds all of this per finding for its pair matrix.
2. **A count of other reviewers' comments on the PR when the review started.** "Other" means not a lane author by the filter `minimize-verdicts.sh` and `run.sh`'s `verdict()` already use (a Bot, or the account the harness writes as, with a verdict-shaped first line). It counts inline review comments as well as issue comments, since that is where Greptile puts its findings. `verdict-join.sh` reads no tracker, so each of its three callers passes the count in: `run.sh`'s `joined_post`, `/dev-pipeline:review`, and `review-lead`. A caller that cannot read it passes nothing and the field is `null`, never `0`.

Bump the line's `v`.

## Constraints

- `verdict-check.sh` reads the folded block as prose; the longer line must still pass it.
- The existing fields keep their names and meanings: `run-joined-selftest.sh` and `verdict-join-selftest.sh` read them.
- The change to what `run.sh` passes lands with a `run*-selftest.sh` case that fails without it.
- A verdict comment must stay under GitHub's 65,536-character limit with the list in it. Observed verdicts run 11–13k characters with 3–7 findings.

## Out of scope

- Blocking the lane review from reading other reviewers' comments. Record first; decide once the count shows how often it happens.
- Reading the new fields. That is the extractor's ticket.

## Why now

The trial is running. Every verdict posted without the count is permanently unlabeled; the per-finding list can be back-filled by parsing, the count cannot.


## Acceptance Criteria

Where the text above differs, these criteria and the intake record win.

AC-1: verdict-join.sh's machine line carries `"v":3` and a `findings` array under both `--format verdict` and `--format report`. Every existing field keeps its name and meaning.
AC-2: `findings` holds one entry per finding of each review: lane blockers, notes and dismissed; blind blockers and notes. Each entry is `{src, id, class, path, line, pair}`. `src` is `lane` or `blind`; `class` is `blocker`, `note` or `dismissed`. A missing id, path or line is `null`.
AC-3: Findings the join matched share one `pair` number, including every blind blocker merged onto one lane blocker. An unmatched finding has `"pair":null`. A blind blocker added to the body also carries `posted_as`, its id in the body.
AC-4: A lone lane dismissal has an entry, and so does every lane finding when the blind review did not return. The blind `ticket-unavailable` note has none.
AC-5: The list holds at most 150 entries, and `findings_omitted` counts the rest. A joined verdict of 320 findings stays under 65,536 characters.
AC-6: A new dev-pipeline tool counts a PR's comments created (reviews: submitted) at or before a given start time. It reads issue comments, inline review comments and non-empty review bodies. It excludes the lane's accounts: `<tracker.bot.app.appName>[bot]` and the login of the gh it reads with. It writes `{at, total, by_author}` to a file. It exits non-zero and writes nothing when any read fails.
AC-7: verdict-join.sh takes that file through a new flag and emits it as `other_comments`. No flag, an unreadable file or invalid JSON emits `null`, never `0`.
AC-8: run.sh takes the count at the review's start and passes it to the join. A `run-joined-selftest.sh` case, with another reviewer's inline comment posted before the start, fails without the change.
AC-9: `/dev-pipeline:review` takes the count at step 2, and `review-lead` at process step 6. Each writes it to a scratch file it never prints, and passes it in its join block. `review-lead` passes the flag only when verdict-join.sh's usage line names it.
AC-10: Path extraction keeps balanced `[..]`, `[[..]]` and `(..)` segments. `app/users/[id]/page.tsx:12` is read whole, and `[x](src/a.ts:10)` yields `src/a.ts:10`. Two route files at the same line no longer pair.
AC-11: A joined verdict with the longer line still passes `verdict-check.sh`.

