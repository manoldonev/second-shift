# Decision record — #1115 The planted corpus mis-scores reviews: dropped-test matching, an unclean control and a saturated P1

Receipt: v4

## Summary

The planted corpus and its scorer get fixed so that a rerun measures review quality. Path-level truth locations let the judge see path-only and pathless blockers on the two dropped-test cases. Every control is audited, and d4p7sx is replaced. Four new P1 cases unsaturate P1, and each review session's stdout and stderr are saved under its run directory.

Open regions: OR-1 the hunk rule stays ranged-only. OR-2 a path-level location uses `side: head`. OR-3 a replaced control gets a fresh id. OR-4 only review sessions save output.

Provenance legend: `user-answered` = the operator chose. `codebase-derived` = a fact from the code or the docs, with its proof. `deferred` = not decided yet, under an open region.

Open region legend: `reversible-default-and-flag` = the build uses the stated default.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Which cases are dropped-test plants | b6r1vy and h9x3cd. g7s3hq deletes an assertion (P3) and is not one. run: `grep -l 'is not in the change' planted/cases/*/case.json` → b6r1vy h9x3cd | codebase-derived | fact |
| D-2 | How a path-level truth location matches | A location `{file, side}` with no start or end matches any blocker on that file, with or without a line. h9x3cd's `test/unit/utils/utils.js` 25–43 range becomes path-level. b6r1vy gains a path-level `test/plugin/updateLocale.test.js`. Ranged locations keep ±WINDOW. | user-answered | intent |
| D-3 | Blockers that name no file | On a case whose truth has a path-level location, a blocker with no parsed path also goes to the judge. The judge still decides. A case with only ranged locations is unchanged. | user-answered | intent |
| D-4 | How a path with no line is parsed | A `path:line` anywhere on the finding's first line wins, as today. Only without one, take the first token holding a `/` and a file extension. Strip backticks and a trailing `.,:;)` from it. `and/or` and `test/` parse no path. | user-answered | intent |
| D-5 | d4p7sx: replace or fix | Replace it with a control from a merged upstream PR. A hand-patched fix would stop being the upstream code. corpus-selftest's d4p7sx mutations move to a surviving case. | user-answered | intent |
| D-6 | Which controls the audit covers | Every control: l9r4qj, o6z3fl, u1c9nb, k5e2hw and d4p7sx's replacement, on one standard. Choosing by which arm drew harm would bias the comparison. Each control confirmed unclean is replaced as D-5 replaces d4p7sx. The PR body records each verdict with its evidence. | user-answered | intent |
| D-7 | What makes a control unclean | A behavior defect that a command the build runs shows. Or a break of a convention the case's own `review-context.md` declares, because P5 defines that as a planted defect. | user-answered | intent |
| D-8 | Where new cases come from | Multi-SWE-bench instances on upstreams the corpus already has: dayjs, axios, express, darkreader and github-readme-stats. NOTICE and the docs' Multi-SWE-bench claim stay true. | user-answered | intent |
| D-9 | How the new P1 cases are made hard | Four new P1 cases, so P1 goes from 4 to 8. Each breaks an AC only where an unchanged caller meets the new code. Hardness comes by construction, and no build step probes a model. Choosing cases by plain's misses would bias the gate. | user-answered | intent |
| D-10 | The P1 and P4 boundary | A P1 truth names the AC it leaves unmet. A broken caller outside every AC is P4. No upstream stores data, so every new P1 case is a caller case. cited (convention): docs/testing.md:754-757 | codebase-derived | fact |
| D-11 | Where each plant's proof lives | In the PR body: the command that fails at head and its output. Case files cannot hold the proof, because `markers_in` rejects such words. `check` stays offline. | user-answered | intent |
| D-12 | Plain's P1 misses as an AC | Moved to PM-1, because only a model run shows it. The operator reads PM-1 off the post-merge baseline rerun. | user-answered | intent |
| D-13 | Where session output goes | Every review session writes `<work>/state/session.stdout` and `session.stderr`. A timed-out session keeps what it wrote before the kill. Every record, a timeout's included, carries both paths. render-selftest's fake claude tests it. | user-answered | intent |
| D-14 | Test intent exemptions | AC-5 and AC-8 are exempt. AC-5 is an audit verdict recorded in the PR body. AC-8 is doc prose. | user-answered | intent |
| D-15 | d4p7sx's regression | Real: year −5 renders as `00-5` under the case's `Utils.s(this.$y, 4, '0')`. run: `node -e "<padStart from dayjs cbe91fd src/utils.js>; padStart(-5,4,'0')"` → "00-5" | codebase-derived | fact |
| D-16 | Whether a control can be dropped | No. The corpus has exactly the minimum of 5 controls, so each removed control needs a replacement. run: `grep -c '"class": "control"' planted/cases/*/case.json \| grep -c ':1'` → 5, and `MIN_CONTROLS = 5` at planted.py:42 | codebase-derived | fact |
| D-17 | Text that goes stale | docs/testing.md lines 749 ("25 cases"), 760 (counts) and 775 (the path:line rule) change. corpus-selftest.sh:27 asserts the old count string. run: `grep -n '25 cases\|four cases per class\|path:line falls' docs/testing.md` → 749, 760, 775 | codebase-derived | fact |
| D-18 | verify on a path-level location | `cmd_verify` loops over `range(loc["start"], …)`, so a path-level location needs its own branch there. run: `grep -n 'range(loc\["start"\]' planted/planted.py` → 964 | codebase-derived | fact |
| D-19 | Why the dead sessions left nothing | The runner keeps stdout only for the envelope and drops stderr. A timeout returns before reading either. run: `grep -n 'stdout, _err' planted/planted.py` → 752 | codebase-derived | fact |
| D-20 | Baseline rows and the changelog | This PR does not touch `planted/changelog.md`. Only `planted.py run` appends to it. The cited baseline rows are on main. run: `git show origin/main:plugins/review-toolkit/evals/code-review-bench-eval/planted/changelog.md \| grep -c '^20'` → 3 | codebase-derived | fact |
| D-21 | Hunk rule with path-level locations | Parked under OR-1 (owner: the build, by its default) | deferred | open |
| D-22 | `side` on a file the patch never touches | Parked under OR-2 (owner: the build, by its default) | deferred | open |
| D-23 | The replacement control's id | Parked under OR-3 (owner: the build, by its default) | deferred | open |
| D-24 | Judge and calibration session output | Parked under OR-4 (owner: the build, by its default) | deferred | open |
| D-25 | How the audit reads a declared convention | A control breaks a convention when code or a test that the change adds breaks it. An existing test that the change edits keeps its existing form. So l9r4qj is unclean: its new `instanceof` test, a behavior Moment.js shares, does not compare with Moment.js. k5e2hw is clean: it edits two existing literal expectations. o6z3fl and u1c9nb are clean. Added in build: D-7 does not say whether an edited existing test counts. | user-delegated | intent |
| D-26 | The replacement controls | w9e4ra (dayjs-918, month names parse December) replaces d4p7sx. f6t2gy (dayjs-1209, a two-digit zone offset) replaces l9r4qj. Both test against Moment.js and match their issue. Rejected: dayjs-1307 (its issue is a timezone conversion that the fix does not show it solves), dayjs-1295 (an ISO fraction after a comma no longer matches REGEX_PARSE and falls back to `new Date`), dayjs-938 (`weekdays(true)` maps to undefined when a locale has no weekStart). Added in build: D-5 and D-6 name no instance. | user-delegated | intent |
| D-27 | The four new P1 cases | j7m5ux (dayjs-1010: the unchanged UTC branch of parseDate), r8b3kz (readme-stats-99: the unchanged fetchRepo query), n4d9sw (readme-stats-293: the unchanged top-langs endpoint), y2h6cv (readme-stats-2491: the unchanged top-langs endpoint). Each truth adds a path-level location on the unchanged caller. readme-stats-88 was dropped: its patch needs lines with trailing spaces, which this build cannot write. Added in build: D-8 and D-9 name no instance. | user-delegated | intent |
| D-28 | The proof commands of D-11 | Not run: `node` and `npm` are outside this build's allowlist. The PR body gives each command and the output that a reading of the code predicts, marked not run. `planted.py verify` ran and built every new case with no gate stop. Added in build: D-11 assumes the build can run the command. | user-delegated | intent |
| D-29 | How score-selftest sees a parsed path | `planted.py score` prints each record's parsed findings beside its score. The printed report does not change. Added in build: the score output carried no parsed path, and AC-3 needs one. | user-delegated | intent |

