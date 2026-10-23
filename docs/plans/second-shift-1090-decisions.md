# Decision record — #1090 A planted-defect corpus measures whether the lane review beats a plain review with the ticket

Receipt: v4

## Summary

A corpus of planted cases, built on real TypeScript and JavaScript issues and fixes from Multi-SWE-bench, measures whether the lane's review catches what a plain Opus review with the ticket misses. The recipe runs both arms on blind builds of each case and scores right, wrong, harm and noise per class. The operator runs it after merge against a gate set in advance.

Open regions: OR-1, where the recipe lives. OR-2, which upstream instances. OR-3, the local `gh` and ref mechanics. OR-4, deletion line ranges. OR-5, the judge's input. All are flagged defaults.

Provenance legend: `user-answered` = the operator chose. `codebase-derived` = a fact from the code or the docs, with its proof.

Open region legend: `reversible-default-and-flag` = the build uses the stated default.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | What the plain arm is given | The ticket only, never the record. P2 is scored and reported, but it does not gate PM-1. | user-answered | intent |
| D-2 | How the lane arm is built | The real review prompt and scheduler input, rendered from `run.sh` as merged. The ticket and an empty PR are served locally. The posted verdict is captured to a file. The record is its own commit. | user-answered | intent |
| D-3 | The corpus's base | Multi-SWE-bench TypeScript and JavaScript instances under permissive licenses, pinned by sha. Plants edit the real fix. Our record and `review-context.md` overlay each case. Cases clone at recipe time. CI checks structure only. | user-answered | intent |
| D-4 | The lane's gates in the comparison | Yes. Plan coverage runs on every case. Fails without the change runs where the recipe configures a runner, and is not-applicable elsewhere. A gate that stops a planted case is a lane catch. | user-answered | intent |
| D-5 | The plain arm's output | The same verdict contract: a `verdict:` line, then `[blocker]` and `[note]` items with path:line. It gets none of the lane's other rules. | user-answered | intent |
| D-6 | What counts as a catch | Right is a matching `[blocker]`, a `violated` or `undeterminable` row (P2), or a lane gate stop. P5 is right on a matching `[note]`, and its approve is not wrong. Wrong is a planted case approved. Noise is an unmatched `[blocker]` on a planted case. | user-answered | intent |
| D-7 | How a finding matches a plant | Its path:line is inside the planted range, within three lines, and the bench's judge agrees it describes the plant. A P2 row matches by its id. The bench's calibration gate runs first. | user-answered | intent |
| D-8 | Corpus size, runs and the gate | Four cases per class, five clean controls, three runs per arm. PM-1 passes when the lane's worst run beats plain's best run on right − wrong − harm, overall and on P1. | user-answered | intent |
| D-9 | Where the ACs come from | Each ticket is the upstream issue text plus an `## Acceptance criteria` block written for the case. The record carries a matching `## Test intent` line. | user-answered | intent |
| D-10 | The gates' inputs | The patch carries the plan a build would commit, with test tasks tagged to ACs. A P1 untested-AC plant drops a test the plan names. | user-answered | intent |
| D-11 | What the plain arm's checkout holds | The base, the repo-content overlay and the patch, without the record commit. Plain can read `review-context.md`. | user-answered | intent |
| D-12 | How harm counts | Once per clean control the arm would send back: a `[blocker]`, a `violated` or `undeterminable` row, or a gate stop. A not-applicable or uncheckable gate is not a stop. | user-answered | intent |
| D-13 | AC-11's test intent | Exempt. It changes docs only. | user-answered | intent |
| D-14 | The spec blockers | Settled in this interview, and the body of #1090 amended to match before this receipt. | user-answered | intent |
| D-15 | Rendering the prompt without changing `run.sh` | Extract `review_prompt()`, `review_input()` and their helpers textually and evaluate them with stubbed globals. `run.sh` has no source guard, and a probe rendered a 96-line prompt this way. run: `grep -c BASH_SOURCE plugins/dev-pipeline/skills/run/run.sh` → 0 | codebase-derived | fact |
| D-16 | The gates run before the review | `plan_coverage` and `fails_without_change` each send a red back before `review_input` is built. The recipe keeps that order. run: `sed -n 1824,1841p plugins/dev-pipeline/skills/run/run.sh` → plan_coverage, fails_without_change, then review_input | codebase-derived | fact |
| D-17 | Which commit carries `review-context.md` and the config | The overlay commit before the record. `policy_edited()` lists any `.claude/second-shift/` path in `FIRST..HEAD`, which the prompt makes a blocker. run: `grep -n 'index(f, ".claude/second-shift/")' plugins/dev-pipeline/skills/run/run.sh` → 996 | codebase-derived | fact |
| D-18 | Case ids | Neutral and random. The bench writes the case id into the reviewer's scratch path and session name. run: `grep -n '"bench-' plugins/review-toolkit/evals/code-review-bench-eval/bench.py` → 199: `-n bench-{arm}-{pr id}` | codebase-derived | fact |
| D-19 | Where the recipe is documented | `docs/testing.md`'s Benchmark tier. run: `grep -n 'Benchmark tier' docs/testing.md` → 728 | codebase-derived | fact |
| D-20 | Where a case's `review-context.md` and config live | One overlay per upstream, under `planted/overlays/<owner>__<repo>/`, named by the case's `overlay` key. The structure check requires both files of each case's overlay. Added in build: five upstreams share the 25 cases, and a copy per case would repeat each file up to fifteen times. | user-delegated | intent |
| D-21 | Where `origin/<base branch>` points in a case checkout | At the overlay commit, not at the upstream base, so the overlay sits below the diff the review prompt names and the lane's policy-edit trace lists nothing. The issue and PR numbers are the upstream's. Added in build: OR-3 sets the ref locally but leaves its commit open. | user-delegated | intent |
| D-22 | How the lane's session is started | With the review prompt and `review_allowlist()` rendered from `run.sh`, and the flags of `run.sh`'s `spawn()` for a review restated in `planted.py`: acceptEdits, no permission prompts, the three disallowed tools, the checkout and scratch dir added, background tasks off, Bash bounded by `inner_ms` of the one-hour bound, 300 turns. Added in build: `spawn()` starts the session, so D-15's rendering cannot produce its flags. | user-delegated | intent |
| D-23 | Fails without the change on the shipped cases | No overlay configures a test runner, so the gate is not-applicable on every case. When a config names a runner, the recipe runs `run.sh`'s own `fails_without_change`. Added in build: an upstream's tests need its dependencies installed, and a depth-1 clone at recipe time installs none. | user-delegated | intent |
| D-24 | A P2 `[blocker]` that names the planted row | It matches the plant: it is right and it is not noise. Added in build: the lane raises a violated row as a rule finding with no path:line, which D-7's location rule cannot match, and D-6 makes that row right. | user-delegated | intent |
| D-25 | Unscorable runs in the gate's nets | A run's net counts only its scorable reviews. The report and the changelog row give the unscorable count per class beside it. Added in build: OR-5 says an unscorable verdict is never an approve, and leaves open how the gate counts it. | user-delegated | intent |

