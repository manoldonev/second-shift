# Decision record — #1121 The planted corpus needs hard P4 cases a plain review does not always catch

Receipt: v4

## Summary

The planted corpus gains at least six P4 cases built on large upstream fixes from github-readme-stats and vuejs/core. vuejs/core is a new upstream. Each case breaks a caller outside the obvious reach of the diff, in one of the four consumer-miss patterns. Each new case also carries one deliberate distraction, recorded in `case.json`. `planted.py check` gains a per-case size floor, a distraction rule and pattern coverage, and `corpus-selftest.sh` tests each of them.

Open regions: OR-1 the vuejs/core overlay's review context follows the upstream's own conventions. OR-2 the build names the new `case.json` fields and pattern values.

Provenance legend: `user-answered` = the operator chose. `codebase-derived` = a fact from the code or the docs, with its proof. `deferred` = not decided yet, under an open region.

Open region legend: `reversible-default-and-flag` = the build uses the stated default.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Upstreams for the new cases | github-readme-stats and vuejs/core. axios-5338 and Kong/insomnia are allowed where a pattern fits. No Multi-SWE-bench instance is reused. vuejs/core is new to the corpus. | user-answered | intent |
| D-2 | What the 80-line floor counts | Each new case changes at least 80 `+`/`-` lines outside `docs/plans/`, counted with `parse_patch`. Tests count. The plan file does not. | user-answered | intent |
| D-3 | Which cases the size floor binds | The 29 existing case ids are frozen in `planted.py`. Every other case must reach 80 lines, including the cases of #1122. No field lets a case opt out. | user-answered | intent |
| D-4 | How a distraction is recorded | A `distractions` list in `case.json`: each a ranged location and one sentence on why the change is correct. `check` requires at least one on every case outside the frozen ids. Each must sit outside WINDOW of every truth range. The scorer does not change. | user-answered | intent |
| D-5 | Coverage of the four P4 patterns | Each pattern appears in at least one new case. `case.json` records each case's pattern. `check` counts the coverage. | user-answered | intent |
| D-6 | The stored-data pattern on upstreams with no store | An in-memory analog. An existing caller passes a whole object it already holds back through the changed path. The new rule rejects a value that object carries. | user-answered | intent |
| D-7 | Truth locations for a caller outside the diff | Two ranged locations: one on the changed line, inside a hunk, and one on the breaking caller's line, even in an untouched file. | user-answered | intent |
| D-8 | The headline goal | PM-1 on the ticket body. The cases are made hard by construction. The build never probes the plain arm to choose them. | user-answered | intent |
| D-9 | Proof that each plant is real | A static proof that a lane build can produce. Per case, the PR body gives a `git grep` trace on the built checkout from the changed line to the breaking caller. It also gives the command that would show the break, with its predicted output. The build runs no JS. | user-answered | intent |
| D-10 | Where a case's 80 lines come from | From instances whose upstream fix and tests already reach about 80 lines. Only the plant and the distraction are authored. | user-answered | intent |
| D-11 | Whether the record explains the distraction | No. No D-n row mentions it, so the lane and plain arms face the same unexplained change. | user-answered | intent |
| D-12 | Where the share cap lives | Not in this slice. The operator's split put the 40% cap and its check in #1122. After this slice dayjs holds 16 of 35 cases. | user-answered | intent |
| D-13 | Text that goes stale | corpus-selftest.sh:27 pins the class counts. docs/testing.md:749 says 29 cases, and :760 gives the class counts. run: `grep -n 'check: ok (P1' corpus-selftest.sh; grep -n '29 cases\|eight P1 cases' docs/testing.md` → 27, 749, 760 | codebase-derived | fact |
| D-14 | What a new upstream needs | An `overlays/<owner>__<repo>/` with `review-context.md` and a configVersion 3 `config.json`, a NOTICE line, and a license in LICENSES. vuejs/core is MIT and has 48 instances. run: `grep -n 'NOTICE does not name\|^LICENSES' planted.py; gh api repos/vuejs/core/license -q .license.spdx_id` → 325, 43, MIT | codebase-derived | fact |
| D-15 | Review context of the vuejs/core overlay | Parked under OR-1 (owner: the build, by its default) | deferred | open |
| D-16 | Names of the new `case.json` fields and pattern values | Parked under OR-2 (owner: the build, by its default) | deferred | open |

Options weighed:

- D-1: readme-stats with vuejs/core, existing upstreams only, or reusing instances. The operator chose readme-stats with vuejs/core.
- D-2: code and tests without the plan, the whole patch, or code only. The operator chose code and tests without the plan.
- D-3: freeze the 29 ids, or mark new cases with a `case.json` field. The operator chose to freeze the ids.
- D-4: a checked `case.json` list, or the PR body only. The operator chose the checked list.
- D-5: every pattern at least once, or any mix. The operator chose every pattern.
- D-6: an in-memory analog, or dropping the pattern. The operator chose the analog.
- D-7: both locations ranged, the caller's file path-level, or the changed line only. The operator chose both ranged.
- D-8: a post-merge check, or none. The operator chose PM-1.
- D-9: a run proof, or a static proof a lane build can make. The operator chose the static proof, so the lane can build the slice unattended.
- D-10: large real fixes, or small fixes padded with authored code. The operator chose large real fixes.
- D-11: no record row, or a D-n row that justifies the change. The operator chose no row.
- D-12: a sequential split with the cap in the second slice, no split, or three slices. The operator chose two sequential slices.

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | Review context of the vuejs/core overlay | reversible-default-and-flag |
| OR-2 | Names of the new `case.json` fields and pattern values | reversible-default-and-flag |

