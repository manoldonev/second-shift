# Decision record — #1367 Intake: decision questions carry each option's cost, graded by an eval

Receipt: v5

## Summary

The interview loop rules gain a shape for a decision question: its reason, its options, each option's consequence and a recommendation. The per-turn question cap goes, rule 9 gains a clarify case, and the `Options weighed:` list gets one form. One operator-run eval case for `claude plugin eval` grades the questions of `plan-interview` on a fixture ticket.

Open regions: OR-1, the scaffold script finds the repo from its own path. The build uses that default.

Provenance legend: `user-answered` = the operator chose. `user-delegated` = the operator gave the choice to the agent. `codebase-derived` = a fact from the code or the docs, with its proof. `deferred` = not decided yet, under an open region.

Open region legend: `reversible-default-and-flag` = the build uses the stated default.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | One ticket or two for the rule and its eval | One ticket. It carries the rule, the rule fixes and the eval case. | user-answered | intent |
| D-2 | Eval runner | `claude plugin eval`, the built-in runner of the CLI. | user-answered | intent |
| D-3 | Per-turn question cap of loop rule 2 | Removed. Rule 2 is replaced in place. A turn carries every decision that does not depend on an unanswered one. Each decision is its own question with its own answer. Rule 8 stays as written. | user-answered | intent |
| D-4 | Loop rule 9 on a request to clarify | One rule with two cases. A request to clarify one question puts that question again in the decision shape and adds nothing. That is not a re-ask under rule 5. Pushback on the round still widens. | user-answered | intent |
| D-5 | A decision with no grounded recommendation | It still states its reason and each option's consequence. It then says that there is no recommendation and which fact is missing. "Ask plain" applies to fact questions only. | user-answered | intent |
| D-6 | Fixture ticket for the eval | The body of closed issue 908, without its admission paragraph, as `TICKET.md`. The code is this repo at commit `3f3e9af5`, the parent of the fix. | user-answered | intent |
| D-7 | Coverage of the live dialog | A post-merge check by the operator on the first live intake, PM-2 in the ticket. The eval does not cover the dialog. | user-answered | intent |
| D-8 | Pass bar for the eval score | PM-1 in the ticket. Five runs per arm. The after score is at least 0.90 and at least 0.20 above the before score. After three failed rewording passes, every skill-file change is reverted and the eval stays. `BASELINE.md` gets one row per arm: date, arm, commit, subject model, judge model, runs, case score, votes per LLM grader. | user-answered | intent |
| D-9 | Shape of a decision question | Four parts in order: the reason with its code location, two to four options, each option's consequence, the recommendation with its reason. In `AskUserQuestion`, each consequence goes in the option's `description` and the recommended option is first. At most one sentence stands above the dialog. One decision gets one question. Plain text uses the same four parts. | user-answered | intent |
| D-10 | Numbering of the loop rules | The rules stay numbered 1 to 9. The decision-question rule replaces the text of rules 3 and 4. | user-delegated | intent |
| D-11 | Subject of the eval | `plan-interview` on `TICKET.md`, non-interactive, with `AskUserQuestion` disallowed. The session ends its turn with every question of the whole interview, numbered, and answers none. | user-delegated | intent |
| D-12 | Contents of the snapshot | The tree of the commit from `git archive`, without `.git`, `.claude/` and `plugins/intake-toolkit/`. | user-delegated | intent |
| D-13 | Form of the `Options weighed:` list | The literal form of the ticket lives once, in `interviewing-baseline`. `intake/receipt.md` refers to it. One bullet per row that was put to the operator. `plan-interview/SKILL.md` no longer puts the options in the Resolution. | user-delegated | intent |
| D-14 | Lint or test for the wording of the rules | None. cited (convention): .claude/skills/writing-tests/SKILL.md:13 | codebase-derived | fact |
| D-15 | Consequence of a PM-2 miss | The operator files a ticket for the wording of the dialog mapping. The rule and the eval stay. From: F-28 | user-answered | intent |
| D-16 | A decision with five or more viable options | The question offers the four strongest. Its text names each dropped option and why it was dropped. From: F-27 | user-answered | intent |
| D-17 | Files that restate the cap | Five sites change: `plan-interview/SKILL.md` step 5 and its opening, `grill-me/SKILL.md`, `intake/requirements.md`, `intake/interview.md`. "One at a time" becomes "each as its own question". `figma-iterate/SKILL.md` drops its reference to the cap and keeps the tool limit of four. The one-batch rule of the onboard skill stays. run: `grep -c "one at a time" plugins/intake-toolkit/skills/intake/interview.md plugins/intake-toolkit/skills/plan-interview/SKILL.md` → 1 and 1. From: F-2, F-30 | codebase-derived | fact |
| D-18 | Model names in the eval files | None, except in `BASELINE.md`. The README command reads `--judge-model "$JUDGE_MODEL"` and `--model "$SUBJECT_MODEL"`. A CI guard fails on an alias in a model position. run: `grep -n "^ALIASES=" scripts/check-eval-model-identity.sh` → 67: opus, sonnet, haiku, fable. From: F-11, F-17 | codebase-derived | fact |
| D-19 | Interface of the scaffold script | The eval runner starts it in the empty workspace. Inputs: no arguments. `SNAPSHOT_REPO` (optional, default the repo that holds the script). `SNAPSHOT_REF` (optional, default `3f3e9af5`). Outputs: exit 0, and the current directory holds `TICKET.md` and the snapshot of D-12. Errors: a non-zero exit with one line on stderr when the repo is not a git repo or does not hold the commit. From: F-15, F-16, F-25 | user-delegated | intent |
| D-20 | Repo that the scaffold selftest reads | The selftest is `scaffold-selftest.sh` in the case directory. It builds its own git repo in a temporary directory and sets `SNAPSHOT_REPO` and `SNAPSHOT_REF`. cited (convention): docs/testing.md:289. From: F-16 | codebase-derived | fact |
| D-21 | Reports that the runner writes | `plugins/intake-toolkit/evals/.gitignore` ignores `results/`. From: F-10 | user-delegated | intent |
| D-22 | Criteria without a test | AC-1, AC-2, AC-3, AC-4, AC-6 and AC-7 are exempt. The review scores them by reading the diff. Only AC-5 has a test. | user-answered | intent |
| D-23 | Shape of a fact question | It stays short and carries no consequences. It may offer labeled answers. cited (convention): plugins/intake-toolkit/skills/intake/requirements.md:71. From: F-3 | codebase-derived | fact |
| D-24 | Issue numbers in the eval scripts | The scaffold script and its selftest name no issue number. A CI lint fails on one in a shell file. run: `sed -n 2,3p scripts/check-no-archeology.sh` → fails on an issue number in a shell, mjs or python file. From: F-18 | codebase-derived | fact |
| D-25 | Recipe for the "before" arm | A git worktree at the commit before this change. The case directory is copied into its `plugins/intake-toolkit/evals/`. The README gives the recipe. | user-delegated | intent |
| D-26 | Check that an arm reads its own rules | The README tells the operator to confirm, from the first run's trace, that the skill files come from the tree under test. From: F-26 | user-delegated | intent |
| D-27 | Definition of the eval case | One case in `plugins/intake-toolkit/evals/decision-questions-eval/`, in a form the runner reads, with five runs and the five graders and weights of the ticket. Inputs: none — the runner reads the case directory and takes no arguments from it. Outputs: a run scores the weighted share of graders that passed, and the case scores the mean of its runs. Errors: a failed scaffold scores the run 0, and the runner exits 1 under its threshold. | user-delegated | intent |
| D-28 | Does the runner start the scaffold script from its case directory | Parked under OR-1. The plugin-evals documentation does not say. Owner: the operator, at the first eval run. | deferred | open |
| D-29 | Limits and tools of an eval run | 60 turns and 30 minutes per run. Allowed tools: Read, Glob, Grep, Skill and Bash. The README command carries `--allow-tools Bash`. | user-answered | intent |
| D-30 | Sentences that require a recommendation on every question | They are aligned with rules 3 and 4. The sites are the opening and "What NOT to do" of `plan-interview/SKILL.md`, `grill-me/SKILL.md` and the opening of `intake/interview.md`. | user-answered | intent |
| D-31 | Type of the `read-the-scheduler` grader | A regex on the trace that matches a Read, Bash, Grep or Glob call whose input names `run.sh`. The match stays inside one tool call's input, so the path in the ticket text does not count. Changed after review on the operator's instruction: a probe run read `run.sh` with Bash, and the `tool_used` grader on Read failed it. | user-answered | intent |
| D-32 | A turn with more questions than one `AskUserQuestion` call takes | Rule 2 says to use more than one call. Added in build: without the cap, a turn can hold more than the tool's four questions per call. | user-delegated | intent |
| D-33 | How a run disallows `AskUserQuestion` | The README command carries `--disallow-tools AskUserQuestion`, and the appended system prompt says the tool is unavailable. Added in build: the case schema has no key for it, and a working case in another repo uses that flag. | user-delegated | intent |
| D-34 | Form of a `BASELINE.md` vote cell | The runs that passed out of the runs, then each run's PASS votes out of three, in run order. Example: `4/5 (3,3,2,3,1)`. Added in build: the record names the column but not its form. | user-delegated | intent |
| D-35 | A conditional recommendation in `primary-decision-framed` | It passes when it names the open fact, or the question that asks it, and marks the recommended option for each answer. Added after review on the operator's instruction: the run lists every question at once, so the mechanism question can come before its fact. | user-answered | intent |