Options weighed:
- D-1: ticket only with P2 non-gating, ticket plus record plus review-context, or ticket only with P2 gating. The operator chose the first.
- D-2: render the real prompt, or a hand arm from the lockstep blocks. The operator chose render.
- D-3: Multi-SWE-bench, a synthetic repo in a git bundle, both, this repo, or the bench's forks. The operator chose Multi-SWE-bench.
- D-5: the same verdict contract, or map plain's bare list. The operator chose the same contract.
- D-6: gated catch with P5 by detection, detection only, or `[blocker]` only. The operator chose the first.
- D-7: location and judge, judge only, or location only. The operator chose both.
- D-8: 4/5/3, 2/3/2, or 6/6/4. The operator chose 4/5/3.
- D-9: write an AC block, or the issue text only. The operator chose write.
- D-10: the plan in the patch with runners where cheap, both on every case, or plan coverage only. The operator chose the first.
- D-11: repo plus patch without the record, the lane's checkout, or no review-context. The operator chose the first.
- D-12: per control, or per blocker. The operator chose per control.

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | Where the corpus and recipe live | reversible-default-and-flag |
| OR-2 | Which Multi-SWE-bench instances | reversible-default-and-flag |
| OR-3 | The local `gh`, the origin ref and the verdict capture | reversible-default-and-flag |
| OR-4 | The line range of a plant that deletes lines | reversible-default-and-flag |
| OR-5 | The judge's input and a malformed verdict | reversible-default-and-flag |

Defaults, all chosen by the intake session. Each costs one recipe or data edit to reverse.
- OR-1 default: a `planted` mode of `code-review-bench-eval`, reusing its judge, cache, calibration and blindness scan, with its own changelog. Its rows never compare with the known-bug rows.
- OR-2 default: the smallest fixes that carry fail-to-pass tests, from MIT, BSD, Apache-2.0 or ISC upstreams, with a NOTICE naming each. P4's stored-data plants come from an instance that persists data. Elsewhere P4 plants a caller break.
- OR-3 default: a `gh` on the session's PATH answers `issue view` from the case ticket and `pr view` with an empty PR, and saves the `pr comment` body as the verdict. `refs/remotes/origin/<base>` is set locally and no remote exists. The blindness scan allows that `gh` only.
- OR-4 default: the head-side position where the deleted lines were, plus the base-side range, and a finding near either matches.
- OR-5 default: the plant's one-sentence description is the golden comment for the bench's judge prompt, unchanged, and the judge runs only on findings inside the range. A verdict that fails `verdict-check.sh` is reported as unscorable, never as approve.

