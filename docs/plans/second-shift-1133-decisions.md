# Decision record — #1133 The planted corpus needs P4 cases a plain review gets wrong, selected on a plain pilot

Receipt: v4

## Summary

The planted corpus gains at least 32 pilot-only P4 candidates, 8 per pattern, each with its breaking caller outside the diff. `planted.py` gains a `PILOT` id set that keeps candidates out of the scored corpus, a plain-only `run --pilot`, and a model-free `cases` report. The selection and promotion of the candidates ship in #1135, after the operator's pilot run.

Open regions: OR-1 a `--case` on a pilot id without `--pilot` is an error. OR-2 `cases` leaves unscored records out of the rate. OR-3 `cases` reports per arm. OR-4 `cases` without ids rates every case. OR-5 an Apache upstream's NOTICE lines are copied. OR-6 the `run --pilot` logic is tested through helpers. OR-7 a new overlay copies the vuejs/core shape.

Provenance legend: `user-answered` = the operator chose. `codebase-derived` = a fact from the code or the docs, with its proof. `deferred` = not decided yet, under an open region.

Open region legend: `reversible-default-and-flag` = the build uses the stated default.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Scope of this ticket | The candidates and the pilot machinery. The selection and promotion ship in #1135, which the operator chose over one ticket with two PRs. | user-answered | intent |
| D-2 | How many candidates | At least 32, 8 per pattern. #1135 keeps a candidate plain misses at least 2 of its 3 pilot runs. | user-answered | intent |
| D-3 | How a candidate is marked | A `PILOT` frozenset in `planted.py`, like `FROZEN`. `check_case` applies every rule to a pilot case. A pilot case is left out of the class counts, the pattern counts, the 40% cap and a normal `run`. | user-answered | intent |
| D-4 | What `run --pilot` runs | The plain arm only, and it refuses `--arm lane`. `--rescore` honors `--pilot`, and the judge-failure message passes `--pilot` through. Neither path writes a changelog row. | user-answered | intent |
| D-5 | How per-case results are read | A model-free `planted.py cases <results.json>`: right, wrong and noise per case and run, and the right rate over a given set of case ids. | user-answered | intent |
| D-6 | Fields of a case from a merged PR outside Multi-SWE-bench | `instance` is `<owner>__<repo>-pr<N>`, `issue` the linked issue or else the PR number, and `pr` the PR. `check` accepts an `instance` in this form or the Multi-SWE-bench form, and nothing else. | user-answered | intent |
| D-7 | ticket.md for a PR with no linked issue | A user-visible problem statement written for the case, with no wording that names the fix, plus the AC block. NOTICE says ticket texts are the upstream issue's text or a problem statement written from the upstream PR. | user-answered | intent |
| D-8 | Where a plant sits | Where the changed hunk reads as correct on its own and the break shows only at the caller. The PR body argues it per case. | user-answered | intent |
| D-9 | How far the caller is from the diff | The breaking caller is in a file the patch does not touch, at least two calls from the changed code. `check` requires a non-frozen P4 case to carry a ranged truth location outside every hunk. The PR body argues the hop count. | user-answered | intent |
| D-10 | Where candidates come from | At most 12 from vuejs/core in Multi-SWE-bench. The rest come from at least two other large MIT or Apache TS/JS repositories, as merged PRs pinned by sha. | user-answered | intent |
| D-11 | The tests of AC-5 and AC-6 | AC-5 is tested through the `instance` rule of D-6. AC-6 is exempt: it says the tests exist, and the tests of AC-2 to AC-4 prove it. | user-answered | intent |
| D-12 | The reversal of "never probe plain" | #1121 D-8 and #1122 D-9 chose hardness by construction. This ticket's pilot reverses that on the operator's choice. The build itself still never runs plain. | user-answered | intent |
| D-13 | Rules carried from #1121 | #1121's D-2, D-3, D-4, D-5, D-7, D-9 and D-11 bind every candidate: the 80-line floor, frozen ids, checked distractions, pattern coverage, ranged truth, the static proof, and no record row for a distraction. No Multi-SWE-bench instance is reused. | user-answered | intent |
| D-14 | Why the pilot cannot start today | `run` checks the whole corpus before `--case` filters it. run: `grep -n 'problems, _, _ = check_corpus(root)\|if args.case:' planted.py` → 1007, 1025 | codebase-derived | fact |
| D-15 | Rescoring a deleted candidate | Scoring looks every record's case up by id, so a dropped candidate's results cannot be re-judged. run: `grep -n 'cases\[r\["case"\]\]' planted.py` → 842, 881, 1155 | codebase-derived | fact |
| D-16 | Licenses a new upstream may carry | MIT, BSD-2-Clause, BSD-3-Clause, Apache-2.0 and ISC. run: `grep -n '^LICENSES' planted.py` → 46 | codebase-derived | fact |
| D-17 | Text that goes stale | corpus-selftest.sh:31 pins the check output, and the planted.py docstring lists the subcommands at :11. Pilot cases leave the pinned counts unchanged. run: `grep -n 'check: ok (P1' corpus-selftest.sh; grep -n '^Subcommands' planted.py` → 31, 11 | codebase-derived | fact |
| D-18 | vuejs/core's share today | 4 of 43 cases. run: `jq -r .upstream cases/*/case.json \| grep -c vuejs; ls cases \| wc -l` → 4, 43 | codebase-derived | fact |
| D-19 | A `--case` on a pilot id without `--pilot` | Parked under OR-1 (owner: the build, by its default) | deferred | open |
| D-20 | Unscored records in `cases` | Parked under OR-2 (owner: the build, by its default) | deferred | open |
| D-21 | Arms in `cases` | Parked under OR-3 (owner: the build, by its default) | deferred | open |
| D-22 | `cases` with no ids | Parked under OR-4 (owner: the build, by its default) | deferred | open |
| D-23 | NOTICE for an Apache-2.0 upstream | Parked under OR-5 (owner: the build, by its default) | deferred | open |
| D-24 | The test seam of `run --pilot` | Parked under OR-6 (owner: the build, by its default) | deferred | open |
| D-25 | The overlay of a new upstream | Parked under OR-7 (owner: the build, by its default) | deferred | open |