Options weighed:

- D-1: one ticket, two tickets with the eval first, or the rule with no eval. The operator chose one ticket.
- D-2: `claude plugin eval`, a runner on agent-eval-kit, or a README with manual dispatch. The operator chose `claude plugin eval`.
- D-3: keep the cap at 2, allow 4 uncoupled decisions per call, or remove the cap. The operator chose to remove the cap.
- D-4: split the rule into two cases, leave it, or delete it. The operator chose the two cases.
- D-5: options and costs with no pick, or keep "ask plain". The operator chose options and costs with no pick.
- D-6: closed issue 908, a synthetic ticket with a small repo, or two fixtures. The operator chose issue 908.
- D-7: a post-merge check, no live check, or a second eval case with a canned answerer. The operator chose the post-merge check.
- D-8: a fixed bar with a stop rule, scores with no bar, or a bar with no revert. The operator chose the fixed bar with the stop rule.
- D-15: file a fix and keep the rule, the stop rule of PM-1, or no stated consequence. The operator chose to file a fix.
- D-16: show four and name the rest, fall back to plain text, or split into two questions. The operator chose to show four.
- D-22: exempt all six, exempt five and test AC-6, or exempt none. The operator chose to exempt all six.
- D-29: 60 turns and 30 minutes with Bash, the same limits read-only, or 40 turns and 15 minutes with Bash. The operator chose 60 turns and 30 minutes with Bash.
- D-30: align the sentences or leave them. The operator chose to align them.
- D-31: `tool_used` on Read, a regex anchored on the Read call, or no such grader. The operator chose `tool_used` on Read.

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | Whether the eval runner starts the scaffold script from its case directory | reversible-default-and-flag |