## Test intent

ACs: AC-7 AC-8 AC-9 AC-10 AC-11

AC-7: a selftest fails on a case that lacks any part the corpus requires, and passes on the shipped corpus
AC-8: the model-free selftests for corpus structure, prompt rendering and the scorer fail without the change
AC-9: a selftest renders both arms' prompts for a case without a model, and finds no planted marker in either
AC-10: a selftest drives the scorer on canned reviews and gets right, wrong, harm and noise as expected per class and arm
AC-11: exempt — docs only

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | The recipe's report per class and arm | decided (D-6) |
| S-2 | The planted mode's changelog rows | decided (D-8) |
| S-3 | A materialized case checkout | decided (D-17) |
| S-4 | The plain arm's checkout | decided (D-11) |
| S-5 | The lane arm's rendered prompt | decided (D-15) |
| S-6 | The CI selftests' output | decided (D-3) |
| S-7 | The Benchmark tier docs | decided (D-19) |
| S-8 | The known-bug bench and its arms | out-of-scope — the planted mode adds rows of its own and changes no existing arm. |
| S-9 | The lane itself | out-of-scope — the ticket's Out keeps the review as merged. |

## Checks

No ticket-specific checks. The configured checks cover this change.

## Intake steps

Requirements: the ticket body as rewritten in session on the operator's word. spec-reviewer: needs work, four blockers. The operator chose to settle them in the interview, and the body was amended.

Split: not triggered at first. No epic label and one deliverable. The register passed ten decisions, and Split then classified it as tooling. Not split: the corpus, both arms and the scorer only measure together.

Explore: done. Read the bench harness, its judge and calibration, the merged review prompt and its gates, plan-coverage.sh and Multi-SWE-bench's dataset card.

Fan-out: ran — 24 items, see Fan-out

Dup-scan: no candidates at or above threshold 12

Post-merge scan: PM-1 already sits under Post-merge checks. No AC needed moving.

Sizing: opus

<details>
<summary>Intake evidence: knowledge source and fan-out</summary>

## Knowledge source

Knowledge source: none declared

## Fan-out

Refuter: cross (opus/fable alternating)
Lenses: lane-arm-fidelity opus 6/6 · blindness-leakage fable 6/6 · scoring-and-gate-decidability opus 6/6 · corpus-construction-and-ci fable 3/6 · premortem fable 3/6
Tally: rows added 7 · snapshot claims overturned 0 · questions added 3

| ID | Angle | Claim | Tag | Disposition |
| --- | --- | --- | --- | --- |
| F-1 | lane-arm-fidelity | The shipped `lane-review` arm carries only the correctness block (`arms/lane-review.md:6-15`) | already-had | became D-2 |
| F-2 | lane-arm-fidelity | The real prompt and scheduler input render offline from extracted functions (`run.sh:1000-1003`) | new | became D-15 |
| F-3 | lane-arm-fidelity | The rendered prompt needs a ticket, a PR and a posting path (`rules.md` blindness) | new | became D-2 and OR-3 |
| F-4 | lane-arm-fidelity | The scheduler's gates run before the review, not inside it (`run.sh:1824-1841`) | new | question: became D-4 and D-16 |
| F-5 | lane-arm-fidelity | The lane cannot block on P5 or on P1's untested AC (`run.sh:1107`) | already-had | became D-6 |
| F-6 | lane-arm-fidelity | `review-context.md` in the patch shows as a policy edit (`run.sh:996`) | new | became D-17 |
| F-7 | blindness-leakage | The scan misses ground truth inside the reviewed checkout (`bench.py` scan) | new | became D-3 and D-11 |
| F-8 | blindness-leakage | Bench checkouts expose `origin/*` refs and a revealing remote URL | new | became OR-3 |
| F-9 | blindness-leakage | The case id leaks into the scratch path and the session name (`rules.md`) | new | became D-18 |
| F-10 | blindness-leakage | The record needs its own first commit, or both record reads match (`run.sh:1094`) | already-had | became D-2 |
| F-11 | blindness-leakage | A second-shift checkout's settings grant `gh` inside the reviewer (`.claude/settings.json`) | not material | not material — the bases are upstream repos |
| F-12 | blindness-leakage | The base repo and where the answer key lives are unstated | already-had | became D-3 |
| F-13 | scoring-and-gate-decidability | The judge matches text only, with no location (`bench.py:256-308`) | already-had | became D-7 |
| F-14 | scoring-and-gate-decidability | P5 cannot score right under `[blocker]`-only scoring (`run.sh:1107`) | already-had | became D-6 |
| F-15 | scoring-and-gate-decidability | Several outcomes are unscored: violated rows, wrong-defect blockers, harm per class (`run.sh:1140`) | new | became D-6 and D-12 |
| F-16 | scoring-and-gate-decidability | The plain arm emits no severity or verdict (`rules.md`) | already-had | became D-5 |
| F-17 | scoring-and-gate-decidability | The bench voids any `gh` call, which the lane prompt needs (`bench.py` scan) | already-had | became OR-3 |
| F-18 | scoring-and-gate-decidability | At the minimums the gate passes equal arms about 9% of the time | new | question: became D-8 |
| F-19 | corpus-construction-and-ci | A vendored base tree is swept by five repo-wide scans (`tools/run-selftests.sh`) | already-had | became D-3 |
| F-20 | corpus-construction-and-ci | A pinned sha of this repo is unreadable in the shallow CI shards (`.github/workflows/ci.yml`) | new | became D-3 |
| F-21 | corpus-construction-and-ci | A vendored `plugin.json` would trip the frozen-file gate later (`check-frozen-files.sh`) | not material | not material — no vendored tree |
| F-22 | premortem | The shipped arm is a reconstruction labeled `src=installed` (`arms/lane-review.md`) | already-had | became D-2 |
| F-23 | premortem | The gate lacks power, and the corpus has no calibration data (`bench.py` calibrate) | new | question: became D-8 and D-7 |
| F-24 | premortem | P2 measures information access when only the lane has the record (`run.sh:1094`) | already-had | became D-1 |

