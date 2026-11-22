# Decision record — #1369 Intake exploration finds few of the code facts that change a ticket, and no eval measures it

Receipt: v5

## Summary

The ticket adds `discovery-recall-eval`, an operator-run eval case under `plugins/intake-toolkit/evals/`. It runs `plan-interview` on the #908 fixture ticket against snapshot 3f3e9af5 and grades one `fact-` grader per answer-key fact. Recall is the share of `fact-` graders passed per run, read with a `jq` line. The case also grades false premises, reads outside the snapshot, the scheduler read and the absence of a plan.

Open regions: OR-1, the answer key falls short of eight facts or one premise. The build stops and asks.

Provenance legend: `user-answered` = the operator chose. `codebase-derived` = a fact from the code or the docs, with its proof.

Open region legend: `pause-and-ask` = the build stops and asks.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Which facts may enter the answer key | A fact qualifies when a line at 3f3e9af5 anchors it. A fact whose force comes from documented claude behavior qualifies when its criteria state that behavior. A fact with no line in the snapshot is excluded: a measurement, a `.claude/` file, `plugins/intake-toolkit/`, or git history alone. The build reads the code only to place a line, never to add a fact. | user-answered | intent |
| D-2 | What counts as a false premise | A literal statement of the ticket, or a candidate's stated assumption, that the code at 3f3e9af5 contradicts. Examples: the env candidate (TICKET.md:24) against run.sh:243, and the `--resume` candidate (TICKET.md:23) against run.sh:42. `no-false-premise` fails only when the message states such a premise as true, not when it offers it as an option. | user-answered | intent |
| D-3 | What the build does when the key falls short | The build stops before it opens a PR and asks the operator under OR-1, with the drafted facts and their count. Departs from the ticket's Fixture section: it said the build says so in the PR and stops there. | user-answered | intent |
| D-4 | How the facts-list length is counted | The prompt puts each of the two lists under a fixed heading. The README defines the length as the numbered items under the first heading of the final message. It gives a command where the result JSON holds that message. The headings must not match the `no-plan-written` pattern. | user-answered | intent |
| D-5 | How the recall `jq` line finds the fact graders | Every fact grader is named `fact-<slug>`. The `jq` line reads `.cases[].arms.with[].graders[]`, keeps names that start with `fact-`, and divides passed by count. A run with no fact graders prints null, never a division error. run: `LC_ALL=C grep -ao 'graders:t\.graders\.map((e)=>({name:e\.name,passed:e\.passed' ~/.local/share/claude/versions/2.1.330` → one match. From: F-7, F-9 | user-answered | intent |
| D-6 | Copy or share the scaffold | Copy. The case holds its own `scaffold.sh`, `scaffold-selftest.sh` and `fixture/TICKET.md`, with snapshot 3f3e9af5. `decision-questions-eval` is not edited. | user-answered | intent |
| D-7 | Where the answer key lives | Only in the `fact-` graders' criteria in `case.yaml`. No separate key file. `no-false-premise` repeats the premises, as the ticket accepts. | user-answered | intent |
| D-8 | Run shape | `runs: 5`, `max_turns: 60`, `timeout_seconds: 1800`, `allowed_tools: [Read, Glob, Grep, Skill, Bash]`, as `decision-questions-eval/case.yaml`. The README states that five runs show only a recall gap near 0.2 or more. From: F-10 | user-answered | intent |
| D-9 | Case name | `discovery-recall-eval`. It is the directory name and the `--case` argument in the README's run command. | user-answered | intent |
| D-10 | How the prompt asks for the facts list | The prompt asks for the facts the session would record as `codebase-derived` rows, each with its evidence. It does not define a fact, so it adds no exploration instruction that the skill lacks. run: `grep -ci premise plugins/intake-toolkit/skills/plan-interview/SKILL.md plugins/intake-toolkit/skills/interviewing-baseline/SKILL.md` → 0 and 0. From: F-12. Departs from the ticket's Prompt section: it defined a fact as a premise the code contradicts, or an omitted fact that forces a decision. | user-answered | intent |
| D-11 | How the eval catches a read outside the snapshot | A `regex` grader `stayed-in-snapshot` on the trace fails when a tool input names `intake-toolkit/evals` or `second-shift-908-decisions`. The README says to discard a run that fails it. Recall stays `fact-` graders only. run: `grep -c '"file_path":"/Users/[^"]*plugins/intake-toolkit/skills/intake/receipt.md"' /private/tmp/e-FYm1JV/out/trace.jsonl` → 1. From: F-6, F-14, F-15, F-16, F-17, F-18, F-27. Departs from the ticket's Graders section and Scope: they listed no grader for reads outside the snapshot. | user-answered | intent |
| D-12 | The scaffold's interface | Copied from the sibling scaffold. Inputs: none on the command line; `SNAPSHOT_REPO` and `SNAPSHOT_REF` in the env, optional, set only by the selftest. Outputs: `TICKET.md` and the 3f3e9af5 tree without top-level `.claude/`, `plugins/intake-toolkit/` and `.git`, in the current directory, exit 0. Errors: exit 1 with one stderr line and nothing written when the repo is not a git repo or lacks the commit. The selftest builds its own git repo, because the suite also runs from the install cache. run: `bash plugins/intake-toolkit/evals/decision-questions-eval/scaffold-selftest.sh` → ALL PASS. From: F-23 | codebase-derived | fact |
| D-13 | What the CI checks require of the eval files | No eval file except `BASELINE.md` names a model, and no criterion quotes run.sh:639-640 (`BUILD_MODEL=opus`/`sonnet`) verbatim. No issue number, AC-n or D-n id appears in the eval files (CLAUDE.md:89). The selftest is found by glob (tools/run-selftests.sh:172). run: `bash scripts/check-eval-model-identity.sh` → 34 runnable eval files carry no vendor model identity. From: F-19, F-20, F-21, F-22 | codebase-derived | fact |
| D-14 | Commit verb and changelog trailer | PR title `feat(intake-toolkit): …`, because the AI tooling is the product here. A `Changelog:` trailer in the branch, prose or `none`. cited (convention): CLAUDE.md:36 | codebase-derived | fact |
| D-15 | AC-1 test | Exempt. `case.yaml` is read only by the model-billed runner. The review reads it against the ticket, and `check-eval-model-identity.sh` covers model names. | user-answered | intent |
| D-16 | AC-2 test | Exempt. The operator approves the key at PR review. The README gives a `git show 3f3e9af5:<path> \| sed -n <n>p` recipe per anchor. | user-answered | intent |
| D-17 | AC-4 test | Exempt. The README is prose. PM-1's probe run proves the run command and the `jq` line. | user-answered | intent |
| D-18 | Where the D-4 count command reads the final message | From the run's trace, not the result JSON. Each run object carries `tracePath`, and the trace's last line is the `result` event whose `.result` is the final message. Traces sit under `/private/tmp/e-*/out/`, so the README says to count soon after the run. run: `jq -r '[.cases[].arms.with[].tracePath][0]' <aggregate-result.json>` → `/private/tmp/e-ZEF9Ue/out/trace.jsonl`; `tail -n1 <trace> \| jq -r .type` → result | codebase-derived | fact |
| D-19 | The fixture's off-by-one line number | Excluded from the key and from `no-false-premise`. TICKET.md:15 says run.sh:475, and `worktree_inflight` is at run.sh:476. A grader on it rewards copying the ticket, not discovery. | user-answered | intent |
| D-20 | How a `BASELINE.md` row tells the fixture case from a held-out case | The row format adds a `Case` column, `fixture` or `held-out`, before `Arm`. The held-out row still names no consumer and no ticket. Added in build: the ticket's row fields cannot tell the two rows PM-1 records apart. | user-delegated | intent |