OR-1 default: the script finds the repo from its own path. The agent chose it, because a working case in another repo does the same. If the runner copies the script first, the first eval run fails with `scaffold failed`, and the fix is one line.

## Test intent

ACs: AC-1 AC-2 AC-3 AC-4 AC-5 AC-6 AC-7

AC-1: exempt — the rule is prose in a skill file, and the repo forbids a test that greps its wording
AC-2: exempt — the removal is prose in skill files, and the repo forbids a test that greps its wording
AC-3: exempt — the rule is prose in a skill file, and the repo forbids a test that greps its wording
AC-4: exempt — the form is prose in skill files, and no lint reads the list
AC-5: run against a repo and a commit, the scaffold script fills the current directory with `TICKET.md` and the commit's tree without `.git`, `.claude/` and `plugins/intake-toolkit/`, and it exits non-zero when the repo lacks the commit
AC-6: exempt — the case and the README belong to an eval that only the operator runs
AC-7: exempt — it states what the pull request leaves untouched, which the diff shows

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | Decision question in the `AskUserQuestion` dialog | decided (D-9) |
| S-2 | Decision question as plain text | decided (D-9) |
| S-3 | Decision question with five or more options | decided (D-16) |
| S-4 | Decision question with no recommendation | decided (D-5) |
| S-5 | Fact question | decided (D-23) |
| S-6 | Question put again after a request to clarify | decided (D-4) |
| S-7 | `Options weighed:` list in a record | decided (D-13) |
| S-8 | Scaffold script, started by the eval runner | contract (D-19) |
| S-9 | Eval case definition, parsed by the eval runner | contract (D-27) |
| S-10 | Eval README | decided (D-18) |
| S-11 | `BASELINE.md` row | decided (D-8) |
| S-12 | HTML report of the eval runner | out-of-scope — the runner writes it, and this change does not shape it. |

## Checks

- `bash scripts/check-eval-model-identity.sh`
- `bash scripts/check-no-archeology.sh`

## Intake steps

Requirements: interviewed (feature). Filed as #1367 on the operator's yes. spec-reviewer: no blockers, and 11 gaps closed in the body. The body was amended twice on the operator's yes. The probe raised three points, and the operator settled each one (D-29, D-30, D-31).

