# Decision record — #1106 Lane review: one session against the ticket and record, no review-lead

Receipt: v4

## Summary

The lane's review session stops running `review-toolkit:review-lead` and its `code-review.mjs` Workflow. It reviews the diff itself against the ticket and the record, for completeness and correctness. Only the design-fidelity reviewer still runs, and only on a record with design frames. A new benchmark arm shares the prompt's instruction text through a lockstep block. The operator measures it before merge.

Open regions: OR-1, the instruction's wording. OR-2, the arm's tool list. OR-3, the arm's name. All are flagged defaults.

Provenance legend: `user-answered` = the operator chose. `codebase-derived` = a fact from the code or the docs, with its proof.

Open region legend: `reversible-default-and-flag` = the build uses the stated default.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | What the session reports beyond completeness and correctness | Completeness and correctness findings can be `[blocker]`s. Maintainability, test coverage and repo conventions are `[note]`s only. A missing test for an AC is a completeness finding. | user-answered | intent |
| D-2 | Which seats still run on the lane | Only the design-fidelity reviewer, and only on a record with `RS-n` rows. The handoff host or `design.provider` picks it, as today. `Agent` stays for that dispatch. `reviewers.add`, `reviewers.remove`, `reviewers.default` and `reviewers.webComponentGlobs` become lane no-ops. AC-10's `Migration:` line names all four. | user-answered | intent |
| D-3 | Which review context the session loads | The session reads `.claude/second-shift/review-context.md` from the head. The per-reviewer files under `review-context/` are not read on the lane. The `Bash(bash *check-review-context.sh*)` grant goes. | user-answered | intent |
| D-4 | The knowledge-base contributions block | Kept. The session applies the inclusion test that `review-context.md` declares and writes the block in `## Notes`. Both `kb-contributions` lockstep copies drop "review-lead's report". The run-verdict-selftest (kb) case and the fake review in `run-selftest-lib.sh` change with them. | user-answered | intent |
| D-5 | An existing `review panel` record row | The row kind is retired. #1107 removes intake's ask and its format. The lane gives such a row no special handling and dispatches nothing for it. No in-flight record carries one. | user-answered | intent |
| D-6 | A record row that names a cost, load or performance risk | The session states the worst-case bound itself, as a finding. The finding is a `[blocker]` when the bound breaks what the row decided, else a `[note]`. The dispatch-or-decline process blocker goes. | user-answered | intent |
| D-7 | The shape of a finding the session raises | `- [blocker] B1 path:line — <defect>`, then the continuation line `Scenario: <input or state> → <wrong outcome>`. A blocker ends with `Fix: <one instruction>`. No confidence number. A dispatched seat's finding names the seat in brackets before path:line. | user-answered | intent |
| D-8 | A review that cannot do its job for an environment reason | Line 3 gains `reason: ticket-unreadable` and `reason: seat-unavailable` beside `reason: render-unavailable`. The scheduler stops with `env-not-ready` and spawns no BUILD. This replaces AC-2's "is a `[blocker]`". `verdict-check.sh` accepts both reasons, with one run-verdict-selftest case each. | user-answered | intent |
| D-9 | Who measures the new arm | The PR commits the arm and its lockstep block. The operator runs the new arm and `plain` on Opus, two runs each, before merge (PM-1). The lane runs no benchmark. | user-answered | intent |
| D-10 | How the arm stays in step with `review_prompt()` | The shared instruction text sits in a `LOCKSTEP-BEGIN` block in `review_prompt()`, written as a quoted heredoc filtered by `grep -v 'LOCKSTEP-'`. The same block sits in the arm. `check-lockstep-pairs.sh` compares them. The block holds no shell variables and no `{` or `}`. | user-answered | intent |
| D-11 | What the arm hands to the bench's scorer | Every `[blocker]` and every `[note]` that is not `Dismissed.` or `Suppressed.`, one per numbered item. | user-answered | intent |
| D-12 | How the review session is spawned | Foreground, like BUILD. It gets `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1` and Bash timeouts of `inner_ms "$REVIEW_TO" 120`, BUILD's derivation on its own bound. `REVIEW_BG_WAIT_MS` and the wait ceiling go. The `PermissionRequest` hook stays BUILD-only. `--add-dir $SCRATCH` stays. | user-answered | intent |
| D-13 | The `Code:` and `Record:` Summary lines of the closed PR #1101 | Not added. The Summary stays as it is on `main`. | user-answered | intent |
| D-14 | AC-4's test intent | `holds`. Its tests keep existing behavior and pass without the change. | user-answered | intent |
| D-15 | AC-6's test intent | Exempt. It is skill prose, and only a prose grep could test it. | user-answered | intent |
| D-16 | AC-10's test intent | Exempt. It is a commit trailer, and CI's `check-changelog-trailer.sh` enforces it. | user-answered | intent |
| D-17 | AC-11's test intent | Exempt. It is release-checklist prose. | user-answered | intent |
| D-18 | AC-9's test intent | Tested. A selftest loads the new arm through `bench.py`'s own `parse_arm` and `.format`. It fails without the arm, and it catches a brace that would crash the bench. | user-answered | intent |
| D-19 | Where the session's ticket read comes from | New prompt text, modeled on BUILD's at run.sh:1030. No new grant: `review_allowlist()` already grants `Bash(gh issue view*)` and `$MCP_ALLOW`. AC-2's run.sh:401 is the jira grant only. run: `grep -n 'gh issue view' plugins/dev-pipeline/skills/run/run.sh` → :1030 the build's instruction, :1199 the review's grant | codebase-derived | fact |
| D-20 | The manual review skill's ticket read | `review/SKILL.md` gains its own ticket read in step 1, under AC-6. Today only the scope seat read the ticket. run: `grep -c 'gh issue view' plugins/dev-pipeline/skills/review/SKILL.md` → 0 | codebase-derived | fact |
| D-21 | Where the performance sentence lives | run.sh:1096 and review/SKILL.md:99–100. Both copies are rewritten per D-6. The kept selftest grep matches text before the rewritten part. run: `grep -n 'at the severity the performance rules' plugins/dev-pipeline/skills/run/run.sh plugins/dev-pipeline/skills/review/SKILL.md` → run.sh:1096, SKILL.md:100 | codebase-derived | fact |
| D-22 | What `policy_edited()` lists | `.claude/second-shift.config.json` and `.claude/second-shift/` only. The `reviewers.add[]` agent-file derivation goes, since no lane reader loads those files after D-2. The prompt line says the session loads these files from the head. run: `sed -n 995,996p plugins/dev-pipeline/skills/run/run.sh` → "the reviewers load these from the head"; `.reviewers.add[]?.name` | codebase-derived | fact |
| D-23 | `review_allowlist()` grants | Drop `Skill`, `Workflow`, `Bash(find *)`, `Bash(cp *)`, `Bash(shasum *)` and `Bash(bash *check-review-context.sh*)`. Keep the rest, `Agent` included (D-2). run-rows-selftest F20 asserts the inverse. run: `sed -n 1199p plugins/dev-pipeline/skills/run/run.sh` → the current grant list | codebase-derived | fact |
| D-24 | `verdict-check.sh` | Logic unchanged except D-8's reasons. `## Panel` stays an optional, unparsed section, so earlier verdicts still parse. Its header comment drops the review-lead finding form. run: `sed -n 21,23p;47p plugins/dev-pipeline/tools/verdict-check.sh` → "nothing here checks it"; `order["## Panel"] = 4` | codebase-derived | fact |
| D-25 | The review's `--max-turns 300` | Unchanged. Opus review runs on the bench used far fewer turns. run: `jq '[..\|objects\|select(has("num_turns")).num_turns]\|max' results-20261022T085933Z.json` → 20 (plain, Opus) | codebase-derived | fact |
| D-26 | Where `review-lead-lane` is named as the lane's measurement | `scripts/derive-release.sh:440`, `docs/releasing.md:99` and the bench README:64. All three name the new arm (AC-11). run: `grep -n review-lead-lane scripts/derive-release.sh docs/releasing.md plugins/review-toolkit/evals/code-review-bench-eval/README.md` → 440, 99, 64 | codebase-derived | fact |

