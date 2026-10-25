# Decision record — #1122 The planted corpus needs P1 and gate-exercising cases, and no upstream above 40%

Receipt: v4

## Summary

The planted corpus gains four review-hard P1 cases and four more P1 runner cases. The runner cases exercise the lane's fails-without-the-change gate. Each runner case has correct code and a tagged test that never exercises the change, so the gate stops the lane on it. `build()` installs the runner's dependencies once per base, and `verify` accepts only the expected stop. `planted.py check` gains a 40% cap per upstream and a rule that each runner case's command is declared.

Open regions: OR-1 the build names the runner overlay. OR-2 the build names the `case.json` field for the expected stop. OR-3 runner cases use readme-stats bases on jest 29.

Provenance legend: `user-answered` = the operator chose. `codebase-derived` = a fact from the code or the docs, with its proof. `deferred` = not decided yet, under an open region.

Open region legend: `reversible-default-and-flag` = the build uses the stated default.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | What the gate does on a runner case | It stops the lane case. `case.json` declares the expected stop. `verify` passes a runner case only when the lane stops on fails-without-the-change for the planted test. A stop on plan coverage or on an environment error fails `verify`. | user-answered | intent |
| D-2 | The class of the runner cases | P1. The runner cases come on top of the four review-hard P1 cases, so this slice adds at least eight cases. | user-answered | intent |
| D-3 | Who installs the runner's dependencies | `build()`, for a case whose overlay declares testRunners. It runs `npm install --ignore-scripts` with network, once per upstream and base, cached beside the bare clones and copied into each checkout. It fails loudly when the runner binary is missing. CI's model-free selftests never install. | user-answered | intent |
| D-4 | The runner format | `jest-json`. Plan tags name each test as `file::case`. | user-answered | intent |
| D-5 | Where a runner case gets its testRunners | A sibling runner overlay directory that only runner cases name. Existing overlays do not change, so no existing case runs the gate. | user-answered | intent |
| D-6 | The upstream of the runner cases | github-readme-stats, with jest. | user-answered | intent |
| D-7 | How the review-hard P1 cases are made hard | The unmet AC's site sits at least two hops from the diff, in a file the diff does not touch. Truth is ranged on the changed line and on the unmet site. | user-answered | intent |
| D-8 | What "the runner command is declared" checks | A runner case's overlay has a testRunners entry with a non-empty command and the `jest-json` format. Every AC-tagged test in the case's plan matches a `when` glob and names `file::case`. | user-answered | intent |
| D-9 | The headline goal | PM-1 on the ticket body. The cases are hard by construction. The build never probes the plain arm to choose them. | user-answered | intent |
| D-10 | The test of AC-4 | AC-4 is unchecked, because the real-upstream stop needs network and npm. render-selftest's synthetic runner proves offline that the install runs once per base, fails loudly without the runner, and that `verify` accepts only the expected stop. | user-answered | intent |
| D-11 | What a runner case plants | A vacuous test. The fix is complete and correct. The AC's tagged test never exercises the change. Truth is ranged on that test. | user-answered | intent |
| D-12 | Who runs `verify` on the real upstream | The operator, before the merge. The PR body names the exact `planted.py verify --case <ids>` command. A red result sends the PR back. The lane builds unattended. | user-answered | intent |
| D-13 | Rules this slice inherits from #1121 | #1121's D-1, D-2, D-3, D-4, D-9, D-10 and D-11 bind every case here. That covers the upstreams, the 80-line floor, the frozen ids, the checked distractions, the static proof, large real fixes and no record row for a distraction. | user-answered | intent |
| D-14 | Duplicate candidate #1121 | Not a duplicate. #1121 is this ticket's predecessor slice, and the operator's split sequenced it first. | user-answered | intent |
| D-15 | How a gate stop scores today | A lane gate stop scores right with no review read. `verify` exits 1 on any stopped lane case. run: `grep -n 'if review\["status"\] == "gate-stop"\|if b\["stopped"\]' planted.py` → 692, 1059 | codebase-derived | fact |
| D-16 | Whether `build()` installs anything today | No. run: `grep -c npm planted.py` → 0 | codebase-derived | fact |
| D-17 | A bare-file tag under a reporting format | run.sh reds it. run: `grep -n 'is a bare file, but' plugins/dev-pipeline/skills/run/run.sh` → 867 | codebase-derived | fact |
| D-18 | When the gate runs | Only after plan coverage passes. A runner case's plan must pass coverage first. run: `grep -n 'pc" -eq 0' lane-render.sh` → 34 | codebase-derived | fact |
| D-19 | Where the 40% cap lives | In `check_corpus`, keyed on `case.json` `upstream`, as every corpus rule is. dayjs holds 16 of 35 cases after #1121. This slice's eight cases bring it to 16 of 43. run: `grep -n '^def check_corpus' planted.py; jq -r .upstream cases/*/case.json \| grep -c dayjs; ls cases \| wc -l` → 365, 16, 35 | codebase-derived | fact |
| D-20 | The readme-stats share | readme-stats holds 6 cases after #1121. The four runner cases add four more. The cap check rejects any upstream above 40% of the corpus. run: `jq -r .upstream cases/*/case.json \| grep -c readme` → 6 | codebase-derived | fact |
| D-21 | The runner at the newest readme-stats base | jest ^29.7.0. run: `gh api -H 'Accept: application/vnd.github.raw' "repos/anuraghazra/github-readme-stats/contents/package.json?ref=9c6eb228" \| jq -r .devDependencies.jest` → ^29.7.0 | codebase-derived | fact |
| D-22 | Text that goes stale | corpus-selftest.sh:28 pins the class counts and the P4 pattern counts. docs/testing.md:749 says 35 cases, and :760 gives the class counts. run: `grep -n 'check: ok (P1' corpus-selftest.sh; grep -n '35 cases\|eight P1 cases' docs/testing.md` → 28, 749, 760 | codebase-derived | fact |
| D-23 | The runner overlay's name | Parked under OR-1 (owner: the build, by its default) | deferred | open |
| D-24 | The `case.json` field for the expected stop | Parked under OR-2 (owner: the build, by its default) | deferred | open |
| D-25 | The node version for older jest bases | Parked under OR-3 (owner: the build, by its default) | deferred | open |

