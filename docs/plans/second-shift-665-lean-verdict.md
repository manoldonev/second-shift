# lean review verdict — #665

verdict=approve
run_id: review-665-2
session_id: 970a0278-03a4-420b-9ed9-3fa38281553e
rounds: 2
pr: #740
reviewed_head: d14222ca0b67ab3f896ec3843153dddab6e59f82
reviewed_patch_id: f63be11d50768fee6efc7940d3005fdd7304f760
inherited_patch_id: 3f2800c7b3889bffb8343741c98e33be744c06c9
inherited_from_verdict: 8188e7062e27a085abaf4b66fa4fac37654c9915
fidelity: not-applicable
model: opus
capabilities: pr-marker

Round 2, inheriting the coverage of patch `3f2800c7b388` (round 1, head `f68e1d81`). Delta
range `661cca49..HEAD`, 5 files — the three workflow files, the lean spec, and `docs/testing.md`.
Read wider than the range where the delta was misleading: the whole branch contribution
(`origin/main...HEAD`, 12 files) was re-derived for the inherited ACs, since round 1's tree
predates the base merge.

All 9 ACs satisfied. Round 1's single blocker is discharged, and both of its fixable warnings
with it. No blockers. **approve.**

## Round 1 findings — disposition

**B1 (blocker) — FIXED and independently verified.** `lint-and-selftests` is green at the
reviewed head. Three independent confirmations, not one:

| Check | Result |
| --- | --- |
| CI step 7 `actionlint (workflow static analysis)`, job 99537009787, head `d14222ca` | `success` |
| the six previously-skipped register guards + the Linux sweep (steps 8–16) | every one `success` — nothing is unanswered on this head any more |
| `actionlint` 1.7.7 (the pinned CI version) run locally over the whole `.github/workflows` surface with shellcheck integration live | 0 findings, rc=0 |

The local run is not a restatement of CI: it was proved non-vacuous by reverting exactly one of
the four fixed sites to its single-quoted form in an isolated copy, which reproduces round 1's
red precisely — `file-issue-on-red.yml:68:9: shellcheck reported issue in this script:
SC2016:info:14:10`. So the green means the check ran, not that it was skipped.

**The "byte-identical emitted text" claim holds, by execution rather than by eye.** All four
requoted lines were extracted straight out of `661cca49` and `d14222ca` and executed under
`bash`; stdout was compared by md5.

| Site | old → new | md5 |
| --- | --- | --- |
| `file-issue-on-red.yml` `printf` | identical | `ff217d230be1` |
| `mutation-merge.yml` `LEAD` (survivor) | identical | `3bfa4a6c7e4d` |
| `mutation-merge.yml` `LEAD` (infra) | identical | `ad47307eec04` |
| `mutation-sweep.yml` `echo` (no `RED:`) | identical | `51c41b406b7c` |

4 of 4 byte-identical, same exit codes. None of the four contains a `$`, a backslash or a `!`,
so the switch to double quotes moves nothing.

