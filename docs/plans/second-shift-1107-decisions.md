# Decision record — #1107 Consumer docs, onboard and intake describe the single-session lane review

Receipt: v4

## Summary

After #1106, the lane's review is one session, and the design-fidelity reviewer runs only on a record with design frames. This ticket makes every doc, onboarding step, lint and intake prompt say so. `reviewers.default` is deprecated but stays valid. Intake stops asking for a `review panel` row, and the row kind is retired.

Open regions: OR-1, the section catalog's reader lines. OR-2, where the `reviewers.default` warning is printed. Both are flagged defaults.

Provenance legend: `user-answered` = the operator chose. `codebase-derived` = a fact from the code or the docs, with its proof.

Open region legend: `reversible-default-and-flag` = the build uses the stated default.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | The fate of `reviewers.default[]` | Deprecated, and still valid. The schema and docs mark it ignored. A warning names it when a config sets it. `check-reviewer-references.sh` stops rejecting names in it. No configVersion bump. Its removal is a later breaking change. | user-answered | intent |
| D-2 | The `review panel` record row | Retired. plan-interview step 5 drops its ask for the row. `receipt.md` drops the row's exact-text exception. Docs stop describing the row. | user-answered | intent |
| D-3 | Scope beyond the first table | Also in scope: `review-lead/SKILL.md:64,292-306`, `scope-completeness-reviewer.md:106` and this repo's `.claude/SECOND-SHIFT.md:26`. They are rows of #1107's table now. Only their description of the pipeline path changes. The ad hoc behavior stays. | user-answered | intent |
| D-4 | AC-8's test intent | Exempt. It changes docs only. | user-answered | intent |
| D-5 | What doctor's upgrade-skew check tests | The review-toolkit files other plugins read after #1106: `workflows/intake-fanout.mjs` and `workflows/intake-review.mjs` (intake-toolkit), and `model-tiering.md` (dev-pipeline's config-lint). `code-review.mjs` leaves the check. run: `git grep -n 'code-review\.mjs\|intake-fanout\.mjs\|intake-review\.mjs\|model-tiering' -- plugins/intake-toolkit plugins/dev-pipeline` → intake: explore.md:60, split.md:112; dev-pipeline: config-lint.sh:53, run.sh:1104 (removed by #1106) | codebase-derived | fact |
| D-6 | What the docs say the lane reads | The lane reads `review-context.md` and writes its knowledge-base block. It reads `design.provider` on a record with design frames. Only the ad hoc review-lead reads `reviewers.add`, `reviewers.remove`, `reviewers.webComponentGlobs` and the per-reviewer `review-context/` files. cited (adr): docs/plans/second-shift-1106-decisions.md | codebase-derived | fact |
| D-7 | The config grill's T2 row and README:120 | Both say `reviewers.webComponentGlobs` routes the a11y and design reviews of the ad hoc review only. On the lane, the design reviewer keys off design frames. cited (adr): docs/plans/second-shift-1106-decisions.md | codebase-derived | fact |

Options weighed:
- D-1: deprecate and keep valid, remove it as a breaking change, or leave it. The operator chose deprecate.
- D-2: stop asking and keep the format, keep asking reworded, or retire the row. The operator chose retire.
- D-3: add the three files, or keep the table only. The operator chose add.

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | The section catalog's reader lines | reversible-default-and-flag |
| OR-2 | Where the `reviewers.default` warning is printed | reversible-default-and-flag |

Defaults, both chosen by the intake session. Each costs one file edit to reverse.
- OR-1 default: keep the reader tokens in `section-catalog.txt`, which stay true for the ad hoc path. Reword the knowledge-base row's description to name the lane session and review-lead. Doctor's coverage report does not change.
- OR-2 default: a config-grill advisory finding, which doctor and onboard print as WARN. `config-lint.sh` has no warning level, only errors.

## Test intent

ACs: AC-8 AC-12

AC-8: exempt — docs only
AC-12: config-grill reports a set `reviewers.default` as an advisory finding, the commit hook passes an unknown name in it, and doctor's skew check fails on a review-toolkit that lacks `workflows/intake-fanout.mjs`

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | The warning for a set `reviewers.default` | decided (D-1) |
| S-2 | The commit hook on `reviewers.default` names | decided (D-1) |
| S-3 | The schema's `reviewers.default` description | decided (D-1) |
| S-4 | plan-interview's specialist-risk question | decided (D-2) |
| S-5 | receipt.md's `review panel` exception | decided (D-2) |
| S-6 | The five AC-8 docs | decided (D-6) |
| S-7 | The config grill's T2 row and README | decided (D-7) |
| S-8 | The consumer template and this repo's copy | decided (D-6) |
| S-9 | review-lead and scope-completeness descriptions | decided (D-3) |
| S-10 | The section catalog and doctor's coverage line | decided (D-6) |
| S-11 | Doctor's upgrade-skew message | decided (D-5) |
| S-12 | Onboard's scaffold, the extension manifest, shadowing and diff guards | out-of-scope — they stay true after #1106, since the lane reads `review-context.md`. |

## Checks

No ticket-specific checks. The configured checks cover this change.

## Intake steps

Requirements: the ticket body of #1105 as written. spec-reviewer: needs work, no blockers. Its surface gaps became this slice's table rows.

Split: split #1105 into #1106 and #1107, in order, on the operator's answer. This receipt is for #1107, queued when #1106 is closed.

Explore: done. Read plan-interview and receipt.md, config-lint, check-reviewer-references, the schema, onboard and its grill, the section catalog, doctor and the docs.

Fan-out: ran once for the #1105 split — 6 items touch this slice, see Fan-out

Dup-scan: no candidates at or above threshold 12

Post-merge scan: no post-merge AC.

Sizing: opus

<details>
<summary>Intake evidence: knowledge source and fan-out</summary>

## Knowledge source

Knowledge source: none declared

## Fan-out

Run: shared with the #1105 split — slices #1106, #1107; supersedes the pre-split run on #1105
Refuter: cross (opus/fable alternating)
Lenses: reader-writer-parity opus 6/6 · session-runtime-and-grants fable 3/6 · measurement-validity opus 6/6 · in-flight-and-legacy-state fable 3/6 · premortem fable 3/6
Tally: rows added 2 · snapshot claims overturned 1 · questions added 1

| ID | Angle | Claim | Tag | Disposition |
| --- | --- | --- | --- | --- |
| F-1 | reader-writer-parity | `docs/extension-points.md` describes the knowledge sink on a lane path #1106 changes (`run.sh:1137-1139`) | already-had | became D-6 |
| F-2 | reader-writer-parity | Intake keeps asking for `review panel` rows until this slice lands (`plan-interview/SKILL.md:58`) | already-had | question: became D-2 |
| F-5 | reader-writer-parity | Onboard's scaffold, the extension manifest and two guards describe `review-context.md` and `reviewers.*` (`scaffold-review-context.sh:26`) | new | S-12, out of scope with its reason |
| F-6 | reader-writer-parity | Doctor blames dev-pipeline and intake-toolkit for `code-review.mjs`, which neither reads after #1106 (`doctor.sh:294-300`) | overturned (snapshot: "doctor's skew check stays valid") | became D-5 |
| F-18 | in-flight-and-legacy-state | Every ticket intaken between #1106 and this slice gets a `review panel` row (`receipt.md:144-145`) | already-had | became D-2 |
| F-21 | premortem | `reviewers.default` goes silent with no lint or doctor line (`config-lint.sh:261-262`) | new | became D-1 |

### Snapshot

    # #1105 — explore-first snapshot (before the fan-out pool)

    Read at origin/main df52f6bd.

    ## Facts (codebase-derived)

    - S-F1 The build's ticket-read instruction is run.sh:1030–1031; :401 is only the jira MCP grant. review_allowlist (:1198–1205) already grants `Bash(gh issue view*)` and `$MCP_ALLOW`: AC-2 needs no new grant.
    - S-F2 The "at the severity the performance rules give it" sentence is run.sh:1096 and review/SKILL.md step 5 (:99–100); no lockstep marker binds them.
    - S-F3 verdict-check.sh parses only the `- [blocker] B<n> ` / `- [note] N<n> ` prefix; the `[Reviewer] file:line (confidence: N)` form is named in its header comment (:21) and never checked. `## Panel` stays in its section order (:47).
    - S-F4 review/SKILL.md step 1 only extracts the `Closes` token; the ticket is read today only by scope-completeness-reviewer via review-lead (step 6). The skill needs its own ticket read.
    - S-F5 doctor.sh:293–301 requires `workflows/code-review.mjs` + `model-tiering.md` when dev-pipeline or intake-toolkit is enabled. Still valid: intake reads `workflows/intake-fanout.mjs`, config-lint reads model-tiering.md, ad hoc review-lead reads code-review.mjs. No change.
    - S-F6 config-lint.sh:255–264 keeps validating `reviewers.*`; ad hoc review-lead still reads all of them. No schema change → no configVersion bump or migration doc; the lane-side no-ops go in the Changelog `Migration:` line.
    - S-F7 The bench arm can be held to the prompt mechanically: a `LOCKSTEP-BEGIN` block in run.sh's heredoc and the arm file (check-lockstep-pairs.sh discovers pairs; a lone site fails). Today's `review-lead-lane.md` is a prose paraphrase with no guard.
    - S-F8 Consumer usage (operator's clones): KB-contributions section in 4 consumer review-context.md files; `reviewers.add` 1 consumer, 1 agent; `design.provider: figma` 2 consumers; `reviewers.default` 0; `reviewers.remove` 2; per-reviewer `review-context/` dirs in 3; `review panel` rows in 3 records across all repos.
    - S-F9 The review prompt keeps "Do not run the repo's test suites or checks" (run.sh:1106); probes stay Out.

    ## Questions (intent)

    - Q1 KB contributions block: session writes it (keep) or drop.
    - Q2 review-context.md: session loads the shared core; per-reviewer files and the check-review-context.sh grant.
    - Q3 reviewers.add[]: dispatch from the session (keeps Agent) or lane no-op.
    - Q4 reviewers.remove/webComponentGlobs/default: lane no-op, documented (follows Q3).
    - Q5 design-fidelity seat on RS-n records: session compares renders itself, or keep the provider's reviewer.
    - Q6 pillars beyond completeness/correctness (maintainability, test coverage, conventions): advisory notes or out.
    - Q7 `review panel` rows + cost-risk rule + intake's ask (plan-interview step 5, receipt.md:144).
    - Q8 finding form for session-raised code findings.
    - Q9 AC-9: arm + lockstep (AC) vs the two-run measurement (who, when).
    - Q10 REVIEW spawn: foreground like BUILD (follows Q3/Q5).
    - Q11 Code:/Record: Summary lines from the closed PR.
    - Q12 policy_edited + :1113 wording (follows Q2/Q3).

    ## After the split (#1106, #1107) — register by slice, before the split's pool

    Folded from the first fan-out (wf_5c634009-9ac, superseded by the split's run): overturned S-F6 in part (`reviewers.default[]` has no reader outside the lane); overturned S-F5 in part (doctor's skew message names dev-pipeline and code-review.mjs). New facts: S-F10 the review keeps `--add-dir $SCRATCH` without the Workflow (record-at-first, drafts); S-F11 run-claim-selftest (fe2, fe3) and run-selftest (a) assert the REVIEW background settings; S-F12 REVIEW has no raised Bash timeouts; S-F13 plain Opus bench runs used at most 20 turns per PR (results-20261022T085933Z, T110224Z) vs the lane's 300 cap; S-F14 the lockstep block for the arm must hold no shell variables and no `{`/`}` (bench.py str.format).

    #1106: Q6 pillars · Q1 KB block · Q2 review-context.md · Q3+Q4+Q12 repo-local config on the lane · Q5 design seat · Q7a scoring an existing `review panel` row + cost-risk rule · Q8 finding form · Q9 AC-9 measurement + sync · Q10 spawn foreground + timeouts · Q11 Summary lines · Q13 unreadable ticket routing (blocker burns a build round vs env terminal).
    #1107: Q7b intake's ask · Q14 `reviewers.default[]` readers (keep, deprecate, remove) · surfaces.

</details>