Options weighed:

- D-1: stop with `verify` expecting it, or run and pass. The operator chose stop.
- D-2: P1 on top of the four, P1 counted among the four, or P4 allowed. The operator chose P1 on top.
- D-3: `build()` installs with a cache, or the operator pre-provisions. The operator chose `build()`.
- D-4: `jest-json` with `verify` checking the reason, or `exit` with bare files. The operator chose `jest-json`.
- D-5: a runner overlay directory, or a per-case config override. The operator chose the overlay directory.
- D-6: readme-stats with jest, vuejs/core with vitest, or a mix. The operator chose readme-stats.
- D-7: two hops in an untouched file, or size and distraction only. The operator chose two hops.
- D-8: command, globs and tags, or a non-empty command only. The operator chose command, globs and tags.
- D-9: a post-merge check, or none. The operator chose PM-1.
- D-10: unchecked with synthetic selftests, or a behavior test. The operator chose unchecked.
- D-11: a vacuous test with correct code, or an unmet AC with a weak test. The operator chose the vacuous test.
- D-12: the operator runs `verify` before merge, or an interactive build. The operator chose the operator's run.

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | The runner overlay's name | reversible-default-and-flag |
| OR-2 | The `case.json` field for the expected stop | reversible-default-and-flag |
| OR-3 | The node version for older jest bases | reversible-default-and-flag |

- OR-1 default: `anuraghazra__github-readme-stats-jest`. The build chose it. Reversing it is a directory rename and four `case.json` edits.
- OR-2 default: `expect_stop: "fails_without_change"`. The build chose it. Reversing it is a rename in `planted.py` and four cases.
- OR-3 default: runner cases use readme-stats bases on jest 29, which needs node 18 or later, under the machine's node. The build chose it. Reversing it means picking other bases.

## Test intent

ACs: AC-1 AC-2 AC-3 AC-4 AC-5

AC-1: `planted.py check` on the shipped corpus counts the four new review-hard P1 cases, and corpus-selftest asserts the new class counts
AC-2: a copy whose new P1 case is cut below 80 changed lines, or loses its distraction, fails naming the case
AC-3: a copy in which one upstream holds more than 40% of the cases fails naming the upstream and its share, and the shipped corpus passes
AC-4: unchecked — the real-upstream gate stop needs network and npm through `planted.py verify`, which the operator runs before the merge
AC-5: a copy whose runner overlay drops the command, uses a format other than `jest-json`, or whose plan tags a bare file or an unmatched path fails naming the case

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | `planted.py check` output and its new messages | decided (D-8) |
| S-2 | `corpus-selftest.sh` output | decided (D-22) |
| S-3 | `planted.py verify` output for runner cases | decided (D-1) |
| S-4 | `render-selftest.sh` output | decided (D-10) |
| S-5 | docs/testing.md, the planted mode section | decided (D-22) |
| S-6 | The runner overlay directory | decided (D-5) |
| S-7 | The install cache beside the bare clones | decided (D-3) |
| S-8 | The PR body: the verify command and the proofs | decided (D-12) |
| S-9 | The lane and plain review prompts | out-of-scope — the render code does not change, and a stopped case renders no prompt. |
| S-10 | `planted/changelog.md` | out-of-scope — only `planted.py run` appends rows, and the rerun is the operator's. |
| S-11 | The scorer's output | out-of-scope — the ticket's Out excludes the scorer, so a gate stop scores as today. |