**W1 (warning) — FIXED.** Both lines are reworded cadence-neutrally ("somebody's sweep", "a
wholesale shard"), which is the stronger fix: they cannot go stale again on the next cadence
change. Re-derived the whole census independently rather than inheriting it — every surviving
`nightly` in tracked non-plan files is one of three legitimate classes: `nightly-guards.yml`'s
selftest lanes, which this change does not touch and which still run nightly
(`docs/testing.md:131/163/288/341/394/475/500/697` — `:163` names `wholesale-selftests`
explicitly); historical narrative, which AC-5 expressly leaves alone (`:1304/1420/1430`); and the
retained `deferred-to-nightly` enum under D-7 (`:1635`, whose surrounding prose correctly routes
the reader to the merge-time sweep). No surviving comment routes anyone to a deleted lane.

**W2 (warning) — FIXED, and the fix is correct on both lanes.** `mutation-merge.yml`'s `file-red`
now gates on `!= 'success'`. `sweep` carries no `if:` and no `needs`, so it cannot resolve
`skipped` — the gate is exactly `{failure, cancelled}`, with no new false-positive path. The
degradation is right too: on `cancelled` the `classify the red` step (`if: failure()`) does not
run, outputs are empty, and the `||` fallbacks supply the body — which is precisely the case the
fallback text now names. `mutation-sweep.yml`'s `file-audit-red` widens to
`failure || cancelled` over `needs.*.result`; `!= 'success'` is unavailable there because the
operand is an array over two jobs.

**W3 (warning) — carried forward, unaddressed, still not blocking.** The dedup/classify shell in
YAML has no execution coverage. D-1's reasoning (no new `*.sh`, so no paired-selftest obligation)
is the repo's own ratified exemption and still applies; building a harness for YAML-embedded
shell is a program, not a fix for this PR. Independently reached by `test-coverage-reviewer`,
which classified it pre-existing at confidence 65.

## Warnings

**W1-r2 — `QUEUED, NEVER CANCELLED` overstates what the concurrency block guarantees.**
`mutation-merge.yml:21-25` reasons that `cancel-in-progress: false` means "every merge is graded
on its OWN diff, and a cancelled run's guards would have no lane left to catch them". GitHub
holds at most one *pending* run per concurrency group: when a run is queued behind an in-progress
one, any **previously pending** run in that group is cancelled. So on a burst of three merges
inside one sweep window — plausible here, since the un-deferred worst case is estimated at 30–45
minutes — the middle merge's run is dropped before it starts, and because no job ever executes,
`file-red` does not fire either. That merge's guards go ungraded *and* unreported, which is the
exact harm the header says the setting prevents.

Not a blocker, and not an argument for `cancel-in-progress: true`: `false` is strictly the better
of the two, D-6 is committed operator authority, and the monthly wholesale audit remains the
backstop. No AC is unsatisfied — AC-1 binds what the workflow does when it runs, not that every
push gets a run. What is wrong is the absolute claim in the comment, in a repo where AC-5 exists
because comments that misdescribe a lane are treated as defects. Worth a sentence acknowledging
the pending-supersession case, or a follow-up if the gap itself is judged worth closing.

## Suggestions

- **This class of red is only discoverable at CI.** `CLAUDE.md`'s mandated local recipe runs
  `shellcheck` over `*.sh`, `jq` over `*.json`, and the selftest sweep — no `actionlint`; and
  `check-workflows-selftest.sh` says in its own header that shellcheck-over-`run:` is "actionlint's
  job and runs in CI". That is a defensible division, but the pinned binary needs no docker and
  runs the whole surface in seconds, which is what made the independent verification above cheap.
  AC-9 binds the outcome; nothing yet makes it reachable before pushing.
- `mutation-sweep.yml:277-280`'s new comment says a cancelled shard "leaves `merge` `skipped`".
  `merge` carries `if: always()`, which runs on a cancelled dependency, so it would more likely
  run than skip. The gate is correct regardless — it matches on `sweep` being `cancelled`, whatever
  `merge` does — so this is the stated reason being imprecise, not the mechanism being wrong.

## AC scoring

| AC | Verdict | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | Inherited, re-verified at this head. `check-lockstep-pairs.sh`: `PASS: seam-scrub (subset-of)`, 29 anchors / 0 failed, and `MUTATION_SWEEP_NO_DEFER` present in BOTH `SEAM_SCRUB` copies (`preflight.sh:60`, `lean-gate.sh:3593`). The count reads 29 against round 1's 30 — the branch is not the cause: the LOCKSTEP marker surface is byte-identical to `origin/main` (218 markers / 55 files on both sides), so the move arrived with the base merge. CI step 11 `contract lockstep blocks` green. |
| AC-2 | satisfied | Both lanes call `file-issue-on-red.yml`; dedup is a `startswith` over the open-issue listing, keys namespaced per lane; green files nothing. Round 1 scored this "qualified by W2" — **that qualification is now discharged**, and this delta is what discharges it. |
| AC-3 | satisfied | `cron: '17 3 1 * *'` — monthly, nightly gone. `workflow_dispatch` with the `seed` input intact, and the seed-mode resolution at `:109-115` unchanged. |
| AC-4 | satisfied (as scoped by the spec's restatement + D-7) | Re-derived, not inherited: `emit_row "$g" "deferred-to-nightly"` appears in the branch diff as a **context** line only — no `+`/`-` touches it, so the enum is byte-unchanged. `ci.yml`'s sole `MUTATION_SWEEP_NO_DEFER` occurrence remains the prohibition comment at `:200`. This delta does not touch `mutation-sweep.sh` at all. |
| AC-5 | satisfied | "Where it runs" is the three-lane table; W1's two residual wordings now fixed; full `nightly` census re-derived above with every survivor classified. CLAUDE.md's two references are `nightly-guards.yml`/install-topology — a live lane, out of scope per #666. |
| AC-6 | satisfied | `tools/mutation-sweep-selftest.sh` ran **cold** in CI at this head — `pass 105s`, and `[mutation-sweep-selftest] all cases passed`; the suite has no row in `tools/selftest-cache-inputs.tsv`, so it can never be served from cache. The sweep summary reads `77 scored, 76 run, 1 served from cache, 0 failed`. Non-vacuity was established at round 1 by mutants M1 and M2, over code this delta does not touch. |
| AC-7 | satisfied | Every branch commit carries a trailer; `0d834aba` carries the substantive one with `Migration: none.`, and the three fix commits carry a bare `Changelog: none` with no trailing prose — so nothing renders spuriously. |
| AC-8 | satisfied | `writing-tests/SKILL.md:55-57` reads "Those **three** are the only places it runs" and names `mutation-merge.yml`. |
| AC-9 | satisfied | The new AC, and its oracle is CI's own step: step 7 `success` at head `d14222ca`, plus the independent pinned-binary run and the non-vacuity probe above. |

**The spec amendment is additive and does not weaken the set.** `docs/plans/second-shift-665-lean.md`
is in this round's delta, so it was read as a possible after-the-fact edit to match the diff. It is
not one: the diff is `9` insertions and `0` deletions — no existing AC was reworded or relaxed. AC-9
adds an obligation that was previously unbound (round 1's blocker sat outside the AC set precisely
because nothing graded the lint), and it is disclosed under Departures with its origin. That is the
strengthening direction, which the rule against post-hoc amendment does not prohibit.

## Merge-boundary state (recorded, not a blocker)

`pr-gates` is red on its final step only — step 6, "lean chain reconciliation". Steps 3-5 (frozen
files, changelog trailer, pipeline chain) all pass. That is the expected pre-verdict state: the
chain cannot reconcile until this record is committed. Every correctness lane is green at
`d14222ca` — `lint-and-selftests`, `selftests (macos, bash 3.2)`, and `mutation-sweep-pr`.

## Panel

`review-lead` fan-out over the delta, **5 of 5 returned, none dark**: security, maintainability,
complexity, test-coverage, scope-completeness. **Zero blockers, zero findings at or above
warning.** Reduced from round 1's six per the prior-round rule — `performance-reviewer` was not
re-selected, having returned nothing at round 1 against a delta that is CI gating conditions and
prose. `a11y` and the design-fidelity dimension were not routed: no changed path matched
`stageParams.webComponentGlobs` (unset → default `apps/web/**/*.{tsx,jsx}`). Scope Completeness
Gate: passed.

The one nit (scope-completeness, confidence 92) is the D-6 concurrency departure from the issue's
literal "coalescing" wording — already recorded at round 1 as not-a-finding on committed operator
authority, and re-confirmed here. Security's three suppressed items were all checked rather than
taken on their confidence scores; its highest (60) posits that `!= 'success'` also matches
`skipped`, which is true in general and unreachable for this job, as set out under W2 above.

Both warnings above are hand-derived. The panel reads the diff; W1-r2 needs GitHub's concurrency
semantics, and the local-recipe gap needs the check surface — neither is in the diff.

**Fidelity: not-applicable.** The spec has no `## Design` section and the repo declares no
`design.provider`.