Options weighed:

- D-1: one ticket with an interactive build, a successor ticket, or a hand-built selection PR. The operator chose the successor ticket.
- D-2: 32 with at least 2 misses, 24 with at least 1, or 16 with at least 1. The operator chose 32 with at least 2.
- D-3: a `PILOT` id list, or a `pilot: true` field. The operator chose the id list.
- D-4: plain only and rescorable, or any arms. The operator chose plain only.
- D-5: a `cases` subcommand, or jq. The operator chose the subcommand.
- D-6: the PR as source with no new field, or a `source` field. The operator chose the PR as source.
- D-7: a written problem statement, or the PR description. The operator chose the written statement.
- D-8: a build rule argued in the PR, or the pilot alone. The operator chose the build rule.
- D-9: outside the diff and two hops, outside the diff only, or as before. The operator chose two hops.
- D-10: at most 12 from vuejs/core, or any split. The operator chose at most 12.
- D-11: AC-5 tested and AC-6 exempt, or both exempt. The operator chose AC-5 tested.

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | A `--case` on a pilot id without `--pilot` | reversible-default-and-flag |
| OR-2 | Unscored records in `cases` | reversible-default-and-flag |
| OR-3 | Arms in `cases` | reversible-default-and-flag |
| OR-4 | `cases` with no ids | reversible-default-and-flag |
| OR-5 | NOTICE for an Apache-2.0 upstream | reversible-default-and-flag |
| OR-6 | The test seam of `run --pilot` | reversible-default-and-flag |
| OR-7 | The overlay of a new upstream | reversible-default-and-flag |

- OR-1 default: an error that names `--pilot`. The build chose it. Reversing it is one branch in `run_recipe`.
- OR-2 default: an unscorable, timed-out or unjudged record leaves the denominator, as `tally` does, and the report counts it apart. The build chose it. Reversing it is one line.
- OR-3 default: per arm, never pooled. The build chose it. Reversing it is a grouping change.
- OR-4 default: the per-case lines, plus a rate over every case in the file. The build chose it. Reversing it is one default.
- OR-5 default: the upstream's NOTICE attribution lines are copied under its entry in `planted/NOTICE`. The build chose it. Reversing it is a text edit.
- OR-6 default: the case selection and the record decision are helpers that score-selftest calls directly. `run_recipe` itself stays untested, since it needs a model. The build chose it. Reversing it is a test refactor.
- OR-7 default: the shape of `overlays/vuejs__core/`, with no testRunners. The build chose it. Reversing it is one file per overlay.

