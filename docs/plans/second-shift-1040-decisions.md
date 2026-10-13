# Intake receipt — #1040 dev-pipeline: the scheduler proves each tagged test fails without the change

Receipt: v4

## Intake steps

Requirements: the ticket body as filed plus its one operator comment; plan-interview pre-flight, no requirements interview; the interview replaced the filed red-commit design and the ticket was reworded with the operator's approval (D-10)
Split: not split — already the layer-3 slice of #1018; its predecessor #1039 is merged
Explore: done — run.sh (run_checks, plan_coverage, red_attempt, record_at_first, FIRST derivation, rebase_onto_base, --handoff exit, config read at launch), plan-coverage.sh, config-lint.sh commands keys, run-selftests.sh, the #1039 record, the consumer configs' test commands, one consumer's test-placement rules
Fan-out: ran — 22 items survived refutation, see Fan-out
Dup-scan: no candidates at or above threshold 12 (corpus: 0 scanned)
Post-merge scan: no post-merge AC — every AC is observable through a selftest in the diff
Sizing: opus

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | What layer 3 proves, and how the scheduler gets the red state | The harness builds it: the head's tagged test files applied onto the record commit's tree (base code, no implementation) must fail there; passing at head is the configured checks'. It proves "fails without the change" — one executed whole-change mutant per tagged file — never that a test was written first, which no history check can show (F-13, F-15). No red commit is looked up, so rebase, review rounds and squashes need nothing special. Plan order is not gated: the plan-position note in run.sh stays a note and its "#1040 owns the order" wording is updated. Mutation review stays the opt-in judgment on test strength. Weighed: harness-built tree; red commit by content (oldest commit adding the file); a build-declared `Red:` trailer; not building layer 3; folding it into a revived mutation executor | user-answered | intent |
| D-2 | Assertion failure vs setup failure on the red leg | Not distinguished: any failure without the change counts. A setup or environment failure present at both legs is caught by the head leg; one present only without the change is caused by the change. AC-6's "or fails there for a reason other than its assertion" is struck from the ticket. Weighed: drop it; an optional per-runner config pattern (parses build-controlled runner output, F-16, and still classes the honest TDD red as setup, F-2); keep as written | user-answered | intent |
| D-3 | How a tagged test is addressed and run | Every task carrying `[AC-n]` must name its test files in its `(files)` parenthetical; plan-coverage.sh starts enforcing that on tagged tasks (red naming the task). A new optional config key `commands.<id>.testRunners: [{when: [globs], command: "… {file}"}]` (the extraLanes `when` shape) maps a file to the command that runs it; config-lint, the JSON schema and docs/config-schema.md learn it. It is never named `testFile`, a retired key config-lint rejects by name. The unit is the file: one failing case in a file floors every AC tagged on it (accepted residual; per-test name filters exit 0 on no match, F-3). No runner configured → layer 3 is not-applicable, noted in the run log and block, and the run goes on; a record with no Test intent or `ACs: none` → not-applicable as in #1039. A file matching no runner is governed by D-11. Weighed: plan files + config runner; every runner-matching file changed since the record commit; appending the file to `commands.test` | user-answered | intent |
| D-4 | An AC about existing behavior | A new Test intent line form `AC-n: holds — <behavior>`: still must be tagged (coverage), its files are kept off the red leg, and the configured checks at head prove it. Like an exemption, every `holds` is put to the operator at intake and recorded as a `user-answered` row. ledger-lint.sh, plan-coverage.sh, receipt.md and interviewing-baseline learn the form. Weighed: a holds form off the red leg; a holds form that must also pass on the red tree (breaks when a holds case shares a spec file with new cases); `exempt — <reason>` (loses coverage) | user-answered | intent |
| D-5 | What a tagged file passing on the red tree does in the run | `red_attempt`: the log names each AC and file and goes to a re-spawned build on the shared checks-red counter (the third red of any kind ends `checks-red-spent`). Fixable by strengthening the test in a new commit, so a terminal would stop a run a build can repair. Weighed: red_attempt; a terminal for a human | user-answered | intent |
| D-6 | The check on the `--handoff` path | Lane only. On `--handoff` the review skill reports that the fails-without-the-change check was not run on the handoff path, in its verdict, never as a blocker; post-review-status.sh is unchanged. A session running test suites in a worktree it controls is not a harness proof. Weighed: lane only, noted; the review skill runs it with post-review-status.sh refusing a success while red, as #1039 D-10 did | user-answered | intent |
| D-7 | Where the red tree is built | In `$WT` after the checks and plan coverage pass, when it is clean at the head: detach to the record commit, check out only the tagged test files from the head, run each through its runner, restore the branch under an EXIT trap; `--resume` re-checks out the branch before anything else. Gitignored dependencies stay, so nothing is reinstalled. The file list and the AC map come from plan-coverage.sh through a new output mode, never a second plan parser. Weighed: in `$WT`, trap-restored; a separate scratch worktree with setup lanes on every pass | user-answered | intent |
| D-8 | Rollout of `testRunners` | DEPARTED: this repo's own config cannot gain the runners in this PR — `.claude/second-shift.config.json` is gitignored here as machine-local (it carries the bot's App identifiers, `.gitignore:22-26`), so no commit can carry it; the PR body gives the exact `testRunners` block (bash for `*-selftest.sh`, node for `*-selftest.mjs`, with the configured test command's env scrubs) for the operator to add to that file by hand, which turns the dogfooding on. Consumers opt in by hand from docs/config-schema.md; onboard's config draft is not taught the key. The key is optional and additive: no configVersion bump. Reason: the file the row names is outside version control, so the build cannot write it | user-delegated | intent |
| D-9 | This receipt's Test intent line for AC-8 | A behavior line, tagged on the same test task as AC-6 and AC-7: the run*-selftest cases tagged for AC-6 and AC-7 fail with the check removed from run.sh. Weighed: a tagged behavior line; `exempt — meta` | user-answered | intent |
| D-10 | The ticket text | #1040's title, goal, scope, sad paths, AC-6 and AC-7 rewritten to the decided design ("fails without the change" on the record commit's tree, holds and unchecked forms); AC-8 unchanged; its open questions marked resolved by this record. Edited at intake with the operator's approval | user-answered | intent |
| D-11 | A tagged file that no configured runner matches | Red, naming the AC and the file, unless the receipt marks the AC with a third new Test intent form `AC-n: unchecked — <tier and reason>` (e.g. a black-box API tier that needs the running app); then the file is noted, not run. Every `unchecked` is put to the operator at intake and recorded as a `user-answered` row, like exempt and holds; an unchecked AC still must be tagged. Closes the dodge of naming a file outside every runner glob. Raised by a side review during the interview. Weighed: declared at intake, else red; noted only; always red | user-answered | intent |
| D-12 | The retired config key name | `commands.<id>.testFile` is rejected by name as the retired mutation engine's per-spec runner template — run: `grep -c 'has("testFile")' plugins/dev-pipeline/tools/config-lint.sh` → 1 | codebase-derived | fact |
| D-13 | Whether the build can change the runner config mid-run | No: run.sh reads the config once at launch into memory, so `testRunners` is fixed for the run; the red leg also runs the record commit's own package and runner config — run: `grep -n '^CONFIG_JSON=' plugins/dev-pipeline/skills/run/run.sh` → 178 | codebase-derived | fact |
| D-14 | Where the AC-8 run.sh selftest case lands | A case in a `run*-selftest.sh` suite that fails without the change; the plan-coverage cases already live in run-record-selftest.sh — cited (convention): CLAUDE.md:120 | codebase-derived | fact |
| D-15 | The record commit after a rebase | rebase_onto_base and launch both re-derive FIRST as the commit adding the record, so the red tree follows a rebase with no stored hash — run: `grep -cF -- '--diff-filter=A -- "$RECORD_REL"' plugins/dev-pipeline/skills/run/run.sh` → 2 | codebase-derived | fact |
| D-16 | Receipt version for the holds and unchecked forms | OR-1's default, taken: no bump — the forms are additive inside v4's section, so every existing v4 receipt keeps linting clean and the lockstep receipt-versions table is unchanged; flagged in the PR body. Reason: the open region's own reversible default, nothing found against it | user-delegated | intent |
| D-17 | A file tagged by a behavior AC and by a holds or unchecked AC | It is run: the behavior AC puts it on the fails-without-the-change leg, and the holds or unchecked note says it is not run *for that AC*. plan-coverage.sh --files lists it under each AC's kind. Reason: D-4 keeps a holds AC from adding files to the leg; it cannot take one off a behavior AC that tags it too | user-delegated | intent |
| D-18 | The checks leave a tracked change in `$WT` before the leg | `terminal env-worktree`, naming the files: the record commit's tree cannot be built over a tracked change without discarding it, which run.sh never does; untracked and ignored files stay. Reason: D-7 builds the tree "when it is clean at the head" and names no path for the other case | user-delegated | intent |
| D-19 | A tagged file the head does not carry | Red, naming the AC and the file, on the checks-red counter like D-5 and D-11. Reason: a named test that does not exist proves nothing, and the build can fix the plan or add the file | user-delegated | intent |
| D-20 | When an interrupted leg is undone | A mark at `<pipelineStateDir>/run-<issue>/red-tree` is written before the detach and removed after the restore; any launch that finds it with the worktree present puts `$WT` back on the branch first (an unforced checkout, a refusal stops the run as `env-worktree`), whether or not `--resume` was passed. Reason: D-7 names `--resume`, but a plain re-launch re-entering a lane claim reaches the same worktree | user-delegated | intent |
| D-21 | How a task's `(files)` parenthetical is read | The parenthesized group that ends the description, after its AC ids are peeled off; its content split on commas and spaces, so a path holding a space is not addressable. An untagged task needs none. Reason: D-3 names the parenthetical but not its grammar; the plan grammar already ends descriptions with it | user-delegated | intent |

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | Whether the new `holds` and `unchecked` Test intent forms bump the receipt version or land inside v4's section | reversible-default-and-flag |

OR-1 default: no version bump — the forms are additive inside v4's section, so every existing v4 receipt keeps linting clean; the build flags the choice in the PR body. Reversing it later is one lockstep-table row.

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | The run log and run-block lines for the check: pass, not-applicable with its reason, unchecked notes | decided (D-3) |
| S-2 | The red findings a re-spawned build reads, naming each AC and file | decided (D-5) |
| S-3 | The build prompt's instruction: test files named on tagged tasks, each must fail without the change | decided (D-3) |
| S-4 | The receipt's `holds` and `unchecked` lines and the intake questions that settle them | decided (D-4) |
| S-5 | Lint violations for the new forms | decided (D-11) |
| S-6 | plan-coverage red for a tagged task that names no file | decided (D-3) |
| S-7 | The `testRunners` config key, its config-lint errors and its docs | decided (D-8) |
| S-8 | The handoff review's not-run note | decided (D-6) |
| S-9 | The checks-red-spent detail after a third red from this check | decided (D-5) |
| S-10 | The ticket text the scope reviewer scores | decided (D-10) |
| S-11 | A proof that a test was written before its code | out-of-scope — no history check can prove order; the build arranges its own history (D-1) |
| S-12 | onboard's drafted config | out-of-scope — consumers add the optional key by hand from the docs (D-8) |

## Checks

No ticket-specific checks — the configured lanes cover this change.

## Fan-out

Refuter: cross (opus/fable alternating)
Lenses: single-test-addressing opus 6/6 · red-commit-anchor fable 6/6 · build-as-adversary opus 6/6 · consumer-placement-fit fable 3/6 · premortem fable 1/6
Tally: rows added 1 · snapshot claims overturned 1 · questions added 1

| ID | Angle | Claim | Tag | Disposition |
| --- | --- | --- | --- | --- |
| F-1 | single-test-addressing | Jest exits 1 alike for an assertion, a beforeAll throw, an import error and a missing path; only its JSON report tells them apart | new | became D-2 |
| F-2 | single-test-addressing | Under the consumer's ts-jest transform the honest test-first red is a TypeError or "suite failed to run", not an assertion | new | became D-2 |
| F-3 | single-test-addressing | Jest `-t` with no match exits 0 with every test skipped; Playwright exits 1 | new | became D-3 (the file is the unit) |
| F-4 | single-test-addressing | Playwright's JSON report has no structured assertion-vs-setup field; the consumer's API-tier lane runs only static checks | new | became D-2 and D-11 |
| F-5 | single-test-addressing | This repo's bash selftests cannot run a single case; a setup FATAL exits 1 like a FAIL; run-selftest.sh takes about 221s | new | became D-3 |
| F-6 | single-test-addressing | Addressing a test needs the file path, and the plan grammar names none | already-had | became D-3 |
| F-7 | red-commit-anchor | No commit hash survives rebase_onto_base; FIRST is re-derived by position and blob | already-had | became D-15 |
| F-8 | red-commit-anchor | The oldest commit adding a test file resolves correctly after a clean rebase | new | became D-1 (weighed, not adopted) |
| F-9 | red-commit-anchor | A test added in a review round has no red commit; one edited there differs from its first-add blob | already-had | became D-1 |
| F-10 | red-commit-anchor | A squash and force-push from the worktree is invisible to the scheduler and the review | new | became D-1 |
| F-11 | red-commit-anchor | run.sh notes the plan's position and leaves gating the order to #1040 | already-had | became D-1 |
| F-12 | red-commit-anchor | The consumer's configured test is the whole jest run and its API tier needs the running app | already-had | became D-11 |
| F-13 | build-as-adversary | A build can write code and test together, then commit a test-plus-stub "red" commit and the code after it | overturned (snapshot: "a build-written commit trailer ... found by message" offered as a red-commit anchor) | became D-1 |
| F-14 | build-as-adversary | An assertion-only rule rewards a stub or `assert.ok(false)` and punishes the honest red | new | became D-2 |
| F-15 | build-as-adversary | A test's body can change between a red commit and the head, so both legs pass a sabotaged red | new | became D-1 |
| F-16 | build-as-adversary | Configured commands resolve through build-committed package scripts, so runner output is forgeable | new | became D-13 |
| F-17 | build-as-adversary | A tagged task naming no file passes coverage, and the consumer's API tier is never executed | new | became D-3 and D-11 |
| F-18 | build-as-adversary | The --handoff path stops before the checks; a session-run proof runs in a worktree the session controls | already-had | became D-6 |
| F-19 | consumer-placement-fit | The Test intent grammar has two forms; an existing-behavior or untestable-tier line lints as an ordinary behavior and then needs a test task | already-had | became D-4 and D-11 |
| F-20 | consumer-placement-fit | The selftest tier has no case filter and no assertion-vs-setup signal at the process boundary | already-had | became D-2 |
| F-21 | consumer-placement-fit | Which Test intent line this ticket's own meta-AC gets is undecided | new | became D-9 |
| F-22 | premortem | A red from a round-2 test would spend the shared counter, and a hash in build-writable state dies on rebase | already-had | became D-5 |

### Snapshot

    | ID | Decision | Resolution |
    | --- | --- | --- |
    | D-1 | How the scheduler finds "the red commit" for a tagged test | open: (a) a build-written commit trailer (e.g. `Red: AC-1 AC-3`) on a commit in FIRST..HEAD, found by message so it survives rebase_onto_base; (b) positional — the commit after the plan commit; (c) no red commit at all: run head's tagged test files on FIRST's tree ("fails without the change", SWE-bench style). Epic split note assumes "finds the red commit through the plan" without saying how |
    | D-2 | How one tagged test is run on its own | open: (a) a config per-glob runner template, e.g. `commands.<repo>.testRunners: [{glob, command "… {file}"}]`, files from the plan task's `(files)` (not enforced by plan-coverage today, D-17 of #1039); (b) the whole configured `test` command red at red / green at head (names no test); (c) a build-written command on the plan line (build-controlled) |
    | D-3 | Assertion vs setup failure across runners (AC-6) | open: no runner-agnostic signal; second-shift's own bash selftests have none; jest prints "Test suite failed to run". Options: optional config pattern per runner, else note "not distinguished"; or drop the distinction (amends AC-6) |
    | D-4 | What a failing proof does in the run | open: red_attempt (fixable only if D-1 lets a later build re-prove) vs terminal for a human; coupled to D-1 |
    | D-5 | AC that keeps existing behavior (comment 1) | candidate: new Test intent line form, e.g. `AC-n: holds — <behavior>`, held to green at red and green at head; lint + plan-coverage learn it |
    | D-6 | AC whose tagged test sits on a tier the scheduler cannot run (comment 2) | candidate: reported "not checkable at the red commit" naming the file/tier, not red, not exempt; falls out of D-2(a) when no runner glob matches |
    | D-7 | Where the red run happens | candidate: in $WT, detached checkout of the red commit after sync_to_remote, trap-restored to HEAD (keeps ignored deps like node_modules; no reinstall); vs a separate worktree + setup lanes |
    | D-8 | The --handoff path | open: lane-only (handoff review notes the proof unrun) vs review skill runs it (session-run, D-10-of-#1039 ceiling) |
    | D-9 | Plan position gating (#1039 D-6 handed "gating the order" to #1040) | open: gate plan-commit-first or keep it a note |
    | D-10 | Not-applicable cases | candidate: record without Test intent / ACs none / no runner configured → not-applicable named, run continues (mirrors #1039 D-3) |
    | D-11 | Later review rounds that add or rewrite tagged tests | open, coupled to D-1: (a) each new red needs its own trailer commit; (c) automatic |
    | D-12 | AC-8 selftest home | run-record-selftest.sh or a new run*-selftest case, per CLAUDE.md |

## Knowledge source

Knowledge source: none declared

## Test intent

ACs: AC-6 AC-7 AC-8
AC-6: a run*-selftest case where a tagged test file passes on the record commit's tree with the head's tagged files applied makes the run red, its log naming the AC and the file
AC-7: a run*-selftest case where every tagged file not marked holds fails on that tree and the checks pass at head lets the run go on to review
AC-8: the run*-selftest cases tagged for AC-6 and AC-7 fail with the check removed from run.sh