Options weighed:

- D-1: (a) a code line plus a stated docs fact — about nine candidates, harder-to-find facts; (b) code-only facts — about five or six candidates, likely short of eight; (c) any fact the sources record — some facts have no honest line and lower recall for both arms. The operator chose (a) because #912's key departure came from such a fact.
- D-2: (a) statements and candidate assumptions — two or three real premises, the judge must tell an option from an assertion; (b) literal statements only — one trivial line-number premise. The operator chose (a) because #912 departed on these premises.
- D-3: (a) a pause-and-ask region — no red PR, the operator picks again; (b) a draft PR, flagged — AC-2 fails in review, a pad-to-eight incentive stays; (c) lower the bar — a coarse recall scale, departs from AC-2. The operator chose (a) because the ticket's PR path contradicts AC-2.
- D-4: (a) fixed headings and a README recipe — a reproducible count, PM-1 confirms the command; (b) count by hand with no headings — two readers can count differently. The operator chose (a) because it gives one count.
- D-5: (a) a `fact-` prefix — one naming rule, a misnamed grader drops out silently; (b) name each grader in the `jq` line — every key change edits the line. The operator chose (a) because the denominator follows the key.
- D-6: (a) copy into the new case — about 90 duplicated lines, each case self-contained; (b) share one scaffold — edits a merged case and couples two baselines. The operator chose (a) because it leaves `decision-questions-eval` untouched.
- D-7: (a) only in the grader criteria — one source, slower to review; (b) also a KEY.md — easy to review, two copies drift and one more file can leak. The operator chose (a) because a second copy drifts.
- D-8: (a) 5 runs as the sibling — known cost, only a gap near 0.2 shows; (b) 10 runs — about twice the cost, departs from PM-1. The operator chose (a) because PM-1 fixes five runs.
- D-9: (a) `discovery-recall-eval` — names the measure; (b) `code-facts-eval` — names the thing found. The operator chose (a) because it names what the case measures.
- D-10: (a) the skill's own words — recall measures the skill, the list can get longer; (b) the ticket's definition — both arms get the hint, a later fix shows little gain. The operator chose (a) because the baseline must measure the skill alone.
- D-11: (a) a trace grader — a per-run signal in the result JSON, unlisted paths go unseen; (b) a trace grep in the README — a manual step that can be skipped; (c) a warning only — a leaked run inflates recall unseen. The operator chose (a) because a walk-out was observed in an earlier eval trace.
- D-15: (a) exempt, reviewed at PR — a wrong grader shape shows only on the probe run; (b) a selftest over `case.yaml` — a presence guard over config. The operator chose (a) because only the runner reads the file.
- D-16: (a) exempt, the operator approves the key — a wrong line number passes CI; (b) a key-anchor selftest — must skip in the install cache and mirrors the key. The operator chose (a) because support for a fact is the operator's judgment.
- D-17: (a) exempt, prose — PM-1 proves the command and the `jq` line; (b) test the `jq` line on a fixture JSON — the fixture can drift from the runner. The operator chose (a) because PM-1 already runs the line on a real result.
- D-19: (a) exclude it — only facts that change the work, OR-1 can trigger sooner; (b) include it — an easy fact in both arms, and `no-false-premise` fails on a quote of the ticket. The operator chose (a) because neither grader would measure discovery.

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | The answer key has fewer than eight facts that meet D-1, or no premise that meets D-2 | pause-and-ask |

