# lean review verdict — #515

verdict=approve
run_id: review-515-2
session_id: 42be9a90-cec9-40b6-8611-af3bed8222fa
rounds: 2
pr: #534
reviewed_head: e6795d36acf3a0823efc534ed335887ee9574ef0
reviewed_patch_id: 8ebfaab6bbd041ce17a19e1e1fe110eca77401f6
inherited_patch_id: 4cf4210be133a33052fba095ad832c4fafeb21b5
inherited_from_verdict: 6693c36020f130588200114cfc298a3220afd88d
fidelity: not-applicable
model: opus
capabilities: pr-marker

Range read: FULL branch diff (`fa99191..e6795d3`), 9 files / 920 insertions, 21 deletions.
Nothing inherited — the rebase onto `#521` re-stamped every patch id, so `delta` printed the whole
range and said so. This round therefore re-read everything round 1 read, plus the two fix commits.

**Verdict: approve.** Round 1's single blocker is cleared, both warnings are fixed, and all ten
acceptance criteria are satisfied. No new blocker.

## Round 1's findings, re-checked

| # | R1 severity | Status | Evidence |
| --- | --- | --- | --- |
| 1 | Blocker | **Fixed** | The PR is `MERGEABLE` and CI has now run on this head: `lint-and-selftests`, `mutation-sweep-pr` and `selftests (macos, bash 3.2)` all **pass**. `pr-gates` fails in 10s on round 1's `verdict=needs-work` — the expected pre-handoff state, which this record clears. Every green in round 1 was a local claim; they are now CI-confirmed. |
| 2 | Warning | **Fixed** | `lean-gate-selftest.sh:4697` now credits **(st15)** for both facts. Verified against the cases themselves: (st15) is "needs no entry attestation and creates no progress file"; (st12) is the jira skip, (st13) the no-branch skip. |
| 3 | Warning | **Fixed** | `orchestrate-lean-selftest.sh:917` now credits **(v13)/(v14)**. Verified: those are the matched real-gate fire/no-fire pair; (v11) is the failing-ticket-probe case. |

Neither fix was a suppression — each moved the claim onto the case that actually asserts it. One
nearby reference was checked rather than assumed: the `(st13)` credit at `lean-gate-selftest.sh:4744`
is **correct** — (st13) asserts `ticket arm clean`, so a leaked `ST_STATE=CLOSED` from (st7) really
would have failed it there.

## Findings this round

No blockers. No warnings.

One non-blocking observation, offered as a suggestion rather than a finding:

- **[Suggestion] `lean-gate.sh:1434-1435`** — the two `git diff --name-only` reads in
  `staleness_base_arm` are the only reads in the arm whose exit status is discarded (`2>/dev/null`
  with no `||`). A failure there yields an empty `base_files`, which routes to
  `"base arm clean — origin/main has not moved"` — the error-reads-as-success shape the ticket
  exists to remove, inverted. It is close to unreachable in practice (both operands are already
  proven resolvable by the fetch and merge-base guards immediately above), it is not one of the
  three reads AC-5 enumerates, and every other read in the arm does fail closed. Noted for
  completeness, not as a defect in scope here.

## The panel

Six reviewers (security, performance, maintainability, complexity, test-coverage,
scope-completeness) returned `approve` with **zero** findings and four sub-threshold suppressed
notes (confidence 35–70). The panel was fully live — no dark reviewer, so no coverage gap.

`a11y` and the design-fidelity dimension were not routed: no changed path matches
`stageParams.webComponentGlobs` (key absent; resolved default `apps/web/**/*.{tsx,jsx}`), and this
diff is shell, markdown and TSV only. The spec declares no `## Design` section, so `fidelity` is
`not-applicable`.

The one suppressed note worth surfacing (scope-completeness, confidence 70): under a jira consumer
the ticket arm no-ops, so only the base arm guards the spawn. That is **AC-3's stated behavior**
(D-8) and the spec names it — not an unsatisfied scope item.

## Per-AC scoring

All ten satisfied.

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | `staleness) cmd_staleness` dispatches at `lean-gate.sh:3618`; taxonomy 0/7/1/2 implemented. The attestation set at `lean-gate.sh:3612` is `claim\|delta\|all\|1..5` — `staleness` is absent, read directly rather than inferred. `cmd_staleness` calls neither `ensure_progress_file` nor `append_line`. (st15) green. |
| AC-2 | satisfied | Overlap, not advancement: (st2) a moved base into no shared file is `0`; (st3) `7` naming `shared.txt`; (st4) neither base-only nor branch-only file is reported; (st6) `--arm ticket` skips it while the base arm is actively firing. Confirmed on real data — see below. |
| AC-3 | satisfied | (st8) `CLOSED` → 7; (st9) asserts the stub was asked `--json state` and never `stateReason`, which is what makes a `not_planned` close count; (st12) jira states a skip while the base arm still fires; (st7) `--arm base` skips it against a CLOSED ticket. |
| AC-4 | satisfied | (st13): a branch-less key is a stated skip at rc=0 with the ticket arm still evaluated, distinct from AC-5's exit 1. |
| AC-5 | satisfied | All four fail-closed paths driven: (st10) unreadable tracker, (st11) unrecognized state, (st14) unfetchable base, (st17) unresolvable merge-base via an orphan root. None returns 0 or 7. |
| AC-6 | satisfied | (v1) 3 spawns / 1 loop read — nothing before REVIEW or the close-out; (v4) 4 spawns / 2 reads proves "per BUILD spawn", not "per spawn"; (v5) round 2 re-evaluates rather than remembering round 1. |
| AC-7 | satisfied | (v6) exit 7, 0 spawns, message names the rebase-or-abandon choice and the state left in place; (v7) states the re-fire (D-10); (v9) any other rc → exit 1; (v8) the check is first in the loop body, so a stale run does not pay for the progress read. |
| AC-8 | satisfied | (v10) preflight rejects at exit 2 with 0 spawns and 0 loop reads; (v11) the other probes still report; (v12) fails closed; (v3) preflight asks `--arm ticket` and the loop asks for both. |
| AC-9 | satisfied | `run-lean/SKILL.md` carries the `7` row, the operator instruction and the OR-3 paragraph, and is **exactly 60 lines** (measured). Both `--help` ranges verified against their files: gate `sed -n '2,172p'` with `set -uo pipefail` at 173; orchestrator `2,158p` with it at 159. |
| AC-10 | satisfied | The `(st)` block builds its own fixture with a real bare `origin`, a second clone that pushes, and no hand fetch — so a build that dropped the arm's own `git fetch` fails (st2). (v13)/(v14) are a matched fire/no-fire pair against the **real** gate with `LEAN_GATE` unset, each on its own fixture tree. |

