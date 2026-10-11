# Intake receipt — #977 post-merge checks get their own marked form

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Where a post-merge check lives, and its form | A `## Post-merge checks` section in the ticket body, apart from the acceptance criteria, its items ID'd `PM-1..n`. Weighed: a marked AC form inside the AC section (it would have to keep its `AC-n` label under the reviewer's all-or-nothing labeling rule, `scope-completeness-reviewer.md:60-63`), a receipt-only section read from the record's first commit (unreachable for hand-built PRs), and both anchored together | user-answered | intent |
| D-2 | What keeps the check alive after `Closes #N` closes the ticket | Nothing new: the ticket closes on merge as now, and the closed ticket's `## Post-merge checks` section is the note. No auto-filed follow-up, no workflow change, no run.sh change. The ticket's third acceptance item ("still on the tracker … with no hand-filing") and the Ask's close-path bullet are DROPPED by the operator. Weighed: the `issues: closed` workflow filing a follow-up (first picked, then withdrawn), run.sh filing at its approve terminal (pre-merge, lane-only, no issue-create path), and `Refs` instead of `Closes` | user-answered | intent |
| D-3 | Guard against a build or anyone else adding the marker after the fact | None. The marker is a note, with the same exposure as the existing linked-deferral exemption (`scope-completeness-reviewer.md:111`). No `--disallowedTools` change, no claim-time anchoring | user-answered | intent |
| D-4 | Which authoring paths separate a post-merge check from the ACs | intake-interviewer asks about any AC not checkable at review time and emits the section (item 6 at `SKILL.md:109` and the body template); spec-reviewer flags a post-merge observation written as an ordinary AC (severity: D-12); intake-orchestrator carries the section verbatim into sub-issues; plan-interview pre-flight scans an existing ticket's ACs, asks the operator about each such item and, on a yes, moves it into the ticket body's `## Post-merge checks` section itself (the answer authorizes that tracker write) and records a ledger row. Amended at a second pre-flight on 2026-10-11: the earlier "tell the operator, never edit the ticket" is superseded by the operator's answer | user-answered | intent |
| D-5 | Where "listed in the verdict" lands | scope-completeness-reviewer's output only: it gains a `Carried (post-merge)` list of the `PM-n` items. review-lead's merge summary, the review skill and run.sh are unchanged (review-lead's remediation note still names the section, D-7); the lane verdict comment shows the list only where it already transcribes the scope reviewer's output. Amended at a second pre-flight on 2026-10-11: the earlier "review-lead's merge summary repeats it" is dropped by the operator | user-answered | intent |
| D-6 | How the scope reviewer treats the section | Items under the section are excluded from Step 2 extraction (2a and 2b's liberal prose scan both, which today scans the whole body, `scope-completeness-reviewer.md:66-80`) and reported `[carried]`, a non-failing class for that section only. A post-merge observation anywhere else stays `[unsatisfied]`: Step 4's no-later-bucket rule (`:111`) is unchanged | codebase-derived | fact |
| D-7 | Other prompt carriers of the ticket format | The contract lives only in prompts (no script parses issue sections). The review-lead remediation note (`review-lead/SKILL.md:465-467`) names the section as the form for a post-merge item; the intake template marks the section optional so no section-presence check treats its absence as a gap | codebase-derived | fact |
| D-8 | Jira tracker | No tracker-specific work: the reviewer reads the Jira description as markdown (`scope-completeness-reviewer.md:44`), so the section is read the same way; with D-2 there is no close hook to need | codebase-derived | fact |
| D-9 | How the reviewer behavior is verified | No model-free test can reach the gate outcome (it is prose in review-lead; `code-review.mjs` parses no `[unsatisfied]`), the eval tooling does not run on main, and a prose-presence guard is barred by the writing-tests rules. Evidence is the operator's read of consumer runs (`docs/consumer-eval.md`); no new selftest | codebase-derived | fact |
| D-10 | How the heading is matched | The scheduler's heading rule: the exact title at any depth, any case; any heading closes the section; the first such section decides (interviewing-baseline, "Headings, both sections") | codebase-derived | fact |
| D-11 | Commit verb | `feat(intake-toolkit,review-toolkit):` on the PR title — a new capability (CLAUDE.md, "Commit verbs decide the version bump"), with a `Changelog:` trailer | codebase-derived | fact |
| D-12 | spec-reviewer severity for a post-merge observation written as an ordinary AC | **Warning** (non-blocking; intake-interviewer's 2-loop exit can emit with it). Weighed: Blocker, per the checklist's "cannot be implemented as written" | user-answered | intent |

## Open Regions

No open regions — every decision in scope is ratified.

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | The `## Post-merge checks` section as intake-interviewer writes it into a ticket body | decided (D-1) |
| S-2 | intake-interviewer's question about an AC not checkable at review time | decided (D-4) |
| S-3 | spec-reviewer's finding on a post-merge observation written as an ordinary AC | decided (D-12) |
| S-4 | plan-interview pre-flight's question to the operator, and its move of the item, on a hand-written ticket | decided (D-4) |
| S-5 | Sub-issue bodies written by intake-orchestrator | decided (D-4) |
| S-6 | scope-completeness-reviewer output: the `[carried]` rows, the `Carried (post-merge)` list, PASS and FAIL | decided (D-5) |
| S-7 | review-lead's merge summary | out-of-scope — the operator kept the list in the scope reviewer's output only (D-5) |
| S-8 | The lane verdict comment and the run block | decided (D-5) |
| S-9 | The ticket after the merge closes it | decided (D-2) |
| S-10 | An auto-filed follow-up issue | out-of-scope — dropped by the operator in favor of the note (D-2) |
| S-11 | A Jira description carrying the section | decided (D-8) |
| S-12 | The release-note line | decided (D-11) |

## Checks

No ticket-specific checks — the configured lanes cover this change.

## Fan-out

Refuter: cross (opus/fable alternating)
Lenses: exemption-as-escape-hatch opus 4/6 · close-path-lifecycle fable 6/6 · ticket-format-readers opus 5/6 · proving-the-acceptance fable 3/6 · premortem fable 3/6
Tally: rows added 2 · snapshot claims overturned 1 · questions added 2

| ID | Angle | Claim | Tag | Disposition |
| --- | --- | --- | --- | --- |
| F-1 | exemption-as-escape-hatch | With the bot configured the build allowlist grants `Bash($GH *)`, which passes `issue edit` through (`run.sh:582`) | new | became D-3 |
| F-2 | exemption-as-escape-hatch | review-lead's guard against editing ACs relies on the auto-mode classifier, which acceptEdits lane sessions do not run under (`review-lead/SKILL.md:466-467`, `run.sh:314`) | new | became D-3 |
| F-3 | exemption-as-escape-hatch | Nothing snapshots the ticket body at claim; GitHub's edit history is read by no code (`run.sh:326-327`) | new | became D-3 |
| F-4 | exemption-as-escape-hatch | A ledger row or claim-time check would anchor the marker under the record's first-commit baseline (`scope-completeness-reviewer.md:58,101`) | new | became D-3 (option weighed, not taken) |
| F-5 | close-path-lifecycle | No scheduler process exists at the merge; the only close-bound automation is `unclaim-on-close.yml` with the job token (`run.sh:1091-1092`) | already-had | became D-2 |
| F-6 | close-path-lifecycle | Jira has no close-time hook; every lane tracker write is github-only (`run.sh:129-137`, `second-shift-unclaim.sh:91-101`) | already-had | became D-8 |
| F-7 | close-path-lifecycle | A failed closing-comment write is non-fatal, so a filing step in `terminal()` would inherit that shape (`run.sh:132-135`) | not material | not material — D-2 adds no filing step |
| F-8 | close-path-lifecycle | A resume after the merge refuses on the closed ticket before close-out (`run.sh:842-843`) | not material | not material — D-2 adds no scheduler step |
| F-9 | close-path-lifecycle | The scheduler reads only lines 1-2 of a verdict comment; later lines survive unread (`run.sh:714-732`) | new | became D-5 |
| F-10 | close-path-lifecycle | Neither spawn allowlist grants `gh issue create` except the bot-wrapper build (`run.sh:580-596`) | new | became D-2 (scheduler-filing option weighed) |
| F-11 | ticket-format-readers | A separate section is still extracted and scored by Step 2b, with no row for a carried item (`scope-completeness-reviewer.md:66-70,110-111`) | already-had | became D-6 |
| F-12 | ticket-format-readers | Real tickets use an `## Acceptance` heading the AC regex does not match, and the reviewer numbers them anyway | not material | not material — a latent mismatch on every ticket, not this change |
| F-13 | ticket-format-readers | An in-section marker that drops the `AC-n` label loses its ID under the all-or-nothing rule (`scope-completeness-reviewer.md:60,63`) | new | became D-1 |
| F-14 | ticket-format-readers | The marker contract lives only in prompts; every carrier must change together | new | became D-7 |
| F-15 | ticket-format-readers | Jira ACs held in a custom field get no heading match (unprobed against a live Jira) | not material | not material — the section lives in the description, like ACs today (D-8) |
| F-16 | proving-the-acceptance | run-selftest's fake gh has no `issue create` verb and run.sh never reads the body (`run-selftest.sh:12,32,36`) | not material | not material — D-2 adds no filing step |
| F-17 | proving-the-acceptance | The gate outcome is prose no selftest reaches (`review-lead/SKILL.md:460-464`, `code-review.mjs:349-350`) | already-had | became D-9 |
| F-18 | proving-the-acceptance | The model-tier eval smokes fail on main and no scope-completeness eval exists (`docs/consumer-eval.md:1-4`) | overturned (snapshot: "a replay of the #964/#967 shape is the only behavioral evidence") | became D-9 |
| F-19 | premortem | The #964 AC was hand-written and about half of recent merges are hand-built, so interviewer-only authoring misses that path | new | became D-4 (pre-flight scan) |
| F-20 | premortem | The section is re-extracted and scored unless Step 2b and Step 4 exclude it; `## Deferred` is unhonored prior art | already-had | became D-6 |
| F-21 | premortem | The scheduler cannot file after the merge; an approve-time filing may orphan and misses hand-approved PRs (`run.sh:1082-1092`) | already-had | became D-2 |

### Snapshot

    | ID | Decision | Resolution |
    | --- | --- | --- |
    | D-1 | Marker form | a separate `## Post-merge checks` heading in the ticket body, items ID'd `PM-n`; the scope reviewer's AC parse keys off the first /acceptance criteria/ heading, so a separate heading leaves AC numbering untouched; step 2b liberal extraction must skip the section |
    | D-2 | Which layer keeps the check alive after `Closes #N` | open: (a) the close-bound `issues: closed` workflow files a follow-up per PM item on a completed close; (b) run.sh files it at the approve terminal (pre-merge, lane-only, orphan if the PR never merges); (c) PR uses Refs instead of Closes; (d) intake files the follow-up up front; (e) verdict/run block only (fails AC-3). run.sh exits before the merge, so it cannot act after one |
    | D-3 | Scope-reviewer classification | a third non-failing class `[carried]` only for items under the marked section; unmarked post-merge AC stays `[unsatisfied]` |
    | D-4 | Where "listed in the verdict" lands | scope-completeness output + review-lead report; lane review verdict comment via run.sh review prompt (open) |
    | D-5 | Which authoring skills write the form | intake-interviewer item 6 + body template; spec-reviewer flags; plan-interview / intake-orchestrator sub-issue bodies open |
    | D-6 | Jira tracker | open: follow-up filing is github-only (unclaim workflow is github-only) |
    | D-7 | Verifying AC-1/AC-2 | no model-free test exists for scope-completeness classification; a replay of the #964/#967 shape is the only behavioral evidence (open) |