## Test intent

ACs: AC-1 AC-2 AC-3 AC-4

AC-1: exempt — `case.yaml` is read only by the model-billed runner; the review reads it, and `check-eval-model-identity.sh` covers model names
AC-2: exempt — the operator approves the answer key at PR review
AC-3: `scaffold-selftest.sh` shows that a repo without the snapshot commit makes `scaffold.sh` exit non-zero with one stderr line and an empty workspace
AC-4: exempt — the README is prose; PM-1's probe run proves the run command and the `jq` line

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | `case.yaml` run shape, read by the eval runner | decided (D-8) |
| S-2 | `scaffold.sh`, called by the eval runner | contract (D-12) |
| S-3 | The session's final message and its two headings | decided (D-4) |
| S-4 | The prompt's request for the facts list | decided (D-10) |
| S-5 | The `fact-` graders' criteria, the answer key | decided (D-1) |
| S-6 | The `no-false-premise` criteria | decided (D-2) |
| S-7 | The `stayed-in-snapshot` grader and the README discard rule | decided (D-11) |
| S-8 | The recall `jq` line over the result JSON | decided (D-5) |
| S-9 | The README run command and case name | decided (D-9) |
| S-10 | The `BASELINE.md` row with the facts-list length | decided (D-4) |
| S-14 | The facts-list count command over the run trace | decided (D-18) |
| S-11 | CI checks over the new eval files | decided (D-13) |
| S-12 | Release notes a consumer reads | decided (D-14) |
| S-13 | `/intake` and its fan-out under the eval | out-of-scope — the ticket's Out list excludes them, and the README says so. |

## Checks

- `bash plugins/intake-toolkit/evals/discovery-recall-eval/scaffold-selftest.sh`
- `bash scripts/check-eval-model-identity.sh`

## Intake steps

Requirements: the ticket body as written. spec-reviewer: implementable with gaps, no blockers. Its gaps became D-1 to D-9. No design handoff. The implementability probe ran once and reported AC-1 to AC-4 covered. Of its two guess-points, the code settled one (D-18) and the operator answered one (D-19).

