# #957 — intake receipt

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Mechanism: rerun the baseline tests, or read the diff | Diff-only: a new review-input section built from `git diff $FIRST..HEAD`; no test rerun, no temp worktree, no extra install or suite run. Weighed: the ticket's restore-and-rerun (temp worktree + setup lanes, temp worktree + symlinked deps, in place in `$WT`; full `commands.test` vs restored paths), folding a diff-only detector into #956, closing #957, diff-only here. The rerun was dropped on cost vs value: about 13s install + 26s suite per head on the bench consumer, worktree-dirt and stall hazards, defeats by HEAD's test config, and 2 of 3 real lane builds firing on legitimate changes, while it adds only precision over the diff. An earlier "full `commands.test`" answer was given under the rerun and lapses with it; the load-error classifier the ticket left open is moot with it | user-answered | intent |
| D-2 | Which files the section covers | Existing files with status `M` in `git diff --name-status $FIRST..HEAD` that match #956's widened test-path pattern (the same definition, not a copy), plus every path under `__snapshots__/` or ending `.snap`, named explicitly so an anchored spec-suffix pattern cannot drop snapshots. Deleted and renamed test files stay in the existing first section | user-answered | intent |
| D-3 | What the section shows per file | The path, then its removed (`-`) diff lines (the old expectations), at most 20 per file followed by `(… N more)` when cut. A matched file with no removed lines is not listed, so an additive test change prints `(none)` | user-answered | intent |
| D-4 | Section heading and placement | Heading `### Existing test or snapshot expectations changed (removed lines)`, written directly after `### Deleted or renamed test files` in `review_input`; prints `(none)` when empty, like its siblings | user-answered | intent |
| D-5 | What the review does with each entry | `review_prompt` asks the review to trace each listed file's changed expectation to an acceptance criterion or a decision-record row; an untraced entry is a Warning with the required citation, never a Blocker; the `## Scheduler input (...)` heading line names the new section. Per the operator decision in the ticket body, https://github.com/manoldonev/second-shift/issues/957 | ticket-sourced | fact |
| D-6 | Gate or input | Review input only: the scheduler never goes red, re-spawns or exits on it. Ticket body, https://github.com/manoldonev/second-shift/issues/957 | ticket-sourced | fact |
| D-7 | Manual review path | `plugins/dev-pipeline/skills/review/SKILL.md` step 4 adds one clause: modified existing test or snapshot files and their removed expectations, each traced to an AC or a record row. It is the only review a handoff-built PR gets | user-answered | intent |
| D-8 | Expectations weakened outside the test globs (shared helpers, mocks, setup files) | Out of scope for this PR. A config-declared helper glob is a separate ticket, filed only if lane PRs show the gap | user-answered | intent |
| D-9 | Dependency on #956 | The section reuses #956's widened pattern; build only once #956 is merged. Parked under OR-1 (owner: operator, before queueing) | deferred | open |
| D-10 | Regression guard | `run-selftest.sh` cases: a build that edits an assertion in an existing spec and a `.snap` file, so the section (extracted by heading, as `run-selftest.sh:249` does) names both files and the removed line; a build that only adds lines to an existing spec, so the section is `(none)`. Required by CLAUDE.md, since a `run.sh` behavior change lands with a `run-selftest.sh` case that fails without it | codebase-derived | fact |

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | #956 is not merged when the build starts, so the widened test-path pattern D-2 reuses does not exist yet | pause-and-ask |

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | The new review-input section: heading, per-file lines, cap marker, empty form | decided (D-3) |
| S-2 | Section heading copy and position among the scheduler-input sections | decided (D-4) |
| S-3 | The review prompt's trace instruction and its `## Scheduler input` heading line | decided (D-5) |
| S-4 | Verdict-comment entries for untraced changed expectations (Warning severity) | decided (D-5) |
| S-5 | Manual `/dev-pipeline:review` step 4 | decided (D-7) |
| S-6 | Scheduler log lines and exit codes | out-of-scope — the section is review input only and adds no log line or terminal (D-6) |
| S-7 | The build prompt | out-of-scope — it already says never to delete, skip or weaken a test; nothing changes there |

## Checks

No ticket-specific checks — the configured lanes cover this change.

## Fan-out

Refuter: cross (opus/fable alternating)
Lenses: consumer-worktree-cost opus 6/6 · oracle-edit-recall fable 5/6 · false-fire-attribution opus 6/6 · scheduler-integration fable 4/6 · premortem fable 4/6
Tally: rows added 1 · snapshot claims overturned 4 · questions added 1

