# lean review verdict — #492

verdict=needs-work
run_id: review-492-2
session_id: 75f8a117-920b-4ce0-929b-66688dd6828c
rounds: 2
pr: #501
reviewed_head: e932531bce919e3cdb5140f65bc8c974d5d9826f
reviewed_patch_id: ac597fb15f2e237202485b553c62333edb07bdbc
inherited_patch_id: 11eaf8f04eb0fe97ba02c012b9c238ecb5eff947
inherited_from_verdict: 0324614612f38f0d56e44e59ddc2241d8d43b862
fidelity: not-applicable
model: unknown
capabilities: pr-marker

## Verdict: needs-work — round 1's blocker is discharged, and the CI it unblocked is red

Round 1 could not certify this branch because it was unmergeable and had therefore never run CI.
Round 2 fixed that: `refs/pull/501/merge` resolves, the merge is pure reconciliation, and the lane's
own machinery ran for the first time. It found a real failure, in this branch's own code.

Two of four jobs pass and they are the expensive ones. `lint-and-selftests` fails at its **first**
step, on a shellcheck error `main` does not have.

## Blocker

**B-1 — `lint-and-selftests` is red: SC2218 in `lean-gate-selftest.sh`, introduced by this branch.**

```
In ./plugins/dev-pipeline/skills/build-lean/lean-gate-selftest.sh line 3010:
pgate entry 8 >/dev/null 2>&1
^---------------------------^ SC2218 (error): This function is only defined later. Move the definition up.
                              (also line 3092)
Process completed with exit code 123.
```

Root cause: this branch defines `pgate` **twice**. `main` has exactly one definition (line 2833,
the build-session wrapper); the new `(pg)` section adds a second at line 4094 with a different body
(`bash "$GATE" progress 77 "$@"`, session id unset, different tree and progress file). ShellCheck
binds the bare calls at 3010/3092 to the *later* definition and errors.

Reproduced and root-caused against CI's exact version, not inferred:

| Probe | Result |
| --- | --- |
| shellcheck **0.9.0** (CI's) on branch `lean-gate-selftest.sh` | `rc=1`, SC2218 ×2 — matches CI byte for byte |
| shellcheck **0.9.0** on `origin/main`'s copy of the same file | `rc=0` |
| rename the second definition `pgate` → `pgprog` (line 4094→EOF) | `rc=0` under 0.9.0 **and** 0.11.0 |
| shellcheck **0.11.0** (this machine's) on branch HEAD | `rc=0` — which is why the local gate passed |

The rename is mechanically safe: no `pgate_tel` call occurs at or after line 4094, and every call in
the `(pg)` section is def-2-shaped (`pgate`, `pgate --satisfied 5`), so nothing after 4094 wants the
first definition. It is also the better code — two same-named helpers with different gate
invocations in one 4200-line file is a readability trap independent of the linter.

At runtime the suite is correct (bash binds definitions as it executes), which is why 73/73 is green.
This is a lint failure, not a behavioral one — but it is a **hard red on a required check**, and the
repo's own verification baseline in `CLAUDE.md` names shellcheck first.

**Second-order cost.** The job aborts at step 1, so eight verification steps never executed: JSON
validation, issue-forms schema, actionlint, the ubuntu selftest sweep, contract lockstep pairs,
eval-harness model identity, capability parity register, and the namespace direction check. The PR
body's "lockstep 28/28, namespace rules 3(a)/3(b) pass" remains a local claim that CI has still not
confirmed. The selftest sweep itself is covered in substance by the macOS job below, so that one is
duplicated rather than lost — the other seven are not.

## CI evidence — the thing round 1 could not obtain

| Job | Result | What it proves |
| --- | --- | --- |
| `selftests (macos, bash 3.2)` | **pass** 4m16s | `73 scored, 71 run, 2 cached, 0 failed` — green on the stock-bash-3.2 lane, where a `declare -A` would fail open. |
| `mutation-sweep-pr` | **pass** 3m30s | 30 verdicts computed (not a vacuous PR-mode zero). `lean-gate.sh` 17 applied / 14 killed / 3 survived; `orchestrate-lean.sh` 11 / 10 / 1. All four survivors are generic and baselined — the job would red on a baseline-absent one. **The PR body's mutation claim is now CI-verified, not just local.** |
| `lint-and-selftests` | **fail** | B-1. |
| `pr-gates` | **fail** | Only `check-lean-chain.sh`, only because the committed record reads `verdict=needs-work`. Expected pre-approval; the other three steps pass. Not a defect. |

## What round 2 verified in the delta (`0324614..HEAD`)

- **The merge is pure reconciliation.** `git diff origin/main HEAD --stat` touches only #492's six
  files — nothing arrived from or was altered on main's side. The three conflict resolutions are
  each one side or the other: the parser keeps main's widened columns and adds
  `--max-continuations`; the run-log line carries both `$REVIEW_BASIS_NOTE` and the continuation
  ordinal; `-h|--help` re-ranges to `2,98p`, which I checked against the file — line 98 is the last
  header comment and line 99 is `set -uo pipefail`. #491's cases survive intact (9 live references
  to `--review-model-basis`), and case `(n)` still guards the range.
- **The W-1 commit is comment-only.** `e932531` is `+5` lines in one file, all comment, immediately
  above the unchanged `if [ "$m5_after" = "$m5_before" ]`. AC-7 is not amended and no behavior moved.
  W-1 is closed.

## Per-AC scoring — all eight, against the whole spec

Production logic re-read at this head over `origin/main`, not inherited blind; the gate internals
carry round 1's coverage (`inherited_patch_id 11eaf8f0`) and are now independently corroborated by
the mutation job above.

| AC | Score | Evidence at this head |
| --- | --- | --- |
| AC-1 | satisfied | Build phase re-spawns on a moved token; prompt is the unchanged `/dev-pipeline:build-lean $ISSUE`. Cases `(o1)`, `(o2)`. |
| AC-2 | satisfied | `--max-continuations` default 2, parsed beside `--max-rounds`, non-negative validation with a stated reason zero is legal; exhaustion is a `HARD STOP` naming the cap. `continuations=0` at the top of each build phase, whose only exit is a PR. `(o3)`, `(o5)`, `(o6)`, `(o7)`. |
| AC-3 | satisfied | Token equality → the pre-#492 message and one spawn. `(j2)` unchanged; `(j3)` is its anti-vacuity control. |
| AC-4 | satisfied | Re-confirmed in source: `cmd_progress` calls only `progress_token` — no `ensure_progress_file`, no `record_build_session`. `rc=4` untouched. `(pg8)`. |
| AC-5 | satisfied | Predicate is the read-only `lean-gate.sh progress`, returning `progress-v1:<n>`; the scheduler compares two strings and parses neither. Bookkeeping excluded. `(pg1)`, `(pg10)`. |
| AC-6 | satisfied | The three enumerated cases plus `(o4)`. Now green on the bash-3.2 CI lane, which round 1 could not show. |
| AC-7 | satisfied | Close-out compares `progress --satisfied 5` across the spawn, requires a NEW row, verify-only, non-zero naming what is unmet. `(p1)`, `(p2)`, `(p3)`. The re-entry trade is now documented in place. |
| AC-8 | satisfied | Re-confirmed in source: dispatch line reads `claim\|delta\|all\|1\|2\|3\|4\|5) require_entry_attested` — `progress` is absent, per D-2. Exercised by `(pg1)`–`(pg12)`. **Note:** the guard file satisfying this AC is the one failing B-1. The cases are sound; the file does not pass the lint gate. |

The blocker is not an unmet AC. The spec does not have an AC for "the branch passes its own CI", and
it should not need one.

## Warning

**W-2 — the repo's shellcheck recipe is version-unpinned, and the skew is silent in the red direction.**
`CLAUDE.md` prescribes `find . -name '*.sh' … | xargs -0 shellcheck -e SC1091,SC2015,SC2181` with no
version; CI installs ubuntu's 0.9.0. This machine has 0.11.0, which dropped this SC2218 heuristic —
so the documented local gate returned a clean green for a change CI errors on. That is the same shape
as `local sweep is not the bash-3.2 lane`, one tool over. Not this PR's to fix; worth a ticket, since
every contributor's local shellcheck gate is only as trustworthy as their version match.

## Suppressed / dismissed

- **`pr-gates` red.** Not a finding — `check-lean-chain.sh` requires `verdict=approve` and the
  committed record is round 1's `needs-work`. It clears when an approve record lands.
- **Ubuntu selftest sweep unrun.** Noted under B-1's second-order cost rather than raised separately:
  the same 73 suites passed on the macOS bash-3.2 job, so the suites themselves are not unverified.

## What the code does well

- The reconciliation was done as a merge with the conflict fix and the W-1 comment in **separate
  commits**, so "no content rode in on the merge" is verifiable by inspection rather than assertion.
  It is what let this round confirm purity in one `--stat`.
- Case `(n)` earned its keep on a merge nobody wrote it for: the `-h|--help` range had to be
  renumbered a third time, and the guard is what makes a wrong number red instead of silently
  truncating the header.
- The PR body states its ceiling (the fake spawn cannot prove a real `claude -p` continuation) rather
  than letting the green imply more than it shows, and it flags that `mutation-sweep-pr` had never
  run — the claim that turned out to be the honest one and is now discharged.

## Remedy

Rename the second `pgate` (line 4094 and its callers to EOF) to a distinct name. Verified green above
under both shellcheck versions. Then let CI run the eight steps it has not yet reached.