## Test intent

ACs: AC-1 AC-2 AC-3 AC-4 AC-5 AC-6

AC-1: `planted.py check` on the shipped corpus reports at least 32 pilot cases, 8 per pattern, and a copy whose pilot P4 case has no ranged truth location outside every hunk fails naming the case
AC-2: a copy whose pilot case breaks a case rule fails naming it, and with the pilot cases present the pinned class, pattern and cap counts are unchanged
AC-3: the pilot case selection returns only pilot ids and refuses the lane arm, and the record decision writes no changelog row on a pilot run or a pilot rescore
AC-4: `planted.py cases` on a canned results file prints each case's right, wrong and noise per run and arm, and the right rate over a given id set
AC-5: a case whose `instance` is `<owner>__<repo>-pr<N>` passes `check`, and an `instance` in neither form fails
AC-6: exempt — it states that the tests exist, and the tests of AC-2 to AC-4 prove it

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | `planted.py check` output with pilot cases | decided (D-3) |
| S-2 | `corpus-selftest.sh` output | decided (D-17) |
| S-3 | `run --pilot` output and refusals | decided (D-4) |
| S-4 | The `planted.py cases` report | decided (D-5) |
| S-5 | NOTICE and the new overlays | decided (D-7) |
| S-6 | The PR body's per-case arguments | decided (D-9) |
| S-7 | `planted/changelog.md` | out-of-scope — a pilot writes no row, and the scored rows are #1135's. |
| S-8 | The lane and plain review prompts | out-of-scope — the render code does not change. |

## Checks

- `bash plugins/review-toolkit/evals/code-review-bench-eval/planted/corpus-selftest.sh`
- `bash plugins/review-toolkit/evals/code-review-bench-eval/planted/score-selftest.sh`
- `python3 plugins/review-toolkit/evals/code-review-bench-eval/planted/planted.py check`

## Intake steps

Requirements: the ticket as filed. spec-reviewer found three blockers and nine warnings. The interview closed them, and #1132's merge closed one. A misattributed figure was fixed in the body.

Split: the operator first declined a split, then moved the selection into its own ticket, #1135. This receipt is for #1133.

Explore: done. Read planted.py's check, run and rescore paths, NOTICE, the overlays and the two results files.

Fan-out: ran — 21 items, see Fan-out

Dup-scan: no candidates at or above threshold 12

Post-merge scan: no AC moved. The headline PM-1 lives on #1135.

Sizing: opus

<details>
<summary>Intake evidence: knowledge source and fan-out</summary>

## Knowledge source

Knowledge source: none declared

## Fan-out

Refuter: cross (opus/fable alternating)
Lenses: selection-statistics opus 4/6 · pilot-exclusion-contract fable 4/6 · provenance-and-sourcing opus 6/6 · hardness-for-the-wrong-reason fable 5/6 · premortem fable 2/6
Tally: rows added 3 · snapshot claims overturned 0 · questions added 4