Options weighed:
- D-1: other pillars as notes, completeness and correctness only, or every pillar can block. The operator chose notes.
- D-2: design and repo-local seats, design only, design on records with frames only, or no seats. The operator chose design on records with frames only.
- D-3: the shared core only, core plus per-reviewer files, or not loaded. The operator chose the shared core.
- D-4: keep with the session writing it, or drop. The operator chose keep.
- D-5: dispatch the named seat, the session covers it, or score it departed. The operator first chose dispatch, then retired the row kind in #1107.
- D-6: always a blocker, always a note, or blocker when the decided bound breaks. The operator chose the last.
- D-8: an environment stop with no round spent, or a `[blocker]`. The operator chose the stop.
- D-9: the operator before merge, the lane BUILD, or nobody. The operator chose the operator.
- D-12: foreground like BUILD, or keep the background settings. The operator chose foreground.
- D-13: keep the Summary, or add the two lines. The operator chose keep.

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | The exact wording of the completeness and correctness instruction | reversible-default-and-flag |
| OR-2 | The new arm's `allow:` line | reversible-default-and-flag |
| OR-3 | The new arm's file name | reversible-default-and-flag |

Defaults, all chosen by the intake session. Each costs one prompt or arm edit to reverse.
- OR-1 default: the build writes the instruction from AC-1's text and D-1. The PR body quotes it.
- OR-2 default: `Read,Grep,Glob,Write,Bash(git *)`. That is the review's read grants plus `Write` for the output file. The bench forbids `gh`, and it has no design frames.
- OR-3 default: `arms/lane-review.md`.

