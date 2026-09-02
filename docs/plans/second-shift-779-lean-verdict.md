# lean review verdict — #779

verdict=approve
run_id: review-779-2
session_id: 9f7290c7-a94e-446b-a718-9f9c10bb3e06
rounds: 2
pr: #782
reviewed_head: 4557c856a70f6c5dcd2f02b25040a0da2aad261c
reviewed_patch_id: 8a855f1d0696c120a72078dbb9f16edf51ab17d4
inherited_patch_id: ceae5fcd5769001a32b7c68e35658e7b7e08fc17
inherited_from_verdict: 13de9ff86428c941c3eccd117800909bd3e66573
fidelity: not-applicable
panel: review-toolkit:scope-completeness-reviewer,review-toolkit:unit-test-mutation-reviewer
model: opus
capabilities: pr-marker

Round 2, inheriting round. Delta range `13de9ff8..HEAD` (2 files: the selftest and the mutation
baseline), reviewed from the lane worktree with the branch checked out; the tool itself is
byte-identical to round 1, so its coverage is inherited by reference to patch `ceae5fcd5769`.
The panel was dispatched over the full branch range rather than the delta, because scope and
mutation review both need the tool, which the delta does not contain. Panel 2 of 2, none dark.
Fidelity `not-applicable`: the spec declares no `## Design` section and the repo configures no
design provider.

**Verdict: approve — both round-1 blockers are fixed and measured fixed, no new blockers.**

## AC scorecard

| AC-n | score | evidence |
| --- | --- | --- |
| AC-1 | satisfied | Inherited: `tools/classify-capture.sh` is unchanged in this delta, so round 1's reading of the per-line scan keyed on `.type == "result"` stands. Re-confirmed live at this head — the suite's 11 cases all exercise the tool end to end and pass. |
| AC-2 | satisfied | Three verdicts at distinct exit codes, each printing a naming line, unchanged from round 1. Strengthened this round: cases (j) and (k) now assert the verdict word as well as the code. Measured at this head — renaming the `COMPLETE` banner fails 2 cases, renaming `FAILED` fails 2 cases; under round 1's suite both survived. |
| AC-3 | satisfied | The rc-3 family is now message-guarded, which is what round 1 found missing. Measured at this head: `die` rewritten to a constant wrong string fails (f)(g)(h); `die` rewritten to emit nothing fails (f)(g)(h). Both mutants left round 1's suite fully green. A third probe, `die` always emitting case (g)'s message, fails (f) and (h) only — so the assertions discriminate within the rc-3 family, not merely detect that some message was printed. |
| AC-4 | satisfied | `tail -n 1` over the collected result lines still makes the last event govern, and the count note still fires only above one. Cases (i) and (j) unchanged in substance; (j) gained its `COMPLETE` assertion this round. |
| AC-5 | satisfied | Round 1's blocker, resolved. This AC's closing sentence — "Each case asserts both the exit code and that the printed line names the verdict" — now holds for all 11 cases, not only the 5 that were flagged: enumerated at lines 39, 50, 61, 73, 85, 97, 109, 119, 132, 145, 157, every one of which is an `rc` comparison conjoined with at least one `grep -qF` against the captured output. The 5 changed cases were verified by execution as above; the other 6 already conformed. `run()` truncates its capture file per invocation and folds stderr into it, so no assertion can pass on a previous case's output. |
| AC-6 | satisfied | Cited from CI at this exact head `4557c856`, not re-run, per the review-side citation rule: run 33628672928 has `lint-and-selftests` success, `selftests (macos, bash 3.2)` success, and `mutation-sweep-pr` success. Glob discovery confirmed in the macos job log — `pass 1s tools/classify-capture-selftest.sh` followed by `all checks passed` — with no registration anywhere. `shellcheck -e SC1091,SC2015,SC2181` is clean on both files locally. |

## Findings