## Independent verification

Everything below was run by this review session from a checkout of the reviewed head. The mutation
probe wrote only to `/tmp`; the reviewed checkout was never mutated.

**Suites, run cold with `CLAUDE_CODE_SESSION_ID` / `RUN_ID` / `LEAN_RUN_MODEL` / `LEAN_GATE`
scrubbed** — all three exited `0`:

- `lean-gate-selftest.sh` — all green, (st1)–(st17) all present and passing.
- `orchestrate-lean-selftest.sh` — all green, (v1)–(v14) all present and passing.
- `scenario-liveness-selftest.sh` — **95 passed, 0 failed**; both `(lean-reentry)` and
  `(lean-reentry-nv)` legs reached their terminal write. This is the suite the rebase broke, so it
  was run rather than inherited.

**shellcheck** `-e SC1091,SC2015,SC2181` on all five changed scripts: clean. Run locally at 0.11.0;
CI's `lint-and-selftests` job runs the pinned version and **passed on this head**, so the local
version skew is settled empirically rather than by argument.

**Mutation-catalog rows — applied verbatim, not assumed.** All three new rows were fed to `sed`
exactly as written in the TSV, against copies of the branch's own files:

| Row | Result |
| --- | --- |
| `staleness-advance-is-the-trigger` | applies to exactly 1 line (`lean-gate.sh:1450`, the `overlap` test), mutant is `bash -n` valid |
| `staleness-fetch-failure-as-clean` | applies to exactly 1 line (`lean-gate.sh:1428`), `bash -n` valid — the `✗` in the anchor survives BSD sed |
| `staleness-preflight-arm-widened` | applies to exactly 1 line (`orchestrate-lean.sh:350`), `bash -n` valid |

None is a silent no-op, which is the failure mode that makes a catalog row read as coverage while
never being applied.

**Lane note, not a finding.** `tools/mutation-pair-map.tsv:47` gives `orchestrate-lean.sh` a second
killer (`scenario-liveness-selftest.sh`), so its mutants are deferred-to-nightly on the PR lane —
`staleness-preflight-arm-widened` is graded nightly rather than at PR time. That trade is documented
in the pair-map row itself and predates this branch; the row is valid, and its verdict simply lands
a day later. The two `lean-gate.sh` rows are unaffected and are graded at PR time.

**The predicate, calibrated on its own PR — and this round it is a matched pair.** Run from this
checkout with the branch's own gate:

```
[lean-gate] staleness: ticket arm clean — #515 is still OPEN.
[lean-gate] staleness: base arm clean — origin/main moved, but into no file this branch touches.
Bare advancement is not the trigger.
rc=0
```

Round 1 ran the same command on the same branch and got **rc=7** naming `tools/mutation-catalog.tsv`.
The rebase removed exactly that overlap and the answer flipped to rc=0 — on real data, across a real
base advance, not a fixture. Hand-checked: `origin/main` moved 12 files since the branch point, the
branch touches 9, and `comm -12` on the two sorted sets is **empty** — so the gate's answer matches
an independent computation of its own predicate. That is a fire/no-fire pair on production data, and
it is the strongest evidence available that the arm discriminates rather than being a constant in
either direction.

**Repo conventions:** no frozen file touched (`plugin.json`, `CHANGELOG.md`, `marketplace.json` all
absent from the diff); `Changelog:` trailers present on all six commits; `feat(dev-pipeline):` is the
honest verb for a new capability in the repo where the tooling is the product.

**Scope.** No creep. The one file in the diff that no AC names — `scenario-liveness-selftest.sh` —
is there because the rebase onto `#521` made that suite a second killer for `orchestrate-lean.sh`,
so its `(lean-reentry)` leg began driving the new subcommand against fixtures with nothing to answer
with. Both fixture gaps were the feature failing **closed** as designed (an unanswerable tracker
stub, and a `refs/remotes/origin/main` hand-set with no remote behind it). The fix adds a `--json
state` arm and a real bare origin pushed at the branch point; the base arm therefore answers
"not moved" there, and its firing path stays owned by (v13)/(v14). The remote swap is contained —
it is the last use of that ref in the file, and the push restores the remote-tracking ref the
earlier legs set by hand.