## Checks

- `bash plugins/review-toolkit/evals/code-review-bench-eval/planted/corpus-selftest.sh`
- `bash plugins/review-toolkit/evals/code-review-bench-eval/planted/render-selftest.sh`
- `python3 plugins/review-toolkit/evals/code-review-bench-eval/planted/planted.py check`

## Intake steps

Requirements: the parent #1119 as written. spec-reviewer found three blockers and nine gaps. The operator closed each one in the interview. The slice body restates the parent's ask.

Split: split into #1121 and #1122 (sequential) on the operator's yes. This receipt is for #1122.

Explore: done. Read planted.py, corpus-selftest.sh, render-selftest.sh, lane-render.sh, run.sh's fails_without_change, docs/testing.md and the Multi-SWE-bench index.

Fan-out: ran once for the #1119 split — 22 items touch this slice.

Dup-scan: one candidate, #1121, the predecessor slice. It is not a duplicate (D-14).

Post-merge scan: no AC moved. PM-1 was added on the operator's answer (D-9).

Sizing: opus

<details>
<summary>Intake evidence: knowledge source and fan-out</summary>

## Knowledge source

Knowledge source: none declared

## Fan-out

Run: shared with the #1119 split — slices #1121, #1122
Refuter: cross (opus/fable alternating)
Lenses: harness-contract-fit opus 6/6 · gate-execution-path fable 6/6 · pattern-fidelity-and-sourcing opus 6/6 · selftest-and-slice-seam fable 6/6 · premortem fable 3/6
Tally: rows added 2 · snapshot claims overturned 2 · questions added 2

| ID | Angle | Claim | Tag | Disposition |
| --- | --- | --- | --- | --- |
| F-3 | harness-contract-fit | testRunners live on the overlay, and a free-string overlay name passes `check` (`planted.py:213`). | already-had | became D-5 |
| F-4 | harness-contract-fit | A lane gate stop scores right, and `verify` exits 1 on it (`planted.py:628`, `:994`). | already-had | became D-1 and D-15 |
| F-5 | harness-contract-fit | dayjs holds 16 of 29 cases, and the cap needs at least 11 new cases outside dayjs. | already-had | became D-19 |
| F-6 | harness-contract-fit | The 80-line rule does not say what counts (`corpus-selftest.sh:27`). | already-had | settled by #1121, cited in D-13 |
| F-7 | gate-execution-path | The recipe never installs dependencies, and run.sh's setup lanes are not extracted (`planted.py:363`). | already-had | became D-3 |
| F-8 | gate-execution-path | No pinned base declares vitest, and jest sits on dayjs, readme-stats and darkreader only. | already-had | became D-6 |
| F-9 | gate-execution-path | An offline install works only from a warm npm cache, and most bases have no lockfile. | new | became D-3 |
| F-10 | gate-execution-path | jest 22 under node 24 writes the jest-json report shape run.sh reads (`run.sh:699`). | new | became D-4 |
| F-11 | gate-execution-path | Every plan tags bare files, and run.sh reds them under a reporting format (`run.sh:867`). | already-had | became D-8 and D-17 |
| F-12 | gate-execution-path | Two overlays name npm scripts their bases lack (`overlays/axios__axios/config.json`). | not material | not material — no existing overlay runs; named for the operator |
| F-13 | pattern-fidelity-and-sourcing | The cap holds only once both slices land. | already-had | became D-19 |
| F-14 | pattern-fidelity-and-sourcing | vuejs/core has 48 unused instances under MIT. | overturned (snapshot: "svelte/mui/vue datasets are LFS pointers; git-lfs is not installed") | settled by #1121, cited in D-13 |
| F-15 | pattern-fidelity-and-sourcing | vuejs/core runs vitest with pnpm at its bases. | overturned (snapshot: "No vitest upstream") | weighed in D-6 |
| F-17 | pattern-fidelity-and-sourcing | Four of eight P1 cases already show the unmet AC outside the diff, and plain got all of them (`cases/*/case.json`). | new | became D-7 |
| F-18 | pattern-fidelity-and-sourcing | Only readme-stats and one axios instance remain outside dayjs without reuse (`planted.py:201`). | new | settled by #1121, cited in D-13 |
| F-19 | selftest-and-slice-seam | Each slice rewrites the pinned count string, and MIN_PER_CLASS is one constant (`planted.py:42`). | already-had | became D-22 |
| F-20 | selftest-and-slice-seam | With `parse_patch` outside the plan, 4 of 29 cases reach 80 lines. | already-had | settled by #1121, cited in D-13 |
| F-21 | selftest-and-slice-seam | `check` accepts unknown `case.json` keys (`planted.py:195`). | new | became D-24 |
| F-22 | selftest-and-slice-seam | The cap holds only at 40 cases or with a dayjs case removed. | already-had | became D-19 |
| F-25 | premortem | A runner that cannot start passes under `exit` and reds under a reporting format. | new | became D-1 and D-4 |
| F-26 | premortem | The ask's minimum counts miss the 40% cap. | already-had | became D-19 |
| F-27 | premortem | A floor over every case reds 25 existing cases unless new cases are marked. | already-had | settled by #1121, cited in D-13 |

