# Intake receipt — #1039 dev-pipeline: the harness checks a test-first plan covers every acceptance criterion

Receipt: v3

## Intake steps

Requirements: the ticket body as written — a slice of #1018 filed by the parent's split with its ACs and its own open questions; plan-interview pre-flight, no requirements interview
Split: not split — already a slice of #1018 (layers 1+2); its successor #1040 (layer 3) is blocked on it
Explore: done — run.sh (record commit, run_checks, red_attempt, --handoff exit, $TOOLS, spawn add-dirs), ledger-lint.sh receipt versions and mandated(), intake receipt.md, build and review skills, post-review-status.sh, scope-completeness AC id rule
Fan-out: ran — 26 items survived refutation, see Fan-out
Dup-scan: no candidates at or above threshold 12 (corpus: 2 scanned)
Post-merge scan: no post-merge AC — every AC is observable through a selftest in the diff
Sizing: opus

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Where the AC-n set the lint and the coverage check hold things to comes from | The receipt's new `## Test intent` section opens with one `ACs: AC-1 AC-2 …` line the Receipt stage transcribes from the ticket (or `ACs: none — <reason>` when the ticket has no AC block), then one line per id: `AC-n: <the observable behavior its test must prove>` or `AC-n: exempt — <reason>`. `ledger-lint.sh --receipt` fails naming every id in `ACs:` with no line and every line whose id is not in `ACs:`. The coverage check reads the AC set and the exemptions from the record at the first commit. The harness never reads the ticket body. Accepted residual: an id dropped while transcribing the `ACs:` line is invisible to the offline lint. Weighed: this ids line; the ticket's AC block embedded verbatim and parsed; a live ticket-body read by run.sh | user-answered | intent |
| D-2 | How the section is mandated from v4 | A `\| Test intent \| v4 \|` row in both lockstep copies of the receipt-version table, plus a check block that calls `mandated 'Test intent'` (the row alone enforces nothing); v1–v3 receipts keep linting clean; the selftest's current-version fixture moves to v4 and gains the section — run: `bash plugins/intake-toolkit/skills/plan-interview/tools/ledger-lint.sh --receipt-version` → 3; run: `grep -c "mandated '" plugins/intake-toolkit/skills/plan-interview/tools/ledger-lint.sh` → 6 | codebase-derived | fact |
| D-3 | A record without a Test intent section (v1–v3), or `ACs: none` | The coverage check reports not-applicable, naming why (`record v<N> carries no Test intent`, or `the ticket has no AC block`), distinct from a pass; the run continues; the build prompt asks for a plan only when the record at the first commit carries `## Test intent` | user-answered | intent |
| D-4 | Plan path and line grammar | Path `<paths.plansDir>/<slug>-<issue>-plan.md`, beside the record (here `docs/plans/second-shift-1039-plan.md`). Groups `## N. Group`. A task is `- [ ] N.M Description (files) [AC-1] [AC-3]`: `[x]` allowed and meaningless, one bracket per id, ids end the line, no comma lists. Any line starting `- [` that does not match is reported unparseable by line number, never skipped. Weighed: strict; strict plus a `test:` marker; lenient any-bracket ids | user-answered | intent |
| D-5 | What makes a task a test task, and whether test-before-implementation order is checked | A task carrying `[AC-n]` is a test task. Line order is not checked: the plan is a coverage map, and #1040's red-before-green proof is what shows the order in git. Weighed: tags-only; a `test:` marker; a filename classifier (`*-selftest.*`), rejected because consumer test naming varies | user-answered | intent |
| D-6 | Which copy of the plan the check reads | The plan at the pushed head (`git show <head sha>:<plan path>`), so a red is fixable by a new commit. Whether the first commit after the record added the plan is printed in the run log and the PR's run block, never gating; gating the order is #1040's. Weighed: head with position noted; head with a position terminal; the plan commit only | user-answered | intent |
| D-7 | What a red coverage check does in the run | Uncovered id, undefined tag, missing or unparseable plan → `red_attempt`: the log names each failing id or line and goes to a re-spawned build on the shared checks-red counter (the third red ends `checks-red-spent`). Not-applicable is a log line plus a run-block note, and the run continues. Weighed: red_attempt; a dedicated `plan-coverage-red` terminal | user-answered | intent |
| D-8 | An exempt AC in the coverage check | Not required to be tagged and reported `exempt`; one the plan tags anyway is allowed and reported `exempt (tagged)`; neither is reported `covered`, and neither is red | user-answered | intent |
| D-9 | Where the check lives and how the lane runs it | `plugins/dev-pipeline/tools/plan-coverage.sh <record-at-first> <plan-file>`, file-in and pure: exit 0 pass, 1 red (names every uncovered id, undefined tag and unparseable line), 2 unreadable input, 3 not-applicable; its own `plan-coverage-selftest.sh`. run.sh calls it from `$TOOLS` (the installed plugin, outside every dir the build is granted) in the NEED_CHECKS block after `run_checks`, on git objects (the record at the first commit, the plan at the pushed head), and decides the result from its exit code. It is not a configured lane, and reads nothing from `$STATE` or the config, both of which the build can write | user-answered | intent |
| D-10 | The check on the `--handoff` path (AC-5) | The review skill runs the script before deciding, and a red is a `[blocker]`. `post-review-status.sh` runs it again and refuses to post an approving `success` while it is red (exit 1, nothing posted, as for a body that breaks a rule); a needs-work verdict posts `failure` as before. The build skill's "nothing between the handoff and the PR is checked by the scheduler" rule names it. Stated ceiling: on this path a session invokes the script, not the scheduler, so it binds a merge only where branch protection requires `second-shift/review` (the same ceiling #991 accepted for verdict bodies). Weighed: tool plus review status gate; lane-only with AC-5 unmet on handoff; inline in run.sh; posting `failure` on a red approve | user-answered | intent |
| D-11 | Who writes the test intent | The Receipt stage drafts each AC's behavior from the AC text. Every exemption is put to the operator as a question and recorded as a `user-answered` ledger row; an AC is never exempted silently | user-answered | intent |
| D-12 | How the build treats the test intent | An instruction in the build prompt: each AC's tagged test proves the stated behavior. The review gains no new scoring rule; test strength stays out of scope | user-answered | intent |
| D-13 | How AC ids are compared | Exact string `AC-<n>` as labeled, never inferred from contiguity (this ticket defines AC-1..5 and AC-8; post-merge moves leave holes); `PM-n` never enters the set, which comes from the `ACs:` line only — run: `gh issue view 1039 --json body --jq .body \| awk '/^## Acceptance Criteria/{on=1;next} on&&/^#/{exit} on' \| grep -oE '^AC-[0-9]+'` → AC-1 AC-2 AC-3 AC-4 AC-5 AC-8 | codebase-derived | fact |
| D-14 | Where the run.sh selftest case lands (AC-8) | A case in a `run*-selftest.sh` suite that fails without the change; record and receipt cases live in `run-record-selftest.sh` — cited (convention): CLAUDE.md:120 | codebase-derived | fact |
| D-15 | CR line endings in the plan and the section | Strip a trailing CR before matching, as the repo's other line parsers do — run: `grep -nF 'line%' plugins/intake-toolkit/skills/plan-interview/tools/ledger-lint.sh` → 752 794 (each `line="${line%$'\r'}"`) | codebase-derived | fact |
| D-16 | What the lane does when plan-coverage.sh exits 2 (the record at the first commit carries a Test intent with no readable `ACs:` line, or an input cannot be read) | A new terminal `plan-coverage-uncheckable`, exit 1 (stopped for a human), beside `verdict-uncheckable`; any exit other than 0, 1 and 3 takes it too. Reason (added during BUILD): no build can change the record at its first commit, so a red_attempt would only spend the checks-red counter on something the build cannot fix, and a check that cannot run is not one that passed | user-delegated | intent |
| D-17 | The task-line details D-4 leaves open | A task is `- [ ] N.M <description>` with `[ ]`, `[x]` or `[X]`; the `(files)` parenthetical is written by the build prompt but not enforced; the description must be non-empty; a bracketed `[AC-n]` anywhere but the trailing run of ids (a comma list, a tag before the description, lower-case `[ac-n]`) makes the line unparseable; a bracket that is not `[AC-n]` (e.g. `[PM-1]`) is description text, neither covered nor undefined. The run log and block name the missing plan as `<head sha>:<plan path>`. Reason (added during BUILD): strict on the ids, which decide coverage, lenient on prose, which decides nothing | user-delegated | intent |
| D-18 | Which plan file `post-review-status.sh` reads on the handoff path | The file beside `<record-at-head>`, `<x>-decisions.md` → `<x>-plan.md` (the checked-out head's), so its six-argument usage is unchanged; the review skill passes the record in the worktree already. Reason (added during BUILD): D-4 places the plan beside the record, and a new argument would break every existing caller | user-delegated | intent |
| D-19 | How strict the lint is inside `## Test intent` beyond D-1 | Besides D-1's two named violations, the lint refuses: an `AC-n:` line before the `ACs:` line, a second `ACs:` line, a second line for one id, a token on `ACs:` that is not `AC-<n>` (so a `PM-n` or a comma list), an empty behavior, an exemption with no reason, a bare `ACs: none`, and any other non-blank line (prose, a bulleted or indented AC line). Reason (added during BUILD): the section is read by a script, and a near-miss line silently skipped is the failure D-4 refuses for the plan | user-delegated | intent |

## Open Regions

No open regions — every decision in scope is ratified.

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | The receipt's `## Test intent` section an operator reads and writes | decided (D-1) |
| S-2 | Lint violations for a missing intent, an id outside `ACs:`, and a missing section on a v4 receipt | decided (D-2) |
| S-3 | The exemption question intake puts to the operator | decided (D-11) |
| S-4 | The plan file the build commits | decided (D-4) |
| S-5 | The build prompt's plan and test-intent instructions | decided (D-12) |
| S-6 | The coverage log a re-spawned build reads on red, naming ids and lines | decided (D-7) |
| S-7 | The not-applicable line and run-block note | decided (D-3) |
| S-8 | Exempt and exempt (tagged) reporting | decided (D-8) |
| S-9 | The plan-position note in the run log and run block | decided (D-6) |
| S-10 | The handoff review's blocker and the refused `second-shift/review` status | decided (D-10) |
| S-11 | The checks-red-spent terminal detail after a third coverage red | decided (D-7) |
| S-12 | Order proof at the red commit | out-of-scope — #1040 owns red-before-green |

## Checks

No ticket-specific checks — the configured lanes cover this change.

## Fan-out

Refuter: cross (opus/fable alternating)
Lenses: ac-set-provenance opus 5/6 · receipt-version-migration fable 4/6 · harness-trust-boundary opus 6/6 · plan-grammar-adversary fable 5/6 · premortem fable 6/6
Tally: rows added 1 · snapshot claims overturned 0 · questions added 0

| ID | Angle | Claim | Tag | Disposition |
| --- | --- | --- | --- | --- |
| F-1 | ac-set-provenance | run.sh never reads the ticket body; under jira it makes no tracker read (`run.sh:372-373`) | already-had | became D-1 |
| F-2 | ac-set-provenance | The record holds no AC set and the lint is network-free, so an AC dropped from the receipt is invisible to it | new | became D-1 (the residual it states) |
| F-3 | ac-set-provenance | AC numbering gaps are normal: slices keep parent ids, post-merge moves leave holes | already-had | became D-13 |
| F-4 | ac-set-provenance | Bodies use two AC line forms and four heading spellings; a second extractor would disagree with the scope reviewer | new | became D-1 (ids transcribed at intake; no AC parser in the harness) |
| F-5 | ac-set-provenance | Section scoping excludes prose-quoted ids and PM-n | already-had | became D-13 |
| F-6 | receipt-version-migration | A version-table row alone enforces nothing; a `mandated` check block is needed | new | became D-2 |
| F-7 | receipt-version-migration | With the check block, v1–v3 receipts stay green and a bare v4 is refused by section name | new | became D-2 |
| F-8 | receipt-version-migration | The current-version selftest fixture must gain the section or ll-rv reds | new | became D-2 |
| F-9 | receipt-version-migration | The lint's only input is the receipt path; the id set must be written into the receipt | already-had | became D-1 |
| F-10 | harness-trust-boundary | The check belongs in the NEED_CHECKS block; the record at FIRST is content-addressed, while a bot-enabled build can edit the issue | new | became D-9 |
| F-11 | harness-trust-boundary | The build can write `$STATE` and the config run_checks re-reads (`run.sh:353-354`) | new | became D-9 (the check reads neither); the pre-existing gap itself is outside this ticket |
| F-12 | harness-trust-boundary | Nothing checks the head descends from FIRST, so a walk of commits after FIRST can read rewritten history | new | became D-6 (position noted, never gating) |
| F-13 | harness-trust-boundary | red_attempt shares one run-wide counter and costs a paid spawn; a --resume starts with no red log | new | became D-7 |
| F-14 | premortem | A check bound to the plan commit cannot be fixed without rewriting history, burning the counter | new | became D-6 |
| F-15 | harness-trust-boundary | On --handoff no scheduler runs after the build; post-review-status.sh is the one script gate | already-had | became D-10 |
| F-16 | plan-grammar-adversary | An `[AC-n]\r` line end matches under ugrep but not awk or BSD grep; the repo's parsers strip CR | new | became D-15 |
| F-17 | plan-grammar-adversary | Extractor strictness changes coverage on comma lists, ticked, indented and in-description ids | new | became D-4 |
| F-18 | plan-grammar-adversary | No AC parser exists in the repo's shell or mjs | already-had | became D-1 |
| F-19 | plan-grammar-adversary | Test-first order is checkable only with a test-task classifier, e.g. the `*-selftest` filename | new | became D-5 (weighed, not adopted) |
| F-20 | plan-grammar-adversary | The receipt-lint cases build from the v3 fixture; the lane check's selftest slice is run-record-selftest.sh | new | became D-2 and D-14 |
| F-21 | premortem | AC-1 cannot be met by the lint as it stands: no source for the ticket's AC set | already-had | became D-1 |
| F-22 | premortem | A check that infers AC-1..max false-reds this ticket (no AC-6, AC-7) | already-had | became D-13 |
| F-23 | premortem | On --handoff the coverage check never runs | already-had | became D-10 |
| F-24 | premortem | run.sh lints with the enabled intake-toolkit, which on this machine predates `--receipt-version` | not material | not material — install state on one machine, not a design decision of this ticket |
| F-25 | premortem | A tag-coverage check passes a build that commits code first or tags every id on one task | new | became D-5 and D-6 (accepted; #1040 proves order) |
| F-26 | premortem | The record and the live ticket can define different AC sets; a mid-run amendment reds a committed plan | already-had | became D-1 |

### Snapshot

    | ID | Decision | Resolution |
    | --- | --- | --- |
    | D-1 | AC set source for the lint and the coverage check | candidate: the receipt carries the ticket's AC block verbatim (indented) beside a per-AC test-intent table; lint checks the table covers every AC id in the block; coverage reads the record at FIRST. run.sh never reads the ticket body (no `--json body` read; jira has no shell read path). Alternative: live ticket body |
    | D-2 | Receipt section name and row form | candidate: `## Test intent`, `\| AC-n \| <behavior its test proves> \|` or `\| AC-n \| exempt — <reason> \|`, mandated from v4 (lockstep table in lint + interviewing-baseline) |
    | D-3 | Plan path and line grammar | candidate: `$PLANS_DIR/$REPO_SLUG-$ISSUE-plan.md` beside the record; `## N. Group`, `- [ ] N.M Description (files) [AC-1, AC-3]`; a task carrying `[AC-n]` is a test task |
    | D-4 | Which commit the coverage check reads the plan at; is plan position (FIRST's child) enforced | open: head (fixable by a new commit) vs FIRST's child (unfixable without history rewrite) |
    | D-5 | Failing / missing / unparseable plan in the run | candidate: red_attempt (checks-red counter, log to next build), like checks/smoke/conventions (run.sh:1150) |
    | D-6 | Exempt AC in the coverage check | candidate: not required, reported `exempt`, distinct from covered |
    | D-7 | Coverage check on the --handoff path (AC-5) | candidate: standalone tool script; /dev-pipeline:review runs it and post-review-status.sh refuses a `success` status when it fails |
    | D-8 | Record below v4 (no test-intent section) | candidate: coverage reported not-applicable (older record), build not asked for a plan |
    | D-9 | Where the check lives | candidate: plugins/dev-pipeline/tools/plan-coverage.sh + selftest, called by run.sh |
    | D-10 | PM-n | excluded by construction: AC set comes from the AC block only |
    | D-11 | Non-contiguous AC ids (this ticket: AC-1..5, AC-8) | parser takes explicit labels, never assumes 1..n |
    | D-12 | Checks | configured `test` lane runs every selftest by glob — empty form |

## Knowledge source

Knowledge source: none declared
