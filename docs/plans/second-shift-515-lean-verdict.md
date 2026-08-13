# lean review verdict — #515

verdict=needs-work
run_id: review-515-1
session_id: def30dfe-d2db-450e-89e8-55ef50ef3a80
rounds: 1
pr: #534
reviewed_head: 872b451f005d28bf2408583d3aff1b51d2cc9608
reviewed_patch_id: 4cf4210be133a33052fba095ad832c4fafeb21b5
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: opus
capabilities: pr-marker

Range read: full branch diff (`492bb99..872b451`), 7 files / 782 insertions, 20 deletions.
Root round — nothing inherited.

**Verdict: needs-work.** One blocker, and it is about the PR's state rather than its code:
the branch cannot merge and has never been built by CI. The implementation itself is clean —
all ten acceptance criteria are satisfied, both touched suites are green, and every claim the
PR body makes reproduced.

## Findings

| #   | Severity | Where                             | Finding                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| --- | -------- | --------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | Blocker  | `tools/mutation-catalog.tsv`      | The PR is `CONFLICTING`, so **zero CI has ever run on it**. `#521` landed on main after this branch was rebased onto `492bb99` and appended to the same catalog; `git merge-tree` reports the file `changed in both`. `git ls-remote origin 'refs/pull/534/*'` returns only `refs/pull/534/head` — no `refs/pull/534/merge`, so no `pull_request` workflow was ever queued. Every green in this record and in the PR body is a **local** claim; `mutation-sweep-pr` and the stock-bash-3.2 macOS lane have not run. Remedy: rebase onto `origin/main`, resolving the two append-only catalog blocks. |
| 2   | Warning  | `lean-gate-selftest.sh:4657`      | The `(st)` block header credits the wrong cases. It says "(st12) asserts the subcommand creates no progress file" and "(st13) is the assertion that this subcommand is reachable without [an entry attestation]" — both facts are asserted by **(st15)**. (st12) is the jira skip and (st13) is the no-branch skip. The numbering looks like it predates two case insertions and was not re-keyed.                                                                                                                     |
| 3   | Warning  | `orchestrate-lean-selftest.sh:919` | Same class, same file pair. The `(v)` block header says "(v11) is the one case here that joins the two" — the real-gate composition is **(v13)/(v14)**; (v11) asserts that a failing ticket probe still reports the other probes' verdicts. A future auditor checking the stated coverage claim lands on a case that guards something else.                                                                                                     |

Both warnings are comment-only and change no behavior. They matter here only because this repo
treats "which case guards which invariant" as load-bearing prose — a header that misdirects is
the shape that lets a real coverage hole read as covered.

The six-reviewer panel (security, performance, maintainability, complexity, test-coverage,
scope-completeness) returned `approve` with **zero** findings and two sub-threshold suppressed
notes (confidence 30 and 35, both output-only interpolation with no sink). Panel was fully
live — no dark reviewer, so no coverage gap. `a11y` and the design-fidelity dimension were not
routed: no changed path matches `stageParams.webComponentGlobs` (key absent; resolved default
`apps/web/**/*.{tsx,jsx}`), and this diff is shell and markdown only.

## Per-AC scoring

All ten satisfied.

| AC    | Score     | Evidence                                                                                                                                                                                                                                                       |
| ----- | --------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| AC-1  | satisfied | `staleness` dispatches at `lean-gate.sh:3622`; taxonomy 0/7/1/2 implemented. `require_entry_attested`'s set (`lean-gate.sh:3612`) is `claim\|delta\|all\|1..5` — `staleness` is absent. `cmd_staleness` calls neither `ensure_progress_file` nor `append_line`. (st15) green. |
| AC-2  | satisfied | Overlap, not advancement: (st2) a moved base into no shared file is `0`; (st3) `7` naming `shared.txt`; (st4) neither the base-only nor branch-only file is reported; (st6) `--arm ticket` skips it while the base arm is actively firing.                        |
| AC-3  | satisfied | (st8) `CLOSED` → 7; (st9) asserts the stub was asked `--json state` and never `stateReason`, which is what makes a `not_planned` close count; (st12) jira states a skip and the base arm still runs; (st7) `--arm base` skips it against a CLOSED ticket.        |
| AC-4  | satisfied | (st13): a branch-less key is a stated skip at rc=0 with the ticket arm still evaluated, distinct from AC-5's exit 1.                                                                                                                                            |
| AC-5  | satisfied | All four fail-closed paths driven: (st10) unreadable tracker, (st11) unrecognized state, (st14) unfetchable base, (st17) unresolvable merge-base via an orphan root. None returns 0 or 7.                                                                       |
| AC-6  | satisfied | (v1) 3 spawns / 1 loop read — nothing before REVIEW or the close-out; (v4) 4 spawns / 2 reads proves "per BUILD spawn", not "per spawn"; (v5) round 2 re-evaluates rather than remembering round 1.                                                             |
| AC-7  | satisfied | (v6) exit 7, 0 spawns, message names the rebase-or-abandon choice and the state left in place; (v7) states the re-fire (D-10); (v9) any other rc → exit 1; (v8) the check is first in the loop body, so a stale run does not pay for the progress read.          |
| AC-8  | satisfied | (v10) preflight rejects at exit 2 with 0 spawns and 0 loop reads; (v11) the other probes still report; (v12) fails closed; (v3) preflight asks `--arm ticket` and the loop asks for both.                                                                       |
| AC-9  | satisfied | `run-lean/SKILL.md` carries the `7` row, the operator instruction and the OR-3 paragraph, and is **exactly 60 lines**. Both `--help` ranges verified against their files: gate `sed -n '2,172p'` with `set -uo pipefail` at 173; orchestrator `2,158p` with it at 159. |
| AC-10 | satisfied | The `(st)` block builds its own fixture with a real bare `origin`, a second clone that pushes, and no hand fetch — so a build that dropped the arm's own `git fetch` fails (st2). (v13)/(v14) are a matched fire/no-fire pair against the **real** gate with `LEAN_GATE` unset. |