## Test intent

ACs: AC-1 AC-2 AC-3 AC-4 AC-5 AC-6 AC-7 AC-9 AC-10 AC-11

AC-1: the review prompt the scheduler records names no review-lead invocation and no panel declaration, and carries the completeness and correctness instruction
AC-2: the review prompt tells the session to read the ticket, and a verdict with `reason: ticket-unreadable` ends the run with `env-not-ready` and no BUILD spawn
AC-3: verdict-check accepts a verdict with no `## Panel` and the new line-3 reasons, and the `verdict-grammar` and `verdict-style` pairs agree
AC-4: holds — verdict-check before and after posting, expectation tracing, the render rule, the bot identity and the status keep working
AC-5: the review spawn's allowlist lacks `Workflow`, `Skill`, `Bash(find *)`, `Bash(cp *)`, `Bash(shasum *)` and the review-context lint, and its env disables background tasks
AC-6: exempt — skill prose, held to run.sh by the lockstep check
AC-7: a run-selftest case over the recorded review prompt fails on the record tree
AC-9: the new arm loads and formats through bench.py's own parser without error
AC-10: exempt — a commit trailer that CI's trailer check enforces
AC-11: exempt — release-checklist prose

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | A finding in the lane's verdict comment | decided (D-7) |
| S-2 | The verdict's line-3 environment reasons | decided (D-8) |
| S-3 | The knowledge-base block in the verdict's Notes | decided (D-4) |
| S-4 | The run's terminal on an unreadable ticket | decided (D-8) |
| S-5 | Earlier verdicts that carry `## Panel` | decided (D-24) |
| S-6 | A record row naming a `review panel` | decided (D-5) |
| S-7 | A record row naming a cost risk | decided (D-6) |
| S-8 | The manual `/dev-pipeline:review` skill | decided (D-20) |
| S-9 | The new arm's bench row | decided (D-9) |
| S-10 | The release checklist and bench README | decided (D-26) |
| S-11 | The Changelog `Migration:` line | decided (D-2) |
| S-12 | The ad hoc review-lead report on a foreign PR | out-of-scope — the ticket's Out keeps it unchanged. |
| S-13 | Consumer docs, onboard and intake's ask | out-of-scope — #1107 changes them. |

## Checks

- `bash scripts/check-lockstep-pairs.sh`

## Intake steps

Requirements: the ticket body of #1105 as written. spec-reviewer: needs work, no blockers. Its line and surface gaps became fact rows and two questions.

