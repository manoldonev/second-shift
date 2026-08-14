# lean review verdict — #527

verdict=approve
run_id: review-527-1
session_id: c14e2d84-272b-4318-8b40-351126204b00
rounds: 1
pr: #545
reviewed_head: 98e29f8ae7c1cdf84cf4d699abe31abbc55b8696
reviewed_patch_id: c699fb78bdbdd2018eca683eba10cf0116745464
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: opus
capabilities: pr-marker

Round 1. Full branch diff (`bff1db5..98e29f8`) — `delta` printed FULL range, nothing to inherit.

## Verdict

**approve.** 8/8 AC satisfied. No blockers. Four warnings, all outside the AC set or
pre-existing-class, none of which costs a round to fix.

## Per-AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 — the sweep names its own infra class | satisfied | `tools/run-selftests.sh:558-574`. `INFRA` tallied at the same site the per-suite `rc=125` class is printed; condition is `-eq "$count"` (ALL, never ANY); reconciliation `exit 2` still precedes it (`:551`); summary carries `($INFRA infrastructure)`. Guards in three polarities plus the no-verdict case re-bound from `-ne 0` to `-eq 3`. |
| AC-2 — milestone 3 honors it, uniformly | satisfied | One resolver, `lane_failure_class` (`:3325`), applied to the fixed keys (`:3378`) and to `extraLanes` (`:3459`). Setup `lanes[]` untouched, as scoped. |
| AC-3 — an infra red charges no fix attempt | satisfied | `fail_milestone` returns `$INFRA_CLASS` **before** `append_attempt` on the recording path and before `attempt_count` on the observe path. Verified no pre-existing caller passes class 7 — the live classes are 1, 5 and 6 only — so the new branch cannot change any existing path. |
| AC-4 — the interrupted budget is per-milestone | satisfied | `interrupted_budget_for` (`:290`), `INTERRUPTED_BUDGET_M3=8`; resolved once in `run_milestone` and reused by the announce, the observe prediction and the refusal. No stray `INTERRUPTED_BUDGET` reader remains. |
| AC-5 — `progress <issue> --infra` | satisfied | `infra_token`/`m3_runner_records` (`:1653-1677`). Issue-keyed glob, `m3infra-v1:` generation prefix, never empty, no `ensure_progress_file`, mutual exclusion validated at parse time beside `--satisfied`'s guard. |
| AC-6 — the scheduler routes on the delta | satisfied | `orchestrate-lean.sh:503-518` and `:560/:577`, read on both sides, conjunction at `:592`, existing continuation path and existing `--max-continuations`. Fail-closed on an unreadable read, byte-identical in shape to its `progress_token` sibling. |
| AC-7 — documented where a consumer reads it | satisfied | Gate header `:165-177` beside the 0/1/2/4/5/6/7 taxonomy; `docs/config-schema.md` as a `commands.<host>` lane contract naming the OR-2 exposure; `docs/testing.md:39`. `--help` range widened to `2,237p`, which is exactly the last header line. |
| AC-8 — the guards | satisfied | 24 new/changed cases, all confirmed to run and pass in a repo checkout. The composed leg is unconditional (absence of the scheduler is a `fail`, not a skip). Its last bullet's re-baseline obligation is vacuously met — see W2. |

## Probes

Every new assertion was probed for fire/no-fire from an isolated worktree. All mutants killed;
`E0` is the unmutated baseline.

