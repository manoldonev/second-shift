# Intake receipt — #1053 dev-pipeline: the fails-without-the-change check judges each named test, running a runner's files in one batch

Receipt: v4

## Intake steps

Requirements: the ticket body as written — spec-reviewer: needs-spec-work (3 blockers, 11 warnings); the operator chose to interview them here, and the body was rewritten from the ledger
Split: the operator moved the independent hardening items to sibling #1056 (D-1) and committing this repo's config to #1059 (D-14); the judge work stays one ticket — one coherent change to one leg; codebase-explorer not dispatched, as no decomposition of the judge was analysed
Explore: done — run.sh's fails-without-the-change leg and its map read, plan-coverage.sh's files parser, config-lint's testRunners rules, run-selftest-lib.sh and the run selftest suites, the #1040 record, two consumer checkouts' runner configs and lockfiles; jest 28.1.3 measured in scratch
Fan-out: ran — 22 items, see Fan-out
Dup-scan: no candidates at or above threshold 12 (corpus: 0 scanned)
Post-merge scan: no post-merge AC
Sizing: opus

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Whether the hardening items stay in this ticket | Moved to sibling #1056: bounding the configured checks, a total cap for the leg, `CI=1` on the leg, literal pathspecs, `bounded()`'s poll. They ship on their own; the operator wants as few tickets as sensible, and two is that number | user-answered | intent |
| D-2 | Judge structure and order | Run-level first: a timeout, a missing or unreadable report, or failed rows with exit 0 is ONE red naming the runner. Then per named test: a form its runner cannot judge is red; more than one matching row is red "ambiguous"; one row: failed ok, passed red, skipped/pending/todo red; no row: absent from the report red "not collected", the file reported rows red "did not run", no rows and a load message pending | user-answered | intent |
| D-3 | A vitest `beforeAll` failure (rows skipped) | Pending, like jest (which reports those rows failed): when the file failed with no failed rows and an empty message, its skipped rows go to the head leg and count only if they pass there. Same outcome on both runners, consistent with #1040 D-2 | user-answered | intent |
| D-4 | What a bash test case is and how it reports | A new `cases` format: the test prints one machine line per case at exit, `case<TAB><passed\|failed><TAB><id>`; run-selftest-lib.sh emits them, the harness owns the format, no user regexes. Chosen over scraping the human ok/FAIL lines after the operator's challenge: the test author owns the case boundary | user-answered | intent |
| D-5 | Runner config grammar and lint | Per runner `format`: exit (default), cases, vitest-json, jest-json. exit and cases run per file with `{file}` (cases may take `{cases}`); the json formats batch with `{files}` and `{report}` and refuse `{file}`. `testSupport: [globs]` at commands.<id>. config-lint is strict: each placeholder only where its format takes it; vitest-json requires `--reporter=json`, `--outputFile={report}`, `--bail=0`, jest-json `--json`, `--outputFile={report}`, `--runTestsByPath`, `--bail=0`, each in `--flag=value` form; a space form, a second `--reporter` or any `--outputFile.<x>` is refused | user-answered | intent |
| D-6 | Plan grammar for a named test | `file::case`, the case backtick-quoted when it holds a space, `>`, `(`, `)`, `,` or `[`; backtick spans lexed across the whole task line before the comma/space split; a backtick inside a case is unsupported; an unterminated backtick or a bare case that needs quoting is a red "unparseable" naming the task. `--files` emits `kind`, `AC-n`, `file`, `case` tab-separated and run.sh reads it split on tabs. Supersedes #1040 D-21 | user-answered | intent |
| D-7 | How a named case matches a report row | The case split on ` > ` must equal ancestorTitles + title exactly, case-sensitive; for `cases` it equals the block id. An `it.each` title is matched as the runner renders it at the head; identical renders are ambiguous | user-answered | intent |
| D-8 | The `exit` format and mismatched forms | `exit` stays the default, file unit, exit code; its hole is documented (a file the runner never collects exits non-zero and counts as failing). A bare file under a cases/json runner, or `file::case` under exit, is red on the checks-red counter | user-answered | intent |
| D-9 | Head leg and interrupted runs | After the restore, at the head: one call per json runner, one per file for cases, over every pending test and every selected `{cases}` test; each must report passed, anything else is red; a pending test that passes is labeled "file-level" in the run block. An interrupted run re-runs both legs on `--resume`; the red-tree mark is unchanged; where report copies live is OR-2 | user-answered | intent |
| D-10 | Report forgery (#1040 D-2's F-16 objection to parsing runner output) | No weaker than the exit code it replaces: a test can print a fake line or rewrite the report as it can `exit 1` today. `{report}` is deleted before each call and copied to the run's state right after; deliberate forgery is the review's job. Supersedes D-2's F-16 objection with that reason | user-answered | intent |
| D-11 | What `timeoutSeconds` bounds | One runner call: a batch for a json runner, one file for exit and cases; a timeout reds every test in that call, naming the runner. The total cap across calls is #1056's | user-answered | intent |
| D-12 | The acceptance criteria | Nine: AC-1..AC-4 as filed (AC-3 widened to the vitest hook case and a head-leg red, AC-4 to jest), AC-6..AC-11 added; AC-5 retired — the run.sh-selftest rule binds every PR through CLAUDE.md, and as an AC it invites a conjured tag | user-answered | intent |
| D-13 | Case selection for this repo's bash suites | In scope: `{cases}` for cases runners; the lib skips unselected blocks; the head leg always re-runs selected blocks. Grounded on the operator's execution-time goal: about 157s whole on the old code vs about 28s selected plus 32s at the head | user-answered | intent |
| D-14 | This repo's own runner config | Stays a hand edit after release (run* suites to `cases` with `{cases}` and `testSupport: [run-selftest-lib.sh]`, the rest `exit`); committing the config is #1059 | user-answered | intent |
| D-15 | The bash case unit, after the probe | The fixture block: everything after `fixture <name>` up to the next fixture, its id the fixture name; rows fold per block; an unselected block's run_case returns at once and its ok/bad are muted; rows before the first fixture are not addressable. A tag cannot drive selection — run: `grep -c run_case run-record-selftest.sh` → 54 against 34 fixture calls, and fw4 reuses fw3's fixture | user-answered | intent |
| D-16 | A `cases` file that prints no case lines | Red, naming testSupport: treating it as pending would let the old lib's plain non-zero exit become a file-level pass for every case. For a `cases` runner its case lines are its report, so the run-level step covers only its timeout and this red is the one it gets | user-answered | intent |
| D-17 | jest 28 vs 29 report shape | The same: one jest-json parser covers both — measured in scratch on jest 28.1.3 — run: `npx jest --ci --json --outputFile=r.json --runTestsByPath a.test.js c.test.js` → rows carry ancestorTitles and title; skip is pending, todo is todo, a beforeAll throw is failed; a load failure is status failed, no rows, a message | codebase-derived | fact |
| D-18 | Consumer runner versions | over the consumer checkouts — run: `grep -A1 -E '^"?(vitest\|jest)@' <consumer>/yarn.lock` → vitest 4.1.10 and 2.1.9, jest 29.7.0 and 28.1.3 (so `vitest list`, 2.1+, is available everywhere) | codebase-derived | fact |
| D-19 | What the bash selftests print today | run: `sed -n '16,17p' plugins/dev-pipeline/skills/run/run-selftest-lib.sh` → `ok()  { PASS=$((PASS+1)); echo "  ok   $*"; }` and `bad() { FAIL=$((FAIL+1)); echo "  FAIL $*"; }` | codebase-derived | fact |
| D-20 | Today's plan parser and parentheses | run: `grep -n "FILES_RE=" plugins/dev-pipeline/tools/plan-coverage.sh` → 96: `FILES_RE='\(([^()]*)\)$'`, so a case holding `(409)` leaves the task with no files | codebase-derived | fact |
| D-21 | How `testSupport` globs match | As `when` globs do — cited (convention): plugins/dev-pipeline/skills/run/run.sh:603 ("$g IS a glob, by contract (extraLanes' `when`)") | codebase-derived | fact |
| D-22 | The lib's shell | bash 3.2 compatible, so no associative arrays — run: `/bin/bash --version` → GNU bash, version 3.2.57(1)-release | codebase-derived | fact |
| D-23 | This repo's config is not committed | run: `git check-ignore .claude/second-shift.config.json` → .claude/second-shift.config.json | codebase-derived | fact |
| D-24 | A vitest/jest file listed with zero rows and no load message | Red "did not run": only a file that failed with a load message goes to the head leg; an empty or fully filtered file never proves anything | user-answered | intent |
| D-25 | A selected fixture block with no ok/bad row (the suite died first) | It prints no case line, so the judge reds it "did not run" on either leg; a crash never folds to passed | user-answered | intent |
| D-26 | How `testSupport` is validated | A non-empty array of non-empty strings, as `when` is — cited (convention): plugins/dev-pipeline/tools/config-lint.sh:214 | codebase-derived | fact |
| D-27 | Case ids for fixtures named at runtime | The expanded name, one block per value — run: `grep -n 'fixture "fe-$v"' plugins/dev-pipeline/skills/run/run-claim-selftest.sh` → 236: fixture "fe-$v" | codebase-derived | fact |
| D-28 | Which selected `{cases}` tests the head leg re-runs | Only the selected tests that failed on the record commit's tree; a test already red there is not run again at the head. Added in build: D-9 says every selected test, but a second run cannot clear a red, so it only adds time | user-delegated | intent |
| D-29 | Which task lines the unterminated-backtick red applies to | Only a task that carries an AC id; an untagged task's description is not read for files, so a stray backtick there stays legal. Added in build: D-6 names the task without saying which tasks, and an implementation task never feeds the check | user-delegated | intent |
| D-30 | Where a bare case ends | At the next comma or the end of the list, so a bare case holding a space is red unparseable; a space still separates bare files, and a quoted case from the next name. Added in build: D-6 splits on spaces and also reds a bare case that needs quoting, and a space can only be caught if a bare case runs to the comma; the review found `file::Importer > dup` split into a case and two stray files | user-delegated | intent |

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | The suites' direct `bash "$RUN"` calls that bypass `run_case` | reversible-default-and-flag |
| OR-2 | Where the report copies live across a `--resume` | reversible-default-and-flag |
| OR-3 | A `testSupport` file the head deleted since the record commit | reversible-default-and-flag |

OR-1 default: they still run in an unselected block, so selection saves only the `run_case` launches; moving them behind `run_case` is a later, mechanical change the build may flag in the PR body. Reversing is cheap: it changes test code, not the contract.

OR-2 default: per run and attempt, in that run's state directory (a resume is a new run, so it writes a new directory and the old copies stay). Reversing is one path change.

OR-3 default: only matching files that exist at the head are applied; a deleted one is left as the record commit has it, so the tree builds rather than ending env-worktree. Reversing is one branch in the checkout step.

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | The run log's red and pending lines, per runner call and per named test | decided (D-2) |
| S-2 | The run block in the PR body: the summary and the "file-level" label | decided (D-9) |
| S-3 | The build prompt's fails-without-the-change paragraph and plan instruction | decided (D-6) |
| S-4 | `docs/config-schema.md` and the JSON schema for the new keys and formats | decided (D-5) |
| S-5 | config-lint's refusal messages | decided (D-5) |
| S-6 | build/SKILL.md and interviewing-baseline's Test intent paragraph | decided (D-6) |
| S-7 | A bash suite's own output under `{cases}` (muted rows, the case lines) | decided (D-15) |

## Checks

- `env -u CLAUDE_CODE_SESSION_ID SKIP_STRESS=1 bash plugins/dev-pipeline/skills/run/run-record-selftest.sh`

## Fan-out

Refuter: cross (opus/fable alternating)
Lenses: consumer-report-reality opus 6/6 · test-id-grammar fable 4/6 · existing-contract-and-migration opus 6/6 · build-controlled-inputs fable 4/6 · premortem fable 2/6
Tally: rows added 3 · snapshot claims overturned 0 · questions added 4

| ID | Angle | Claim | Tag | Disposition |
| --- | --- | --- | --- | --- |
| F-1 | consumer-report-reality | vitest 4.1.10's JSON matches the judge's main rows; the file key is an absolute realpath; a symlinked filter path collects nothing | new | became D-7 |
| F-2 | consumer-report-reality | A vitest beforeAll failure leaves the file failed with an empty message and no failed rows, unlike skipIf | new | became D-3 |
| F-3 | consumer-report-reality | jest reports a beforeAll throw as failed rows, so the same hook failure proves under jest and is red under vitest | new | became D-3 |
| F-4 | consumer-report-reality | jest's positional file arguments are regexes; `--runTestsByPath` collects literal paths; not-collected rests on absence from the report | new | became D-5 |
| F-5 | consumer-report-reality | The consumers' configs leave the report path alone; one backend's rootDir leaves its API specs uncollected by root jest | new | became D-2 |
| F-6 | consumer-report-reality | fullName is space-joined in both runners; the id must be rebuilt from ancestorTitles + title | already-had | became D-7 |
| F-7 | test-id-grammar | Today's parser rejects any parenthesis in the files list, and a bracketed AC id inside a case breaks the line | already-had | became D-6 |
| F-8 | test-id-grammar | Backtick quoting is invisible to today's splitter; a quoted case with spaces becomes several files | already-had | became D-6 |
| F-9 | test-id-grammar | An it.each title renders differently across vitest 2, vitest 4 and jest | new | became D-7 |
| F-10 | test-id-grammar | The judge table's rows conflict when two rows match one name | already-had | became D-2 |
| F-11 | existing-contract-and-migration | The proposed grammar does not parse today; pc12 and pc13 pin the --files strings | already-had | became D-6 |
| F-12 | existing-contract-and-migration | run.sh reads the map with default IFS, so a fourth column lands in the file path and every test reds as missing | new | became D-6 |
| F-13 | existing-contract-and-migration | config-lint and the schema refuse format, testSupport and a command without `{file}` | already-had | became D-5 |
| F-14 | existing-contract-and-migration | No consumer configures testRunners; the one consumer read resolves jest 29.7.0 | not material | not material — opting in is each consumer's; another consumer resolves jest 28.1.3, measured the same (D-17) |
| F-15 | existing-contract-and-migration | The fw cases pin per-file strings that change with the judge | not material | not material — rewording them follows from D-2 to D-9 |
| F-16 | existing-contract-and-migration | The red-tree mark records no leg state, so an interrupted head leg has no resume rule; four texts state the per-file contract | new | became D-9 |
| F-17 | build-controlled-inputs | The ticket's own example line is red or mangled by today's parser | already-had | became D-6 |
| F-18 | build-controlled-inputs | Under exit, a tagged file the runner never collects exits non-zero and counts as failing | new | became D-8 |
| F-19 | build-controlled-inputs | vitest honors space-form flags and a redirected outputFile; a jest config bail cuts suites and writes no report | new | became D-5 |
| F-20 | build-controlled-inputs | Titles may contain ` > `, and runners disagree on a beforeAll failure | already-had | became D-7 |
| F-21 | premortem | Parenthesized titles are common in a consumer (43 of 700), so the grammar must carry them | new | became D-6 |
| F-22 | premortem | No consumer exercises the judge until its operator writes runner entries; one backend has a second suite a single glob would misroute | not material | not material — a misrouted file is red "not collected" (D-2) |

### Snapshot

    | ID | Decision | Resolution |
    | --- | --- | --- |
    | D-1 | Judge structure and order (spec-review blocker 1) | open: split invocation-level outcomes (timeout, report missing/unparseable, report-vs-exit disagreement) from case-level; per case, ambiguity (more than one matching row in the file) checked first, then the single row's status |
    | D-2 | What one `lines` case is (blocker 2) | open: patterns capture the tag only; several rows per tag fold (any FAIL row -> fails; all ok -> passes); verified: run-selftest-lib.sh:16-17 prints `  ok   $*` / `  FAIL $*`, expect() at :230 adds a row, `(fw1)` appears on 3 ok/expect rows |
    | D-3 | Config grammar (blocker 3) | open: per-runner `format` (exit default, vitest-json, jest-json, lines), `pass`/`fail` keys for lines, placeholders per format ({file} for exit and lines, {files}+{report} for the json formats); `testSupport` at commands.<id> level; config-lint learns all of it and still rejects unknown keys |
    | D-4 | Plan grammar for file::case (W1) | open: backtick spans lexed before the comma/space split; quoting required for space, `>`, `(`, `)`, `,`; supersedes 1040 D-21; verified FILES_RE='\(([^()]*)\)$' at plan-coverage.sh:96 forbids parentheses |
    | D-5 | Which formats batch (W2) | open: json formats batch all of a runner's files in one invocation; exit and lines run per file |
    | D-6 | timeoutSeconds when batched (W4) | open: bounds one invocation |
    | D-7 | Bare file vs file::case per format (W2) | open: checked in run.sh (plan-coverage reads no config); a bare file under a formatted runner is a red on the checks-red counter; file::case under an exit runner is red |
    | D-8 | Case name to report row (W3) | open: ancestorTitles + title joined with " > ", exact and case-sensitive, for both jest-json and vitest-json |
    | D-9 | Head leg outcomes (W3) | open: any status but passed, a missing row, or a timeout is red |
    | D-10 | Invocation-level report failure (W3) | open: one red naming the runner and why, not one "not collected" per case |
    | D-11 | Which 1040 rows this supersedes (W7) | open: D-2 (for formatted runners), D-3 (the case is the unit for formatted runners), D-21; F-16 forgery stance |
    | D-12 | This repo's own runners (W6) | open: the operator edits the gitignored config by hand; the .mjs runner stays exit |
    | D-13 | Statuses disabled/focused/todo | open: count as skipped -> red |
    | D-14 | Consumer runner versions | fact: lockfiles resolve vitest 4.1.10 and 2.1.9, jest 29.7.0 and 28.1.3 |
    | D-15 | Report forgery | open: review's job, or hash the report right after the leg |
    | D-16 | AC set (W8) | open: add ACs for lines folding, jest-json, the bare-file rule, ambiguous ids, head-leg failure, testSupport |

## Knowledge source

Knowledge source: none declared

## Test intent

ACs: AC-1 AC-2 AC-3 AC-4 AC-6 AC-7 AC-8 AC-9 AC-10 AC-11

AC-1: a tagged file whose named test passes on the record commit's tree is red naming the AC and the test, though another test in the file fails there
AC-2: a named test missing from a file that reported tests, skipped there, or named in a form its runner cannot judge is red
AC-3: a named test in a file that does not load on the record commit's tree, or behind a failing vitest beforeAll, passes labeled file-level when it passes at the head, and is red when it does not
AC-4: three tagged vitest files, and three tagged jest files, run in one call on the record-tree leg and one call on a head leg
AC-6: two report rows matching one named test make the check red "ambiguous"
AC-7: a runner call that times out, leaves no readable report, or reports failed rows with exit 0 is one red naming the runner
AC-8: plan-coverage.sh --files emits a backtick-quoted file::case holding spaces, parentheses or > as one tab-separated row, and an unterminated backtick as a red unparseable line
AC-9: a run*-selftest.sh under a cases runner is judged per fixture block, with testSupport bringing the head's run-selftest-lib.sh, and is red naming testSupport when it prints no case lines
AC-10: config-lint refuses a reporting runner missing its placeholders or required flags, a placeholder its format does not take, a space-form flag, and an unknown format
AC-11: with {cases}, only the selected fixture blocks launch run.sh on the record commit's tree, unselected blocks print and count nothing, and each selected block must pass at the head