- OR-1 default: a short `review-context.md` drawn from the upstream's own contributing guide, in the shape of the existing overlays. The build chose it. Reversing it is one file edit.
- OR-2 default: `distractions: [{file, start, end, side, why}]` and `truth.pattern` with one of four short slugs. The build chose it. Reversing it is a rename in `planted.py` and the new cases.

## Test intent

ACs: AC-1 AC-2 AC-3

AC-1: `planted.py check` on the shipped corpus counts at least ten P4 cases and every one of the four patterns, and a copy that drops a pattern's only case fails naming the pattern
AC-2: a copy whose new case has no distraction fails, and one whose distraction sits within WINDOW of a truth range fails
AC-3: a copy whose new case is cut below 80 changed lines outside the plan fails naming the case, and the frozen under-80 cases still pass

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | `planted.py check` output and its new messages | decided (D-3) |
| S-2 | `corpus-selftest.sh` output | decided (D-13) |
| S-3 | docs/testing.md, the planted mode section | decided (D-13) |
| S-4 | NOTICE and the vuejs/core overlay | decided (D-14) |
| S-5 | The PR body: proofs and the case-to-pattern map | decided (D-9) |
| S-6 | The lane and plain review prompts | out-of-scope — the render code does not change, and new cases pass through it as today. |
| S-7 | `planted/changelog.md` | out-of-scope — only `planted.py run` appends rows, and the rerun is the operator's. |
| S-8 | `planted.py verify` output | out-of-scope — verify prints truth ranges and needs no change for a caller range. |

## Checks

- `bash plugins/review-toolkit/evals/code-review-bench-eval/planted/corpus-selftest.sh`
- `python3 plugins/review-toolkit/evals/code-review-bench-eval/planted/planted.py check`

## Intake steps

Requirements: the parent #1119 as written. spec-reviewer found three blockers and nine gaps. The operator closed each one in the interview. The slice body restates the parent's ask.

Split: split into #1121 and #1122 (sequential) on the operator's yes. This receipt is for #1121.

Explore: done. Read planted.py, corpus-selftest.sh, lane-render.sh, run.sh's fails_without_change, docs/testing.md and the Multi-SWE-bench index.

Fan-out: ran once for the #1119 split — 16 items touch this slice.

Dup-scan: no candidates at or above threshold 12

Post-merge scan: no AC moved. PM-1 was added on the operator's answer (D-8).

Sizing: opus

<details>
<summary>Intake evidence: knowledge source and fan-out</summary>

## Knowledge source

Knowledge source: none declared

## Fan-out

Run: shared with the #1119 split — slices #1121, #1122
Refuter: cross (opus/fable alternating)
Lenses: harness-contract-fit opus 6/6 · gate-execution-path fable 6/6 · pattern-fidelity-and-sourcing opus 6/6 · selftest-and-slice-seam fable 6/6 · premortem fable 3/6
Tally: rows added 1 · snapshot claims overturned 1 · questions added 0

| ID | Angle | Claim | Tag | Disposition |
| --- | --- | --- | --- | --- |
| F-1 | harness-contract-fit | A caller location outside every hunk passes `check` only beside a ranged location in a hunk (`planted.py:292`). | already-had | became D-7 |
| F-2 | harness-contract-fit | Nothing knows a distraction, and a blocker on it scores only noise (`planted.py:653`). | already-had | became D-4 |
| F-5 | harness-contract-fit | dayjs holds 16 of 29 cases, and this slice alone leaves it at 45.7%. | already-had | became D-12 |
| F-6 | harness-contract-fit | The 80-line rule does not say what counts, and the count string is pinned (`corpus-selftest.sh:27`). | already-had | became D-2 |
| F-13 | pattern-fidelity-and-sourcing | The cap needs at least 11 new cases outside dayjs. | already-had | became D-12 |
| F-14 | pattern-fidelity-and-sourcing | vuejs/core has 48 unused instances under MIT, and axios's unused instance is 5338. | overturned (snapshot: "svelte/mui/vue datasets are LFS pointers; git-lfs is not installed") | became D-1 |
| F-16 | pattern-fidelity-and-sourcing | No existing P4 case breaks two hops away, and three patterns have no case (`cases/*/case.json`). | new | became D-5 |
| F-18 | pattern-fidelity-and-sourcing | Each of the 29 cases uses its own instance, and `check` does not enforce it (`planted.py:201`). | new | became D-1 |
| F-19 | selftest-and-slice-seam | Each slice must rewrite the pinned count string (`corpus-selftest.sh:27`). | already-had | became D-13 |
| F-20 | selftest-and-slice-seam | With `parse_patch` outside the plan, 4 of 29 cases reach 80 lines (median 25). | already-had | became D-2 |
| F-21 | selftest-and-slice-seam | `check` accepts unknown `case.json` keys and a duplicated case directory. | new | informed D-3; the duplicate gap is out of scope |
| F-22 | selftest-and-slice-seam | The cap holds only at 40 cases or with a dayjs case removed. | already-had | became D-12 |
| F-23 | selftest-and-slice-seam | Each new check fits the copy-and-break idiom of `corpus-selftest.sh`. | not material | not material — the test idiom is the build's |
| F-24 | selftest-and-slice-seam | A new upstream needs an overlay, a NOTICE line and an allowed license (`planted.py:325`). | already-had | became D-14 |
| F-26 | premortem | The ask's minimum counts miss the 40% cap. | already-had | became D-12 |
| F-27 | premortem | A floor over every case reds 25 existing cases unless new cases are marked. | already-had | became D-3 |

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