| Probe | Mutant | Result |
| --- | --- | --- |
| E0 | none — `lean-gate-selftest.sh` baseline | 387 pass / 0 fail |
| E1 | `lane_failure_class` never matches the reserved code | KILLED 381/6 — (ic1)(ic2)(ic4)(ic5)(ic6). (ic5) shows the harm directly: `rc=4`, the fix budget spent by infra reds |
| E2 | `fail_milestone`'s infra early-return deleted | KILLED 382/5 — (ic1)(ic2)(ic4)(ic5)(ic6). The rc still comes back 7; the *record* is what catches it |
| E3 | `infra_token` drops the live-runner subtraction | KILLED 385/2 — (ir4)(ir7) |
| E4 | `interrupted_budget_for` collapses back to one budget | KILLED 385/2 — (ib2)(if6) |
| E5 | the issue-keyed glob narrowed to `m3_paths`' computed key | KILLED 385/2 — (ir4)(ir7), the D-4 regression exactly |
| A1 | the routing conjunction forced true | KILLED — (oi1)(oi3)(oi4) |
| A2 | both infra reads removed | KILLED — (j3) reds, which the pre-#527 single-predicate form would not have |
| B1 | ANY instead of ALL in the runner | KILLED — the mixed case, the fail-open direction the spec names |
| B2 | the reserved `exit 3` collapsed back to 1 | KILLED |
| B3 | the `INFRA` tally never incremented | KILLED |
| C1 | **only** the post-spawn `infra_after` fail-closed guard weakened | **SURVIVED** — see W1 |
| D1 | the same weakening on the **pre-existing** `tok_after` guard | SURVIVED — which is what makes C1 a pre-existing class, not a new gap |

## Warnings

**W1 — the post-spawn `infra_after` fail-closed guard has no failing case of its own.**
`orchestrate-lean.sh:577`. `INFRA_FAIL=1` is a blanket seam on the fake gate, so it always trips
on the pre-spawn read at `:560` — (oi5) asserting `spawn_count == 0` is the proof. Replacing the
post-spawn guard with `infra_after="$infra_before"` — silently reading an unanswerable residue as
"unmoved", which is the pre-#527 bug restored — passes the whole suite (rc=0, zero FAIL lines).

Not a blocker, because it is not a new gap: I ran the same mutant against the **pre-existing**
`tok_after` sibling at `:574` and it survives identically. The new read follows the established
shape byte for byte, and the shipped behavior is genuinely fail-closed. A follow-up wants a
side-selective seam (a streamed `INFRA_FAIL`, or an `INFRA_FAIL_AFTER`) so both post-spawn guards
become reachable — for `progress_token` as much as for `infra_token`.

**W2 — AC-8's re-baseline sentence describes something the diff does not do.**
The spec says "`tools/mutation-baseline.tsv` is re-baselined in this same diff, and any
`tools/mutation-catalog.tsv` row addressing those functions is re-anchored". Neither file is in
the diff. The **outcome is correct** — I verified it independently rather than taking either
artifact's word:

- Ordinals: for `cmp-eq`, `default`, `fail-open`, `cmp-z` and `logic`, the site list at ordinals
  1-2 (the whole swept window at `K_BUDGET=2`) is identical between `bff1db5` and `98e29f8` on
  all three edited guards. The only movement is *within* a site — `sed -n '2,214p'` → `'2,237p'`
  and `'2,158p'` → `'2,160p'`, on a `cmp-z` site neither guard baselines. No row re-keyed.
- Anchors: all 23 catalog rows on the three guards still apply at head under `sed -E`, which is
  what `mutation-sweep.sh:1579` uses. No drift.

What I would change is the **PR body's reasoning**, not the outcome: "every generic ordinal is on
a guard the PR lane defers" does not establish that no ordinal re-keyed. PR-lane deferral only
changes *when* the guard is swept; a re-keyed ordinal produces a survivor absent from the baseline
and reds the **nightly**. The load-bearing fact is the one above — the swept-window site list did
not move. Anyone reusing the stated rule on the next PR will skip a re-baseline that is genuinely
owed. Reword the spec bullet to "no ordinal was re-keyed, so no baseline row changed".

**W3 — `mutation-sweep-pr` computed zero verdicts on this PR, so its green is vacuous.**
All three touched guards report `deferred-to-nightly`, 1s wall. That is not caused by this diff:
I timed `tools/run-selftests-selftest.sh` at **7.28s on the base** and 7.49s at head, both over
the 5s bar, so the new `mutation-slow-suites.tsv` row records a pre-existing fact rather than
creating the deferral — the guard had simply not been measured, since it only enters the PR lane
when `run-selftests.sh` is in the diff. The row and its consequence are correct and declared.
Flagging it so the lane's green is not read as evidence: on this PR the mutation evidence is the
probe table above, not CI.