Split: not split. The operator chose one ticket for the rule and its eval (D-1).

Explore: done. Read the loop rules, every file that restates them, the receipt stage, the eval guards, the runner's help and documentation, and the fixture commit.

Fan-out: ran — 30 items, see Fan-out

Dup-scan: no candidates at or above threshold 12

Post-merge scan: no post-merge AC. The ticket was filed with PM-1 and PM-2 outside its AC block.

Sizing: opus

<details>
<summary>Intake evidence: knowledge source and fan-out</summary>

## Knowledge source

Knowledge source: none declared

## Fan-out

Lenses: rule-citers-and-restatements opus 6 · eval-cli-contract opus 6 · fixture-and-ci-path opus 6 · record-readers opus 6 · premortem opus 6
Tally: rows added 10 · snapshot claims overturned 0 · questions added 2 (D-15, D-16)

| ID | Angle | Claim | Tag | Disposition |
| --- | --- | --- | --- | --- |
| F-1 | rule-citers-and-restatements | The four files on the ticket's list hold per-turn cap text (`plan-interview/SKILL.md:58`). | already-had | already had — D-3 |
| F-2 | rule-citers-and-restatements | `intake/interview.md:3` says decisions are settled "one at a time", which the ticket's list misses. | new | became D-17 |
| F-3 | rule-citers-and-restatements | `intake/requirements.md:71` asks for labeled options on reporter-owned facts, against a one-sentence fact question. | new | became D-23 |
| F-4 | rule-citers-and-restatements | Only rules 1, 5 and 6 are cited by number (`intake/SKILL.md:128`). | already-had | already had — D-10 |
| F-5 | rule-citers-and-restatements | Three files disagree on where weighed options go (`plan-interview/SKILL.md:45`). | already-had | already had — D-13 |
| F-6 | rule-citers-and-restatements | The exemption in `figma-iterate/SKILL.md:126` has nothing to exempt from once the cap goes. | already-had | already had — D-3 |
| F-7 | eval-cli-contract | The case schema has one key per run-shape element (strings of the CLI binary). | not material | not material — the ticket leaves the case form to the build |
| F-8 | eval-cli-contract | Only the `--judge-model` flag sets the judge, and its default is haiku (`claude plugin eval --help`). | already-had | already had — D-2 |
| F-9 | eval-cli-contract | Every flag the README names exists, and `--scaffold` is off by default (`claude plugin eval --help`). | already-had | already had — D-2 |
| F-10 | eval-cli-contract | The runner writes results under `plugins/intake-toolkit/evals/results/`, which git does not ignore. | new | became D-21 |
| F-11 | eval-cli-contract | A literal model alias in the README command fails `scripts/check-eval-model-identity.sh:67`. | new | became D-18 |
| F-12 | eval-cli-contract | The repo has no case file yet, and a case elsewhere on this machine uses the same run shape. | not material | not material — it confirms the run shape and changes no row |
| F-13 | fixture-and-ci-path | Commit `3f3e9af5` is the only parent of the fix commit `0b6154d2` (`git log -1`). | already-had | already had — D-6 |
| F-14 | fixture-and-ci-path | The archive of `3f3e9af5` holds `run.sh`, `.claude/` and `plugins/intake-toolkit/` (`git archive`). | already-had | already had — D-12 |
| F-15 | fixture-and-ci-path | CI fetches full history, and the local checkout is shallow (`.github/workflows/ci.yml:22`). | new | became D-19 |
| F-16 | fixture-and-ci-path | A selftest under `plugins/` also runs from an install cache with no git repo above it (`docs/testing.md:283`). | new | became D-19, D-20 |
| F-17 | fixture-and-ci-path | The model-identity guard scans every eval file except `changelog.md` and `BASELINE.md` (`scripts/check-eval-model-identity.sh:57`). | new | became D-18 |
| F-18 | fixture-and-ci-path | The archeology lint scans shell files and fails on an issue number (`scripts/check-no-archeology.sh:2`). | new | became D-24 |
| F-19 | record-readers | `ledger-lint.sh` never reads the Options weighed list (grep count 0). | already-had | already had — D-13 |
| F-20 | record-readers | No lint rule needs options in a Resolution cell (`ledger-lint.sh:468`). | already-had | already had — D-13 |
| F-21 | record-readers | `interviewing-baseline/SKILL.md:453` holds a lockstep copy of the receipt-version table. | not material | not material — AC-7 already forbids an edit to that table |
| F-22 | record-readers | The scheduler and the verdict check read no options list (`run.sh:494`). | already-had | already had — D-13 |
| F-23 | record-readers | The review prompts score rows against the Resolution cell only (`scope-completeness-reviewer.md:104`). | already-had | already had — D-13 |
| F-24 | record-readers | The probe eval's `planted-record.md:22` uses the old list form. | not material | not material — the fixture is an old-form record, and no reader parses the list |
| F-25 | premortem | `3f3e9af5` is not reachable from the shallow local main (`git merge-base --is-ancestor`). | new | became D-19 |
| F-26 | premortem | An arm could read rules from the user-scope install, not from the tree under test. | new | became D-26 |
| F-27 | premortem | Issue 908 names three candidates and plan-interview adds one, so options can pass four (`plan-interview/SKILL.md:45`). | new | became D-16 |
| F-28 | premortem | The eval can pass while PM-2 fails, and PM-2 has no stated consequence. | new | became D-15 |
| F-29 | premortem | The weights total 9, so one failed framing grader scores a run 0.78 or less. | not material | not material — two such runs of five still score 0.91 |
| F-30 | premortem | The onboard skill's one-batch rule could be read as a cap under AC-2 (`onboard/SKILL.md:118`). | new | became D-17 |