Options weighed:

- D-2: path-level matches any line, path-level matches only a lineless finding, or the file name anywhere in the text. The operator chose any line.
- D-3: judge pathless blockers on path-level cases, or leave them out. The operator chose to judge them.
- D-4: path:line first with a cleaned token, or the first `/` token taken literally. The operator chose path:line first, cleaned.
- D-5: replace d4p7sx, or fix its patch. The operator chose replace.
- D-6: every control, the controls either arm harmed, or l9r4qj and o6z3fl only. The operator chose every control.
- D-7: a shown defect or a declared convention, or a shown defect only. The operator chose both.
- D-8: Multi-SWE-bench on existing overlays, Multi-SWE-bench with a new upstream, or any merged PR. The operator chose existing overlays.
- D-9: by construction plus PM-1, a plain probe that keeps plain's misses, or construction plus a reported probe. The operator chose construction plus PM-1.
- D-11: the PR body, or a case.json field that verify runs. The operator chose the PR body.
- D-13: every session in `state/`, or failed sessions only. The operator chose every session.
- D-14: exempt AC-5 and AC-8, or exempt AC-8 only. The operator chose both.

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | Whether a path-level location counts toward the in-hunk rule | reversible-default-and-flag |
| OR-2 | The `side` value of a path-level location | reversible-default-and-flag |
| OR-3 | The id of a replacement control | reversible-default-and-flag |
| OR-4 | Output capture for judge and calibration sessions | reversible-default-and-flag |