| # | Severity | Location | Finding |
| --- | --- | --- | --- |
| R1-B1 | Resolved | `tools/mutation-baseline.tsv:147` | Round-1 blocker cleared. `mutation-sweep-pr` is green at this head. The sweep still reports `applied=8 killed=7 survived=1` with the same survivor id, so the row accepts a survivor rather than hiding a kill — which is the correct remedy for this class. The row's justification was verified rather than taken on trust: the `default` operator at `tools/mutation-operators.tsv:56` rewrites the fallback VALUE in place, and `run_killer` at `tools/mutation-sweep.sh:1468` runs every paired suite with `TMPDIR` pointed at its own scratch dir. Measured both directions at this head: with `TMPDIR` set the mutant survives, with `TMPDIR` unset it is killed by 9 of 11 cases. The site is genuinely unobservable under the harness, not under-tested. Row shape matches all 131 existing rows (2 tab-separated columns) and sorts correctly. |
| R1-B2 | Resolved | `tools/classify-capture-selftest.sh:97` | Round-1 blocker cleared, and verified by execution rather than by reading the diff — see the AC-3 and AC-5 rows. The fix also went past what was asked: the assertion strings are literal substrings of the production messages, so they discriminate between the three rc-3 causes rather than merely proving that something was printed. |
| W1 | Warning | `tools/classify-capture.sh:52` | Inherited, unchanged, still open. A session killed mid-write leaves a partial final JSON object, which exits 3 as unreadable rather than 2 as truncated. AC-3 mandates exactly that, so the diff is right and this is not a blocker; what it costs is the remedy split AC-2 was written for, since re-run gets reported as investigate. Worth a follow-up ticket, not a change here. |
| W2 | Warning | `tools/classify-capture.sh:69` | Inherited, and RE-MEASURED at this head against the strengthened suite rather than carried on round 1's word: flipping the `subtype` fallback to `success` still leaves the suite 11 of 11 green. A result event carrying no `subtype` key remains unguarded, where case (k) covers the analogous `is_error` gap. Not an AC-5 enumerated case. |
| W3 | Warning | `tools/classify-capture.sh:64` | Inherited, re-measured at this head: relaxing the multi-result note threshold from above-one to above-zero still survives, printing a spurious note on every ordinary capture. No case asserts the note is absent on a single-result capture. |
| W4 | Warning | `tools/classify-capture.sh:40` | Inherited, re-measured at this head: relaxing the argument check from exactly-one to at-least-one still survives, so a silently ignored second argument is unguarded. The generic sweep kills the exactly-one check only in the not-equal direction. |
| S1 | Suggestion | `tools/classify-capture.sh:53` | Inherited. A bare JSON scalar line leaks a raw `jq` error to stderr before being treated as a non-result line; the verdict is still correct. Suppressing stderr on the type read, as the validity check already does, closes it. |
| S2 | Suggestion | `tools/classify-capture.sh:52` | Inherited. A line containing literal `null` is reported as not-valid-JSON when it is valid JSON, because `jq -e` exits 1 on a null result. Harmless for real stream-json, but the message misdescribes its own input. |

## Strengths

- The fix is wider than the finding. Round 1 named 5 cases; the result is that all 11 now assert
  the printed line, so the AC's closing sentence holds as written rather than at the 5 points
  where its absence had been demonstrated.
- The assertion strings were chosen to discriminate, not merely to exist. Asserting `absent or
  unreadable` / `not valid JSON` / `usage:` separately is what makes the rc-3 family's three
  causes distinguishable; a single shared `[classify-capture]` prefix would have passed the same
  review sentence and killed none of the three mutants that now die.
- The baseline row states a checkable mechanism and cites the function that implements it
  (`run_killer` setting `TMPDIR`), which is what let this round verify it in two directions in
  under a minute instead of taking the classification on trust.
- The five converted cases were moved onto the `if/else` form the file's first five cases already
  used, so the suite reads uniformly rather than carrying two assertion idioms.

## Panel

- `review-toolkit:scope-completeness-reviewer` — approve, 0 findings.
- `review-toolkit:unit-test-mutation-reviewer` — approve, 0 defects. Its three returned entries
  are fix-verification confirmations at confidence 85 to 92, each independently tracing the new
  assertion strings to the production messages and the baseline row to its sibling rows. Treated
  as corroboration, not as findings.
- Lead pass covered performance, maintainability, complexity, test coverage and security, and
  found nothing at or above the confidence threshold. The delta adds `grep` calls to a suite that
  runs in 1s and one TSV row, so the performance and complexity dimensions have no surface.
- `security-reviewer` not selected: the delta is a test file and a data row, with no auth,
  tenancy, session, upload or external-input query surface, and the repo carries no
  `review-context/security-reviewer.md`. The lead pass owns the security dimension this round.
- `a11y-reviewer` and the design-fidelity dimension not routed: no changed path matches
  `stageParams.webComponentGlobs`, which resolves to the shipped default `apps/web/**` since the
  repo declares none.

## Merge-boundary state, recorded not scored

`pr-gates` fails at the lean chain reconciliation step only, and the log names the reason exactly:
the committed record still read `verdict=needs-work` from round 1, so freshness is undefined and
the downstream arms are not evaluated. That is the expected pre-approve state of that lane and
resolves when this record lands. Every other arm of that job is green, the frozen-files and
changelog-trailer guards included. All three correctness lanes are green at this head.

## Probe method

All mutants were applied in a throwaway worktree detached at `4557c856`, inside the repo, one at a
time with a restore between and a diff check after each restore. Baseline was confirmed green
first. The reviewed lane worktree was never modified and is clean.