### Snapshot

    # Snapshot — #1367, before the fan-out pool is read

    ## Register

    | ID | Decision | Resolution |
    | --- | --- | --- |
    | D-1 | One ticket or two for the rule and its eval | One ticket. The before score comes from a tree without the rule, the after score from the branch |
    | D-2 | Eval runner | `claude plugin eval`, the CLI's built-in runner |
    | D-3 | Per-turn question cap (loop rule 2) | Removed. A turn carries every decision that does not depend on an unanswered one |
    | D-4 | Loop rule 9 on a request to clarify | One rule, two cases: a request to clarify one question re-puts that question; pushback on the round widens |
    | D-5 | A decision with no grounded recommendation | It still states its reason and each option's consequence, then says there is no recommendation and which fact is missing |
    | D-6 | Fixture ticket | Closed issue #908, read against the repo at the commit before its fix |
    | D-7 | Coverage of the live dialog | A post-merge check by the operator on the first live intake |
    | D-8 | Pass bar for the eval | After at least 0.90 and at least 0.20 above before, five runs per arm. Three rewording passes, then revert the skill changes and keep the eval |
    | D-9 | Shape of a decision question | Reason with code location, 2-4 options, each option's consequence, recommendation with reason; consequences in the AskUserQuestion option descriptions |
    | D-10 | Loop rule numbering | Rules stay 1-9; the new rule replaces the text of rules 3 and 4; rule 2 is replaced in place |
    | D-11 | Eval subject | `plan-interview`, because an isolated run loads only the plugin under test |
    | D-12 | Snapshot contents | `git archive 3f3e9af5`, without `.git`, `.claude/` and `plugins/intake-toolkit/` |
    | D-13 | Options weighed form | One literal form in interviewing-baseline; receipt.md refers to it; one bullet per row put to the operator |
    | D-14 | Lint for the rule's wording | None |

    ## Facts held

    - The cap is stated at interviewing-baseline/SKILL.md:17 and restated at plan-interview/SKILL.md:58, grill-me/SKILL.md:6, intake/requirements.md:70; figma-iterate/SKILL.md:127 refers to it.
    - `ledger-lint.sh` has no rule for `Options weighed:` (grep count 0); the form appears at receipt.md:161 and interviewing-baseline/SKILL.md:58.
    - Loop rules are cited by number at intake/SKILL.md:128, plan-interview/SKILL.md:77, intake/interview.md:57, interviewing-baseline/SKILL.md:21 and :342.
    - The fix of #908 is commit 0b6154d2; its parent is 3f3e9af5, which holds run.sh and 872 files, 46 of them under `.claude/` or `plugins/intake-toolkit/`. The snapshot extracts in under a second.
    - A scaffold script starts in the empty workspace with PATH, a temporary HOME and TMPDIR, gets no arguments, must finish in 120 seconds, and a non-zero exit scores the run 0 (plugin-evals documentation).
    - A run loads only the plugin under test; project `.claude/` configuration is not loaded; runs use the operator's normal Claude Code login.
    - The runner's default judge is the background-task model; `--judge-model` overrides it; default runs are 3; results go to `<plugin>/evals/results/<timestamp>/`.
    - Selftests are discovered by the `*-selftest.sh` glob (tools/run-selftests.sh).
    - spec-reviewer: no blockers, 11 gaps, all closed in the filed body.
    - This repo declares no knowledge source.

</details>