**W4 — the PR title has no conventional-commit prefix, which costs the minor bump.**
`derive-release.sh:146` matches `^feat(\([^)]*\))?:` against each commit's `%s` over
`$LAST_TAG..HEAD` on main. A squash merge leaves one commit whose subject is the PR title, and
`An infrastructure kill is told apart from an idle session` matches nothing, so this releases as a
**patch**. The branch's own commit is `feat(dev-pipeline): …` with a real consumer-visible
`Changelog:` line, and CLAUDE.md is explicit that a new capability here is `feat:` — a new
`progress --infra` flag, a reserved cross-repo exit-code contract and a new per-milestone budget
qualify. Retitle to `feat(dev-pipeline): an infrastructure kill is told apart from an idle
session`. Outside the AC set and not a commit, so it costs no round.

## Suggestions

- `infra_token`'s `[ "$n" -lt 0 ] && n=0` clamp is untested and is reachable on the shipped
  topology, not only under OR-1: the ceiling arm deliberately keeps the pid record while the
  runner lives, so a `concluded` row can coexist with a live record and drive `live > unclosed`.
- `m3_runner_records`' `found` counter feeds only the OR-1 stderr diagnostic. Every `gate_ir`
  helper drops stderr and the scheduler's `infra_token` drops it too (`2>/dev/null`, matching its
  sibling), so the line is asserted nowhere and invisible in the lane log — it is operator-facing
  on a hand run only.
- The header describes the surviving residue as four terms — flushed `started`, no `concluded`,
  a dead recorded pid, **and no marker** — then says "THE FULL CONJUNCTION IS KEPT". The code
  implements two of the four; there is no marker term. A runner that stamped its marker and died
  before the `concluded` row reads as a death. The direction is one bounded extra re-spawn, so
  the behavior is fine; the comment overstates what it implements.
- `rc=125` remains conflated: a suite that genuinely exits 125 is classed infra exactly like a
  worker that wrote no verdict, so an all-125 sweep now exits 3 and charges no fix attempt. The
  classification is pre-existing and the AC-1 fixtures deliberately lean on it; the new
  consequence is bounded twice and documented. Worth a line in `docs/testing.md` next time that
  file is touched.

## Strengths

- Leg 9 of `scenario-liveness-selftest.sh` is the writer↔reader obligation discharged properly: a
  real `kill -9` on the gate's own process group, residue the real gate left, a run that must
  still reach `| milestone-5 | satisfied`, and an idle-first-spawn arm proving the leg is not
  green for any other reason. The lockstep DROPPED entry names that case instead of pinning a
  literal — the sanctioned answer for two sites sharing a number.
- (ic8) drives the one state where the two rules collide — a genuinely spent budget through the
  real writer — and asserts the infra and ordinary classes side by side. (ic6)/(ic7) then run the
  **real** runner into `commands.acme.test` in both polarities, so a runner returning 3
  unconditionally reds.
- (j3) re-derived over both token spaces rather than left on the old single-predicate form: my A2
  mutant reds it, and would not have red the pre-#527 assertion.
- The delta-not-level choice is pinned by (oi3) rather than only argued in prose.

## CI on `98e29f8`

`lint-and-selftests` pass · `selftests (macos, bash 3.2)` pass · `mutation-sweep-pr` pass
(0 verdicts — see W3) · `release-pr-gates` skipped · `pr-gates` fail, and the log names exactly
one arm: `no committed verdict record (a file named *-527-lean-verdict.md)`. That is this round's
own output, the expected pre-review state, and no other arm fired.

## Panel

8 selected, 8 returned, none dark. security / performance / maintainability / complexity /
test-coverage / pipeline approve with no findings; unit-test-mutation and scope-completeness
approve-with-nits. Scope Completeness passed — no unsatisfied item. `a11y-reviewer` and the
design-fidelity dimension were not routed: no changed path matches
`stageParams.webComponentGlobs` (unset, so the shipped default `apps/web/**/*.{tsx,jsx}`).