Split: split #1105 into #1106 and #1107, in order, on the operator's answer. The register passed ten decisions and the change touches about 26 files. This receipt is for #1106.

Explore: done. Read run.sh's review prompt, grants and spawn, review/SKILL.md, verdict-check.sh, review-lead's routing, the bench arms and results, doctor, config-lint and four consumer configs.

Fan-out: ran once for the #1105 split — 17 items touch this slice, see Fan-out

Dup-scan: no candidates at or above threshold 12

Post-merge scan: AC-9's measurement moved to PM-1 on the operator's answer (D-9). #1106's body was edited to match.

Sizing: opus

<details>
<summary>Intake evidence: knowledge source and fan-out</summary>

## Knowledge source

Knowledge source: none declared

## Fan-out

Run: shared with the #1105 split — slices #1106, #1107; supersedes the pre-split run on #1105
Refuter: cross (opus/fable alternating)
Lenses: reader-writer-parity opus 6/6 · session-runtime-and-grants fable 3/6 · measurement-validity opus 6/6 · in-flight-and-legacy-state fable 3/6 · premortem fable 3/6
Tally: rows added 4 · snapshot claims overturned 1 · questions added 2

| ID | Angle | Claim | Tag | Disposition |
| --- | --- | --- | --- | --- |
| F-1 | reader-writer-parity | The `kb-contributions` pair fails the lockstep check if one copy goes, and `run-selftest-lib.sh:210-211` fakes the block | new | became D-4 |
| F-2 | reader-writer-parity | verdict-check makes an existing `review panel` row block unless a scoring rule exists (`verdict-check.sh:80-85`) | already-had | became D-5 |
| F-3 | reader-writer-parity | run-selftest (a), run-claim-selftest fe2/fe3 and run-rows I10 assert the spawn settings and `policy_edited()` | new | became D-12 and D-22 |
| F-4 | reader-writer-parity | The bench README:64 calls `review-lead-lane` the arm "as the lane runs it" | new | became D-26 |
| F-7 | session-runtime-and-grants | REVIEW has no raised Bash timeouts, so foreground means adding BUILD's trio (`run.sh:1747-1751`) | overturned (snapshot: "foreground like BUILD follows from the seat answers") | became D-12 |
| F-8 | session-runtime-and-grants | Review runs use far fewer turns than the 300 cap (`changelog.md:9`) | already-had | became D-25 |
| F-9 | session-runtime-and-grants | Posting the status and minimizing verdicts are the scheduler's, not the session's (`run.sh:1412-1440`) | not material | not material — unchanged by this slice |
| F-10 | measurement-validity | A lockstep block must sit in a quoted heredoc with no variables (`run.sh:1116`) | already-had | became D-10 |
| F-11 | measurement-validity | A brace in the arm crashes `bench.py` before any session (`bench.py:195`) | new | became D-18 |
| F-12 | measurement-validity | `--runs 2` prints one pooled F1, and voided runs shrink the denominator (`bench.py:447-450`) | not material | not material — the operator reads per-run JSON for PM-1 |
| F-13 | measurement-validity | No committed Opus baseline row exists in the bench changelog (`changelog.md:10-13`) | new | question: became D-9 and PM-1 |
| F-14 | measurement-validity | The arm must choose what it transcribes from blockers and notes (`rules.md:12-20`) | new | question: became D-11 |
| F-16 | in-flight-and-legacy-state | Legacy verdicts with `## Panel` and new ones both pass verdict-check (`verdict-check.sh:47`) | already-had | became D-24 |
| F-17 | in-flight-and-legacy-state | An existing `review panel` row changes the verdict once no seat runs (`verdict-check.sh:114`) | already-had | became D-5 |
| F-19 | premortem | CI cannot catch a worse review, so the measurement is the only guard (`rules.md:6-8`) | already-had | became D-9 |
| F-20 | premortem | 300 turns may not fit one session doing every trace (`run.sh:1851`) | not material | not material — D-25's measured turns |
| F-21 | premortem | `policy_edited()` and `reviewers.default` go silent unless the record decides them (`run.sh:995-999`) | already-had | became D-22 and D-2 |

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