Split: not triggered. No epic label and one deliverable. The register reached 10 operator decisions, at the bar and not past it.

Explore: done. Read the sibling case, its scaffold and selftest, the #908 record, the fixture ticket and run.sh at 3f3e9af5. A first fan-out launch with a placeholder body was stopped before any output was read.

Fan-out: ran — 30 items, see Fan-out

Dup-scan: no candidates at or above threshold 12

Post-merge scan: no post-merge AC. PM-1 is already under Post-merge checks.

Sizing: opus

<details>
<summary>Intake evidence: knowledge source and fan-out</summary>

## Knowledge source

Knowledge source: none declared

## Fan-out

Lenses: answer-key-sources opus 6 · measurement-validity opus 6 · isolation-and-leakage opus 6 · repo-gate-fit opus 6 · premortem opus 6
Tally: rows added 6 · snapshot claims overturned 0 · questions added 2 (D-10, D-11)

| ID | Angle | Claim | Tag | Disposition |
| --- | --- | --- | --- | --- |
| F-1 | answer-key-sources | Five candidates have a line at 3f3e9af5, including bounded() and add_cost (run.sh:216,245) and the BUILD allowlist with no Workflow (run.sh:458). | already-had | already had — D-1 |
| F-2 | answer-key-sources | Five more candidates qualify only under a lenient reading; strict total 5, lenient 10 (run.sh:185,243; CLAUDE.md:93). | already-had | already had — D-1 |
| F-3 | answer-key-sources | No literal premise is contradicted; the only mismatch is run.sh:475 against 476 (TICKET.md:15). | already-had | already had — D-2 |
| F-4 | answer-key-sources | The #908 comments hold only lane claim and approve lines (`gh issue view 908 --comments`). | already-had | already had — the snapshot held it; no row |
| F-5 | answer-key-sources | No #881 commit is in the snapshot's history; a fact on it needs a line anchor (`git log 3f3e9af5 --grep '#881'`). | already-had | already had — D-1 |
| F-6 | answer-key-sources | The key's source doc is outside the snapshot but inside the live checkout (`docs/plans/second-shift-908-decisions.md`). | new | became D-11 |
| F-7 | measurement-validity | The result JSON writes graders at `.cases[].arms.with[].graders[]` with name and passed (claude 2.1.330 binary). | new | became D-5 |
| F-8 | measurement-validity | An llm grader passes on two of three judge votes (docs plugin-evals, binary). | not material | not material — the ticket already states the rule |
| F-9 | measurement-validity | The `jq` line needs a fact prefix and a guard for a run with no graders (synthetic r.json, rc 5). | new | became D-5 |
| F-10 | measurement-validity | Five runs over 8 to 11 facts show only a gap near 0.2 (binomial model). | new | became D-8 |
| F-11 | measurement-validity | Recall rises with message length, and a fact named only in a question passes (binary focus text). | not material | not material — the ticket records list length and chose the focus |
| F-12 | measurement-validity | The prompt's fact definition is an instruction neither skill file holds (`grep -ci premise` → 0). | new | became D-10 |
| F-13 | isolation-and-leakage | The snapshot holds no #908 text, and #912 is not an ancestor of 3f3e9af5 (`git grep 3f3e9af5`). | not material | not material — confirms the snapshot holds no key content |
| F-14 | isolation-and-leakage | The runner loads the plugin from the live checkout and names its path to the session (trace init event). | new | became D-11 |
| F-15 | isolation-and-leakage | A session read a live skill file by absolute path (/private/tmp/e-FYm1JV/out/trace.jsonl). | new | became D-11 |
| F-16 | isolation-and-leakage | The sandbox denyRead covers the evals dir and `//Users` for Bash (config/settings.json). | new | became D-11 |
| F-17 | isolation-and-leakage | No test shows that the Read tool obeys denyRead; settings carry no permissions.deny. | new | became D-11 |
| F-18 | isolation-and-leakage | The README's trace check passes on a walk-out too (decision-questions-eval/README.md). | new | became D-11 |
| F-19 | repo-gate-fit | check-no-archeology reads only the .sh files; the selftest is found by glob (scripts/check-no-archeology.sh:56). | new | became D-13 |
| F-20 | repo-gate-fit | check-eval-model-identity.sh scans every eval file and exempts BASELINE.md (scripts/check-eval-model-identity.sh:55-67). | new | became D-13 |
| F-21 | repo-gate-fit | Quoting run.sh:639-640 `BUILD_MODEL=opus` in criteria turns that check red. | new | became D-13 |
| F-22 | repo-gate-fit | Issue numbers in eval files break the CLAUDE.md archeology rule (CLAUDE.md:89). | new | became D-13 |
| F-23 | repo-gate-fit | The install cache ships the evals dir, so the selftest must build its own repo (scaffold-selftest.sh:1-3). | new | became D-12 |
| F-24 | repo-gate-fit | A plugins/** PR needs a Changelog: trailer and touches no frozen file (scripts/check-changelog-trailer.sh:19-27). | already-had | already had — D-14 |
| F-25 | premortem | Most #908 record rows rest on docs or measurements, so eight facts may not be reached honestly. | already-had | already had — D-1 |
| F-26 | premortem | The fixture is in-sample for the SKILL.md:45 rule that #912 fitted to it. | not material | not material — the held-out row exists for this |
| F-27 | premortem | A session can reach `case.yaml` and the result JSON through the live plugin path (trace init event). | new | became D-11 |
| F-28 | premortem | The judge defaults to haiku when `--judge-model` is omitted (`claude plugin eval --help`). | not material | not material — the run command passes `--judge-model` |
| F-29 | premortem | The fixture names the facts' topics, and its run.sh:475 anchor is off by one (TICKET.md:15). | already-had | already had — D-2 |
| F-30 | premortem | The snapshot has no git history, so history-only facts need a CHANGELOG or docs anchor (scaffold.sh:22). | already-had | already had — D-1 |

### Snapshot

    | ID | Decision | Resolution |
    | --- | --- | --- |
    | D-1 | Which facts may enter the answer key | open: recommend a fact with a code line in the snapshot, also when its force rests on a documented tool behavior that the criteria state; exclude facts with no line in the snapshot |
    | D-2 | What counts as a false premise | open: recommend a ticket statement, or a candidate's stated assumption, that the snapshot's code contradicts (env candidate vs run.sh:243; --resume vs run.sh:42) |
    | D-3 | What the build does when the key falls short | open: recommend a pause-and-ask region; the build stops before the PR and asks |
    | D-4 | How the facts-list length is counted | open: recommend fixed headings for the two lists in the prompt; the README counts the numbered items under the first |
    | D-5 | How the recall jq line finds the fact graders | open: recommend a `fact-` name prefix |
    | D-6 | Scaffold: copy or share | open: recommend a copy of scaffold.sh, its selftest and the fixture in the new case |
    | D-7 | Where the answer key lives | open: recommend only in the grader criteria |
    | D-8 | Case name and run shape | open: recommend discovery-recall-eval; run shape as decision-questions-eval/case.yaml |
    | D-9 | no-false-premise on an option or a question | ticket text: it fails only when the message states the premise as true |
    | D-10 | Commit verb and trailer | feat(intake-toolkit) and a Changelog: trailer (CLAUDE.md) |
    
    Facts held before the pool:
    - scaffold.sh:22 extracts 3f3e9af5 without .claude/ and plugins/intake-toolkit/; no .git. scaffold.sh:12 finds the fixture from its own directory.
    - case.yaml:28-30 max_turns 60, timeout 1800, allowed_tools Read Glob Grep Skill Bash. no-plan-written matches only Decision Ledger / Implementation Plan / Plan headings.
    - #908's comments are lane claim and approve lines; they hold no facts (spec-reviewer).
    - Code lines at 3f3e9af5: run.sh:42 fresh-process rule; run-selftest.sh:144 [F1] no --resume; run.sh:243 --setting-sources user,project,local; run.sh:712 -p spawn with --permission-prompts none, --allowedTools, --max-turns; CHANGELOG.md:904 the --bg spawn (#810); run.sh:186 cap accepts a fractional value; CLAUDE.md:93-94 tells sessions to background the sweep; run.sh:467-468 the review allowlist holds Workflow (review-lead panel); run.sh:476 worktree_inflight (the ticket says 475).
    - Facts with no line in the snapshot: D-5 (measurement), D-17 (.claude/), D-18 (plugins/intake-toolkit/); the 600 s wait and the 120 s default are documented tool behavior.
    - plan-interview SKILL.md:21 records codebase-answerable facts as codebase-derived, never asked.
    - tools/run-selftests.sh:172 discovers every *-selftest.sh by glob.
    - spec-reviewer: implementable with gaps, no blockers. Gaps: fact admission, short-key end state, jq grader selection, facts-list count, case name, scaffold copy/share, key location.

</details>