## Independent verification

Everything below was run by this review session from a checkout of the reviewed head. The only
mutation probe wrote to `/tmp`; the reviewed checkout was never mutated.

**Suites, run cold with `CLAUDE_CODE_SESSION_ID` / `RUN_ID` / `LEAN_RUN_MODEL` scrubbed:**

- `lean-gate-selftest.sh` — **all green**, (st1)–(st17) all pass.
- `orchestrate-lean-selftest.sh` — **all green**, (v1)–(v14) all pass.

**shellcheck** `-e SC1091,SC2015,SC2181` on all four changed scripts: clean. Run at 0.11.0;
CI runs 0.9.0, which is the strictly less strict of the two, so this direction of skew is safe.

**bash 3.2**, verified on stock `/bin/bash` 3.2.57: `${@:2}` (both suites' `git` wrappers),
process substitution feeding `grep -Fxf`, and `<<<` here-strings all behave. The `<<<` form is
also what keeps the assertions clear of the `pipefail`/SIGPIPE misread that `#522` fixed.

**Mutation-catalog rows — applied verbatim, not assumed.** All three new rows were run through
`sed` exactly as written, against the branch's own files:

| Row                                | Result                                                                                    |
| ---------------------------------- | ----------------------------------------------------------------------------------------- |
| `staleness-advance-is-the-trigger` | applies to 1 line (`lean-gate.sh:1450`, the `overlap` test), mutant is `bash -n` valid     |
| `staleness-fetch-failure-as-clean` | applies to 1 line (`lean-gate.sh:1428`), mutant is `bash -n` valid — the `✗` in the anchor survives BSD sed |
| `staleness-preflight-arm-widened`  | applies to 1 line (`orchestrate-lean.sh:350`), mutant is `bash -n` valid                   |

None is a silent no-op, which is the failure mode that makes a catalog row read as coverage
while never being applied. Each also has a resolvable killer under the same-stem rule
(`lean-gate.sh` → `lean-gate-selftest.sh`, `orchestrate-lean.sh` → `orchestrate-lean-selftest.sh`),
so `#521`'s new `tools/mutation-pair-map.tsv` needs no row for them.

**(st15) anti-vacuity control.** (st15) asserts a path does *not* exist, which is worthless if
that is not the path the gate writes. Sourcing the gate in its `LEAN_GATE_LIB` mode under
(st15)'s own config resolves `PROGRESS_FILE` to
`$MAIN_ROOT/.claude/pipeline-state/<issue>-lean-progress.md` — exactly the path (st15) names.
The assertion is real.

**The predicate fires on its own PR.** Run from this checkout with the branch's own gate:

```
[lean-gate] staleness: ticket arm clean — #515 is still OPEN.
[lean-gate] staleness: BASE ARM FIRED — origin/main has moved into 1 file(s) this branch also
touches since 492bb99: tools/mutation-catalog.tsv
rc=7
```

That is finding 1 restated by the feature itself, and it is the best available evidence that
the overlap predicate is calibrated correctly rather than merely green against its fixtures.

**Repo conventions:** no frozen file touched (`plugin.json`, `CHANGELOG.md`,
`marketplace.json` all absent from the diff); `Changelog:` trailers present on all three
commits; `feat(dev-pipeline):` is the honest verb for a new capability in the repo where the
tooling is the product.

## What the next round must do

Rebase onto `origin/main` — the conflict is two append-only blocks at the end of
`tools/mutation-catalog.tsv` and resolving it is mechanical. Folding in findings 2 and 3 costs
three comment lines and no behavior. Because any line-changing push voids this record, doing
both in one push is strictly cheaper than doing them separately.