| ID | Angle | Claim | Tag | Disposition |
| --- | --- | --- | --- | --- |
| F-1 | selection-statistics | A P4 run is right on one matched blocker near any truth location (`planted.py:777-833`). | new | informed D-9 |
| F-2 | selection-statistics | Plain's P4 variation sits in one case; keeping on one miss keeps 1 of 10. | new | became D-2 |
| F-3 | selection-statistics | Across classes the keep rate is 24-29%, so 16 candidates yield 4-5. | new | became D-2 |
| F-4 | selection-statistics | Sixteen candidates reach PM-1 only if about 60% are hard (simulation). | new | became D-2 |
| F-5 | pilot-exclusion-contract | `run` checks the whole corpus before `--case` filters (`planted.py:1007`). | already-had | became D-14 |
| F-6 | pilot-exclusion-contract | Rescoring a record whose case is gone crashes with KeyError (`planted.py:842`). | new | became D-15 |
| F-7 | pilot-exclusion-contract | corpus-selftest pins check output and cap denominators (`corpus-selftest.sh:31`). | already-had | became D-17 |
| F-8 | pilot-exclusion-contract | A case.json or planted.py marker never reaches the reviewer; an id or directory marker does. | new | informed D-3 |
| F-9 | provenance-and-sourcing | `instance` is only a label; nothing else reads it (`planted.py:315`). | new | became D-6 |
| F-10 | provenance-and-sourcing | `issue` fixes the plan and record paths (`planted.py:123`). | new | became D-6 |
| F-11 | provenance-and-sourcing | ticket.md is hand-written, and NOTICE says every ticket is upstream issue text. | new | became D-7 |
| F-12 | provenance-and-sourcing | License and NOTICE are checked for presence, never for agreement. | not material | not material — no MIT/Apache mismatch is planned |
| F-13 | provenance-and-sourcing | The cap allows up to 22 more vuejs/core cases. | already-had | became D-10 |
| F-14 | provenance-and-sourcing | The only precedent for marking cases is `FROZEN`, an id list. | already-had | became D-3 |
| F-15 | hardness-for-the-wrong-reason | Identical plain findings flipped between judgings on 9 P4 case-runs. | new | carried to #1135 AC-1 |
| F-16 | hardness-for-the-wrong-reason | Plain wins by reading the hunk; the caller is one grep away. | new | became D-8 |
| F-17 | hardness-for-the-wrong-reason | Plain runs far below its turn and time ceilings on P4. | not material | not material — no timeout artifact today |
| F-18 | hardness-for-the-wrong-reason | Two location spellings of a correct finding are never judged. | new | carried to #1135 AC-1 |
| F-19 | hardness-for-the-wrong-reason | Three scorer shapes could each be called a plain miss. | already-had | carried to #1135 AC-1 |
| F-20 | premortem | Nothing marks a pilot case, and a plain-only run appends a row. | already-had | became D-3 and D-4 |
| F-21 | premortem | No row or report shows per-case results. | new | became D-5 |

### Snapshot

    # Snapshot — #1133, plain intake register before the fan-out pool
    
    | ID | Decision | Resolution |
    | --- | --- | --- |
    | D-1 | How the second PR is carried (not split) | Open. The lane builds PR 1 and closes the ticket on merge; the selection PR needs a home. Question. |
    | D-2 | Pilot-only mark | Open: a case.json field (`pilot: true`) or a separate `candidates/` directory. Question: does it skip check_case or only the counts, the cap and run? #1121 D-3 says no field lets a case opt out of the size floor. |
    | D-3 | How the pilot reaches the candidates | Open: a `run --pilot` flag that loads only pilot cases. run_recipe today loads every case, with `--case` the only filter. Question. |
    | D-4 | What "missed" means | Open: not right (incl. needs-work on noise), or wrong (an approve). Unscorable runs? Question. |
    | D-5 | Pilot results to PR 2 | Open: the results file lives in ~/.cache; the PR 2 build needs per-candidate results. Question: issue comment vs a checked-in file. |
    | D-6 | Pilot changelog row | Open: `--no-record`, or a recorded row with a note. Question. |
    | D-7 | Pattern spread | Open: at least 4 candidates per pattern; at least 2 kept per pattern. Question. |
    | D-8 | Non-Multi-SWE-bench provenance | check_case needs non-empty instance, integer issue and pr (planted.py:315-322). NOTICE preamble says every case comes from Multi-SWE-bench. Question. |
    | D-9 | Instance reuse | #1121 D-1: no instance reused. vuejs/core uses 4 instances today. Fact + carry the rule. |
    | D-10 | PM-1 failure disposition | Open: what happens when held-out plain > 50%. Question. |
    | D-11 | Reversal of "never probe plain" | #1121 D-8 / #1122 D-9 said hard by construction, never probe plain. This ticket reverses it on the operator's choice; record the departure. Fact/record. |
    | D-12 | Stale text | corpus-selftest count string, docs/testing.md 749/760, FROZEN. Fact. |
    | D-13 | Dropped candidates | Open: delete, or keep pilot-only. Question. |

</details>