### Snapshot

    # #1090 — explore-first snapshot (before the fan-out pool)

    Read at origin/main 759938a6 (#1108 merged).

    ## Facts

    - S-F1 The bench's shared output contract (`code-review-bench-eval/rules.md`) is a numbered list `1. path:line — the issue`, with no severity and no verdict. `bench.py` `parse_findings` keeps numbered items only, and `score()` counts any matched candidate whatever its severity.
    - S-F2 The merged lane prompt's correctness block (run.sh:1107) says a test-coverage or repo-convention problem is a `[note]` only. Its completeness block (run.sh:1103) says an AC with no test that proves it is a finding. The two disagree on P1's no-test variant; P5 can never be a `[blocker]` for the lane.
    - S-F3 `review_prompt()` needs a PR, `$RECORD_REL` at `$FIRST` and the head, `gh` for the ticket, `verdict-check.sh`, a PR comment, and `review_input()`'s scheduler input. The bench forbids `gh`, and its arm placeholders are `{rules},{checkout},{base},{head},{scratch},{out}` only.
    - S-F4 Lockstep anchors in `review_prompt()`: review-completeness (:1102), review-correctness (:1105), verdict-grammar (:1127), kb-contributions, verdict-style. The `lane-review` arm pairs only review-correctness.
    - S-F5 The bench clones large public forks by sha from GitHub; CI cannot do that cheaply. A vendored base under `evals/` meets repo-wide shellcheck, `jq empty`, the every-script-has-a-selftest rule and `check-eval-model-identity.sh`. This repo has no stored data ("No runtime service"), so P4 does not fit it.
    - S-F6 The judge (`bench.py:256-308`, `data/judge-prompt.md`) matches a candidate to a golden comment, and the calibration gate needs `data/calibration/` (Martian PRs only; 51/55 with Sonnet on the dev set).
    - S-F7 The bench's blindness: checkouts under `~/.cache`, transcripts scanned for the data dir.
    - S-F8 The right docs home is `docs/testing.md:728` "Benchmark tier", not :696 "Adversarial tier".
    - S-F9 #1108 is merged; the one-session lane review is what the lane runs.

    ## Questions (intent)

    - Q1 What the plain arm emits: the same verdict + `[blocker]`/`[note]` contract, or every item counts as a blocker.
    - Q2 How P5 and P1-no-test score, given the lane prompt makes conventions and coverage `[note]`s.
    - Q3 How the lane arm is reproduced offline: the lockstep blocks plus inlined ticket and record, or the full `review_prompt()` rendered by a runner.
    - Q4 The corpus's base: a synthetic repo shipped as a git bundle, this repo, or the bench's public forks.
    - Q5 What the plain arm is given: the ticket only, or the ticket and the record.
    - Q6 The matcher: the bench judge, a file:line window, or both; and how calibration applies.
    - Q7 The PM-1 gate's completeness clause (P2 is a free lane win if plain never sees the record).

</details>