- OR-1 default: a path-level location does not count. A case still needs one ranged location inside a hunk. The agent chose it. Reversing it is a one-line change in `check_case`.
- OR-2 default: `side: head`, checked only as `head|base`. The matcher ignores `side`. The agent chose it. Reversing it is a JSON edit.
- OR-3 default: a fresh six-character id. Results are keyed by case id, so a reused id would merge old and new results. The agent chose it. Reversing it is a rename.
- OR-4 default: only review sessions in `review_one` save output. Judge sessions have no `<work>/state`. The agent chose it. Reversing it adds a path in `bench.py`.

## Test intent

ACs: AC-1 AC-2 AC-3 AC-4 AC-5 AC-6 AC-7 AC-8

AC-1: corpus-selftest: `check` accepts a case with a path-level `{file, side}` location outside every hunk, and refuses a path-level location with no file
AC-2: score-selftest: on a path-level case the judge sees a path-only blocker, a blocker at a line outside every range on that file, and a pathless blocker; a ranged-only case does not judge a pathless blocker
AC-3: score-selftest: a first line opening `test/plugin/x.test.js —` parses that path with no line, a backticked path with a trailing comma parses clean, `and/or` parses no path, and a later `src/i.js:9` wins over an earlier bare path
AC-4: corpus-selftest: `check` passes with no case d4p7sx and reports control 5, and the selftest's mutations run on a surviving case
AC-5: exempt — an audit verdict is a judgment recorded with its evidence in the PR body; no test proves it
AC-6: corpus-selftest: `check` reports `P1 8`
AC-7: render-selftest: a fake claude's stdout and stderr land in `state/session.stdout` and `state/session.stderr` and the record names both; a fake that outlives `--reviewer-timeout-s` leaves the output it wrote before the kill
AC-8: exempt — docs/testing.md is prose; no test can prove it

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | `planted.py check` output line | decided (D-9) |
| S-2 | `planted.py verify` output on a path-level location | decided (D-18) |
| S-3 | Session output files under the run directory | decided (D-13) |
| S-4 | Record fields in `planted-results-<stamp>.json` | decided (D-13) |
| S-5 | Judge picks and scores on dropped-test cases | decided (D-2) |
| S-6 | docs/testing.md planted-mode section | decided (D-17) |
| S-7 | Control audit verdicts in the PR body | decided (D-6) |
| S-8 | `planted/changelog.md` rows | decided (D-20) |
| S-9 | The gate and the printed report | out-of-scope — the ticket's Out keeps the gate's rule, and the report format does not change. |

## Checks

- `bash plugins/review-toolkit/evals/code-review-bench-eval/planted/score-selftest.sh`
- `bash plugins/review-toolkit/evals/code-review-bench-eval/planted/corpus-selftest.sh`
- `bash plugins/review-toolkit/evals/code-review-bench-eval/planted/render-selftest.sh`
- `python3 -I plugins/review-toolkit/evals/code-review-bench-eval/planted/planted.py check`

## Intake steps

Requirements: the ticket body as written. spec-reviewer: needs-revision, with one blocker on the matcher. The interview resolved it and the other gaps. The operator approved an AC block and PM-1 on the ticket.

Split: not triggered. The four fixes serve one rerun, sit in one eval directory and fit one PR.

Explore: done. Read planted.py's parser, matcher, check, gate and runner, the selftests, the named cases, the dayjs overlay, the baseline results and the docs.

Fan-out: skipped — by the operator at the intake notice: no reason given

Dup-scan: no candidates at or above threshold 12

Post-merge scan: plain's P1 misses moved to PM-1 (D-12).

Sizing: opus

<details>
<summary>Intake evidence: knowledge source and fan-out</summary>

## Knowledge source

Knowledge source: none declared

## Fan-out

Fan-out: skipped — by the operator at the intake notice: no reason given

</details>