| ID | Angle | Claim | Tag | Disposition |
| --- | --- | --- | --- | --- |
| F-1 | consumer-worktree-cost | The configured test command takes a path list, but vitest treats paths as substring filters and a missing path exits 1, like a red test | new | weighed in D-1; the rerun was dropped |
| F-2 | consumer-worktree-cost | A detached temp worktree with a symlinked node_modules costs 0.06s, stays clean and caught the tamper | overturned (snapshot: "rerun in place in $WT") | weighed in D-1 |
| F-3 | consumer-worktree-cost | A fresh install in a temp worktree costs about 13.4s and about 770M on the bench consumer | new | weighed in D-1 (cost) |
| F-4 | consumer-worktree-cost | The full suite takes 22-33s; restored paths alone take 1.5-3.8s | new | weighed in D-1 (cost) |
| F-5 | consumer-worktree-cost | An in-place restore is clean only via `git checkout HEAD -- paths`, and reusing run_checks re-runs the setup lanes | already-had | weighed in D-1 |
| F-6 | consumer-worktree-cost | A temp tree inside $WT is collected twice, and a FIRST-side run needs its own install when the lockfile changed | new | moot under D-1 |
| F-7 | oracle-edit-recall | Restore-and-rerun catches assertion edits and committed snapshots, and is silent on additive tests | already-had | weighed in D-1 |
| F-8 | oracle-edit-recall | Fixtures, helpers, setup files, each-tables and env files outside test globs are missed by any glob-keyed approach | new | became D-8 |
| F-9 | oracle-edit-recall | HEAD's test config (`update: true`, `-u`, `exclude`) can defeat the rerun | new | weighed in D-1 |
| F-10 | oracle-edit-recall | Nothing in lane() pins snapshot update off or the test config to FIRST | new | moot under D-1 |
| F-11 | oracle-edit-recall | The vitest JSON reporter separates a load error (no assertion results) from an assertion failure | overturned (snapshot: "load-error classifier: none, the log excerpt shows it") | moot under D-1 |
| F-12 | false-fire-attribution | A renamed source module or a moved helper fails as a file-level load error with zero test results | new | weighed in D-1 (false fires) |
| F-13 | false-fire-attribution | A renamed export is not a load error; it fails at call time as a TypeError | new | weighed in D-1 (false fires) |
| F-14 | false-fire-attribution | The error class cannot tell API drift from a behavior change; a typecheck of the restored tests separated 3 of 4 | new | weighed in D-1 (false fires) |
| F-15 | false-fire-attribution | Snapshots are restored today only because `.spec.` matches inside `.snap` names; an anchored pattern would drop them | new | became D-2 (snapshots named explicitly) |
| F-16 | false-fire-attribution | With CI unset, a missing snapshot key passes and writes a snapshot into the tree | new | weighed in D-1 |
| F-17 | false-fire-attribution | "Green at FIRST" is never established by the lane, so a test already red at FIRST false-fires | already-had | moot under D-1 |
| F-18 | scheduler-integration | An in-place restore leaves tracked dirt that worktree_inflight reads as the build's in-flight work | overturned (snapshot: "rerun in place in $WT") | weighed in D-1 |
| F-19 | scheduler-integration | The real cost is one more full suite (about 34s), and lane() is hardwired to $WT | new | weighed in D-1 (cost) |
| F-20 | scheduler-integration | A red rerun must not share run_checks' RED markers or log, or it becomes rebuild findings | new | moot under D-1 |
| F-21 | scheduler-integration | A rerun would slot once per head under the retry-suffixed attempt id | not material | not material — review_input already runs once per head |
| F-22 | premortem | On the bench consumer, 2 of 3 real lane builds would fire, all on legitimate behavior changes | new | weighed in D-1 (noise) |
| F-23 | premortem | Rerun cost roughly doubles to triples the check lane's test time per head | new | weighed in D-1 (cost) |
| F-24 | premortem | 59 of 92 specs import shared helpers outside the test globs | already-had | became D-8 (prevalence measured) |
| F-25 | premortem | lane() has no watchdog, so a stalled in-place rerun leaves dirt that close-out must never reset | overturned (snapshot: "restore failure is terminal env-worktree") | weighed in D-1 |

### Snapshot

    | ID | Decision | Resolution |
    | --- | --- | --- |
    | D-1 | How the rerun runs | rerun the configured commands.<repo>.test whole-suite in place in $WT with the test paths restored from $FIRST, then restore HEAD; run_checks just went green at HEAD, so a red is attributable to the restored files. Weighed: ticket's temp worktree (needs an install), per-file runner key (testFile retired in #574, config-lint rejects it), repo-carried script seam |
    | D-2 | Restored set | M/D/R paths matching #956's widened test glob (old path for R) plus snapshot files; #956 must merge first |
    | D-3 | Attribution and baseline | list the restored files and an excerpt of the red log; no separate run at FIRST |
    | D-4 | Section states and copy | distinct lines for: no test command configured / no expectation file changed / ran, none red / red (listed) / could not run (reason) — none of the not-run states prints (none) |
    | D-5 | Restore failure | terminal env-worktree — the scheduler must not leave the build's worktree altered |
    | D-6 | Load-error classifier | none; the log excerpt shows the load error; deferred until lane PRs measure noise |
    | D-7 | In-place / shared-fixture variant | out of scope |
    | D-8 | Manual /dev-pipeline:review step 4 (parallel path, also the HANDOFF build's review) | add the rerun to step 4 |
    | D-9 | Severity of an untraced entry | Warning with the required citation (operator, issue body) |
    | D-10 | Review prompt trace instruction | review_prompt asks to trace each listed test to an AC or a record row; heading line updated |