### Snapshot

    # Snapshot — #1119 split (#1121, #1122), plain intake register before the fan-out pool

    | ID | Decision | Resolution |
    | --- | --- | --- |
    | D-1 | Upstream pool for new cases | Non-dayjs unused Multi-SWE-bench instances: readme-stats ~15, axios 1 (5919), insomnia 1 (Apache-2.0, new overlay). express and darkreader are exhausted. svelte/mui/vue datasets are LFS pointers; git-lfs is not installed. Question: which upstreams, and how the 40% cap is met (readme-stats ends ~37.5%). |
    | D-2 | 40% arithmetic | dayjs 16/29 today; at 10 new non-dayjs cases 16/39 = 41%. Needs >= 11 new non-dayjs cases, or retired dayjs cases. Fact. |
    | D-3 | What the 80-line floor counts | Open: whole patch.diff (plan included, as the 7/23/110 figures do), or code+tests only. Each case, not aggregate. Question. |
    | D-4 | How the size check knows a case is new | Open: case.json field, id allowlist, or grandfather the 29 existing ids. 22 of 29 existing patches are under 80. Question. |
    | D-5 | Distraction recording | Open: truth.distractions[] with a location (reported apart), or critic-only. A blocker on it already counts as noise. Question. |
    | D-6 | P4 pattern coverage | Open: each of the four patterns at least once among the six. Question. |
    | D-7 | Stored-data pattern on upstreams with no store | No corpus upstream stores data (docs/testing.md:757). Question: in-memory analog acceptable (a whole options/config object passed back). |
    | D-8 | Truth locations for a two-hop caller | check_case needs one ranged location inside a hunk; others may sit in untouched files. Fact. Recommend the changed line plus the caller's line. |
    | D-9 | Hardness | By construction, not by probing plain (precedent #1115 D-9). Headline goal is a post-merge check on the rerun. Question (PM). |
    | D-10 | Plant proof | PR body, command + output (precedent #1115 D-11); markers_in bans proof words in case files. Fact/precedent. |
    | D-11 | Stale text | corpus-selftest.sh:27 count string; docs/testing.md:749, 757, 760-762; NOTICE per new upstream. Fact. |
    | D-12 | Runner config mechanism (#1122) | A new overlay directory per runner variant works with no build() change (overlay is a free-form dir, planted.py:213). Alternative: per-case config. Question. |
    | D-13 | Dependency install (#1122) | build() installs nothing. Need npm ci at build (network) or a cache, and a Node version per base (jest 22/26/27/29 across upstreams). Question. |
    | D-14 | Gate outcome on runner cases (#1122) | Stop (scored right for the lane, verify rc=1 today) vs run-and-pass. Passing-test shape fits P1. Question. |
    | D-15 | Runner format (#1122) | exit judges files; jest-json needs file::case tags. Question. |
    | D-16 | Who builds | A lane BUILD has no node/npm/curl (memory); runner proofs need node. Constraint for #1122, flag. |
    | D-17 | Jest upstreams | readme-stats (jest 26-29), darkreader (27), insomnia (29), dayjs (22). No vitest upstream. axios/express mocha. Fact. |

</details>
