# lean review verdict — #492

verdict=approve
run_id: review-492-3
session_id: 200d8af7-7b7f-4349-9734-cd627432d635
rounds: 3
pr: #501
reviewed_head: 8561290da199ba2d3d54ba944ea9627b537b374d
reviewed_patch_id: a9a6b9d32759ec360e7b708c58ffc45e28e59401
inherited_patch_id: ac597fb15f2e237202485b553c62333edb07bdbc
inherited_from_verdict: 4617895acbf225b694cf9168f146e01c72cdca1e
fidelity: not-applicable
model: unknown
capabilities: pr-marker

## Verdict: approve — round 2's blocker is discharged, and every CI step it took down has now run

Round 2 could not certify this branch because `lint-and-selftests` died at its **first** step on
SC2218, taking eight later verification steps down unrun. Round 3's delta is exactly the remedy that
record prescribed, and nothing else. All four CI jobs now report, the lane's own machinery is green,
and the eight steps that had never executed have executed and passed.

No blockers. One minor warning, which costs no round to fix.

## The delta (`4617895..HEAD`), and what it is

One commit, `8561290`, one file, 16 insertions / 16 deletions: the `(pg)` section's gate wrapper is
renamed `pgate` → `pgprog` — its definition at line 4094 and its 15 call sites through EOF.
Behavior-preserving by construction: the function body is untouched (`bash "$GATE" progress 77
"$@"`), and only the identifier moved.

Verified complete and correctly bound, not assumed:

| Check | Result |
| --- | --- |
| `pgate` occurrences after line 4094 | **none** — the first definition (2833) and `pgate_tel` (2843) keep every call site at 2864–3092, all *before* 4094 |
| `pgprog` occurrences | 16 = 1 definition + 15 calls, all at or after 4094 — matches the diff's 16/16 exactly |
| the surviving duplicate that caused SC2218 | gone: one `pgate`, one `pgprog`, no shadowing |

## CI at this head (`8561290`) — the evidence round 2 unblocked and round 3 collects

`refs/pull/501/merge` resolves to `e52c7bd`, whose parents are `2e4b480` (main's tip, #487, landed
19:10:38Z) and this head. The run was created 19:11:15Z — **37 seconds after #487 merged** — so all
four jobs ran against main-at-tip merged with this branch, not a stale base.

| Job | Result | What it proves |
| --- | --- | --- |
| `lint-and-selftests` | **pass** 3m58s | B-1 discharged. |
| `selftests (macos, bash 3.2)` | **pass** | Green on the stock-bash-3.2 lane. |
| `mutation-sweep-pr` | **pass** | Verdicts computed against main's newest `tools/mutation-sweep.sh` (#487 changed that file); no baseline-absent survivor. |
| `pr-gates` | fail | `check-lean-chain.sh` only, and only on `verdict=needs-work`. Expected pre-approval — the other three steps pass. Not a defect. |

**The step list, not the job verdict** — the discipline round 2's B-1 established. All eight steps
that never executed under B-1 have now run and passed: `validate JSON`, `issue-forms schema`,
`actionlint`, `run all selftests` (the ubuntu sweep), `contract lockstep pairs`,
`eval-harness model identity`, `capability parity register`, `namespace direction check`. The one `-`
in the list is `save selftest pass cache`, a cache **write**, not a verification step. The PR body's
"lockstep 28/28, namespace rules 3(a)/3(b) pass" is no longer a local claim.

## Probes — the rename is not a vacuous green

A rename that severs a test wrapper from production would leave the `(pg)` cases passing on nothing,
and CI would look identical. Both directions were probed in **detached throwaway worktrees**, never
the reviewed head. Every mutant was `cmp`-verified changed and `bash -n`-verified parseable before
scoring, and the applied diff printed.

**Control** — unmutated head: `rc=0`, `all green`, `(pg1)`–`(pg12)` all PASS.

| Probe | Mutation | Result | What it establishes |
| --- | --- | --- | --- |
| **A** | rename the *definition* `pgprog()` → `pgprogSEVERED()`, leaving all 15 call sites saying `pgprog` | **8 FAILURES**; `(pg1)(pg3)(pg4)(pg5)(pg6)(pg7)(pg10)(pg11)` red, tokens empty, `(pg11)` rc=127 | The call sites genuinely resolve to the definition at 4094. Decisively **not** falling through to the surviving `pgate` at 2833 — that would have returned a non-empty token and left them green. The rename is complete on both ends. |
| **B** | break production `progress_token` in `lean-gate.sh` to always print `progress-v1:0` | **5 FAILURES**; `(pg1)(pg3)(pg4)(pg6)(pg7)` red | The renamed wrapper still reaches the real `lean-gate.sh progress` subcommand. The cases are non-vacuous post-rename — AC-8's exercise is real. |

The cases that stayed green under each probe are accounted for, not overlooked. Under A, `(pg2)`
compares two tokens that are both broken and therefore equal; `(pg8)`, `(pg9)`, `(pg12)` never call
`pgprog`. Under B, `(pg5)` asserts the token does **not** move on an `attempt` row — a constant `0`
also does not move, which is the known class of case a feature-removal probe cannot red; `(pg7)`'s
second clause covers that ground and did fire.

## Reviewer panel

Five reviewers selected and dispatched on the delta (Small change size: security, performance,
maintainability + test-coverage since the change is to a test file, + scope-completeness
unconditionally on `#492`). **All five returned, none dark. 5/5 approve, zero findings.**

| Reviewer | Verdict | Findings | Confidence Range |
| --- | --- | --- | --- |
| Scope Completeness | Pass | 0 | — |
| Security | Pass | 0 | — |
| Performance | Pass | 0 | — |
| Maintainability | Pass | 0 | — |
| Test Coverage | Pass | 0 | — |

One suppressed finding at confidence 20 (`"$@"` interpolation into a gate invocation at 4094) —
dismissed on reading: every call site passes literal test flags inside a selftest fixture, there is
no external input, and the construct is unchanged from before the rename.

`a11y-reviewer` and the design-fidelity dimension were **not routed**: no changed path matched
`stageParams.webComponentGlobs` (unset → default `apps/web/**/*.{tsx,jsx}`). Not a coverage gap — a
shell selftest is not a web-component surface.

## Per-AC scoring — all eight, against the whole spec

The delta touches only the guard file behind AC-8, so AC-1 through AC-7 inherit round 2's coverage of
the production sources (`inherited_patch_id ac597fb1`); `orchestrate-lean.sh`'s full contribution diff
was nonetheless re-read at this head rather than inherited blind, and CI's mutation job corroborates
the gate internals independently.

| AC | Score | Evidence at this head |
| --- | --- | --- |
| AC-1 | satisfied | Build phase re-spawns on a moved token; the continuation prompt is the unchanged `/dev-pipeline:build-lean $ISSUE`, a fresh `-p` session, never `--resume`. Cases `(o1)`, `(o2)`. |
| AC-2 | satisfied | `--max-continuations` default 2; `continuations=0` at the top of each build phase, whose only exit is a PR — that scoping *is* D-3's reset. Exhaustion is a `HARD STOP` naming the cap. Zero legal, with the reason stated in-source. `(o3)`, `(o5)`, `(o6)`, `(o7)`. |
| AC-3 | satisfied | Token equality → the pre-#492 message and one spawn. `(j2)` unchanged; `(j3)` is its anti-vacuity control. |
| AC-4 | satisfied | `cmd_progress` calls only `progress_token` — no `ensure_progress_file`, no `record_build_session`, no milestone evaluation. `rc=4` untouched. `(pg8)`, and probe B above. |
| AC-5 | satisfied | The predicate is the read-only `lean-gate.sh progress`, printing `progress-v1:<n>`; the scheduler compares two strings and parses neither, and returns non-zero rather than an empty token when the gate cannot answer — so a broken gate is not mistaken for an idle session. Bookkeeping rows excluded. `(pg1)`, `(pg2)`, `(pg10)`. |
| AC-6 | satisfied | The three enumerated cases plus `(o4)`, green on both CI lanes including bash 3.2. |
| AC-7 | satisfied | Close-out compares `progress --satisfied 5` across the spawn, requires a NEW row, verify-only, non-zero naming what is unmet. `(p1)`, `(p2)`, `(p3)`. The re-entry trade is documented in place (round 1's W-1, closed in round 2). |
| AC-8 | **satisfied** | `progress` is absent from `require_entry_attested`'s subcommand set, per D-2; it writes nothing and creates nothing. Exercised by `(pg1)`–`(pg12)`. Round 2 scored this with the caveat that the guard file satisfying it was the file failing B-1 — that caveat is now retired: the file passes shellcheck 0.9.0 in CI, and probes A and B show the exercise survives the rename. |

## Warning

**W-3 — the PR body has no round-3 section, so the shipped fix is undocumented in the PR narrative.**
The body's round-2 section still reads "shellcheck and `jq empty` clean" for head `e932531`, which is
the head where CI proved that claim false; nothing in the body records that `8561290` renamed the
duplicate `pgate` to clear SC2218. The commit message documents it fully, and the body is not part of
the patch id — so this costs no round and does not gate the merge. Worth one paragraph before merge,
since the body is the artifact a human reads.

W-2 from round 2 (the version-unpinned shellcheck recipe in `CLAUDE.md`) stands as raised and remains
correctly out of this PR's scope.

## Suppressed / dismissed

- **`pr-gates` red.** Not a finding — `check-lean-chain.sh` requires `verdict=approve` and the
  committed record was round 2's `needs-work`. It clears when this record lands.
- **Cross-file duplicate `progress_token`.** `lean-gate.sh:1122` and `orchestrate-lean.sh` both define
  a function by that name. shellcheck is per-file so there is no SC2218 exposure, the two live in
  different scripts, and the shared name is accurate in both. Not a finding.
- **OR-1** (a continuation re-enters `build-lean` step 1 against an already-claimed ticket). Declared
  in the spec with a `reversible-default-and-flag` disposition and an evidence-backed default; the
  fake-spawn harness cannot reach it, which the spec says in its own Stated Ceiling. Declared, not
  overlooked.

## What the code does well

- **The remedy was taken literally and nothing rode along with it.** Round 2 prescribed "rename the
  second `pgate` and its callers to EOF"; the delta is that and 16/16 lines of it. A fix round that
  stays this small is what makes a third round cheap to certify.
- **The chosen name carries information.** `pgprog` names the subcommand it invokes, so the two
  wrappers are now told apart by what they do rather than by which one bash bound last — the
  readability defect that outlived the linter error is fixed too.
- **The commit message states the mechanism, not the symptom.** It names 0.9.0 as the version that
  errors and 0.11.0 as the version that dropped the heuristic, which is exactly why the local gate
  was honestly green — the next contributor reading it learns the trap, not just the fix.

## Stated ceiling, restated

`orchestrate-lean-selftest.sh` fakes the spawn, so no CI case proves a real `claude -p` continuation
completes `build-lean` unattended. Every AC is provable against the fakes; the end-to-end remains an
operator observation on the next live run. This approve certifies the ACs and the guards, and says
nothing more than that.
