# lean review verdict — #392

verdict=approve
run_id: review-392-2
session_id: ff980a53-1d08-4deb-ab16-d54a46c6e41a
rounds: 2
pr: #400
reviewed_head: b4eba3114a043fde4553d50cb62574fe3f1803e6
reviewed_patch_id: c6ffc5e38c9a009897f71f106eee7ef90a34e180
inherited_patch_id: 86d23d218593c533c63de573199d83d5b5b51caa
inherited_from_verdict: f42c2a16633852285fdb1afe7160880d063693f8
model: unknown

# Review round 2 — PR #400 / issue #392

Range read: `f42c2a1..HEAD` (the round-2 commit), inheriting patch `86d23d218593` — round 1's
full-branch coverage. Round-1 findings re-read from `docs/plans/second-shift-392-lean-verdict.md`
before scoring, and `lean-gate.sh` read in full despite being outside the delta, since every AC
this round is about whether that unchanged file's guard is observable.

Reviewer: `review-lead` panel of 7 (0 dark; `unit-test-mutation-reviewer` died on its first
dispatch and returned on the automatic retry) + operator-run execution probes.

## Verdict: approve

All seven `AC-n` satisfied. Every round-1 blocker and warning is discharged, and the two
discharges that were mechanical claims rather than prose — the recorded-effect kills and the
composed verdict paths — were re-verified by execution here rather than taken from the PR body.

## Per-AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | Unchanged behavior, strengthened assertions. `(iz1)` and `(iz2)` now each require all three tokens the AC names — `no verifying lane configured for 'acme'`, the config path, and `allowUnverified` — closing round-1 W2, where `(iz2)` asserted only the third. `(i-392)`/`(i-392b)` cover the opted-out green path. |
| AC-2 | satisfied | `(iz3)` unchanged; round 1 pinned its killing direction (dropping `any_verifying=1` reds the suite). |
| AC-3 | satisfied | `(iz4)` unchanged — a `when`-scoped `extraLanes` entry missing on the diff keeps the guard inert through `el_count`, never through execution. |
| AC-4 | satisfied | Two `tools/mutation-catalog.tsv` rows anchor the guard by pattern. Verified independently, not from the PR body: each sed applies with `sed -E` to **exactly one** line, leaves `bash -n`-valid output, and is killed by `lean-gate-selftest.sh` — `catalog::lean-gate-zerolane-record` by `(i-392b)` as the sole failure, `catalog::lean-gate-zerolane-milestone` by `(iz1b)` as the sole failure. `kill_set_for()` resolves `lean-gate.sh` to the same-stem `lean-gate-selftest.sh` and no pair-map row, so the paired suite the AC names is the one that kills. A diff-scoped sweep (`--mode pr --base main`) reproduces the PR body's figure exactly — `applied=12 killed=9 survived=3`, both catalog rows scored KILLED via `lean-gate-selftest.sh`, survivor ids exactly the three baselined rows (`cmp-eq::1`, `default::1`, `default::2`). Re-baseline clause: this round's diff contains no `.sh` guard at all, so no ordinal moved and those three are untouched. |
| AC-5 | satisfied | Both halves render the three-consumer sentence. `schema/second-shift.config.schema.json`'s `allowUnverified.description`: "…Stage 6 refuses an all-skipped verifySummary, preflight withholds its pipeline-ready verdict, and lean-gate.sh milestone 3 reds naming the opt-out…". `docs/config-schema.md:9` carries the matching prose. `Changelog:` trailer present on the branch (a real block on `3c5f583`, `none` on the other two); `render_bullet` reads blocks per-sha with a whole-block `none` no-op test, so the real entry ships and the two no-ops render nothing. |
| AC-6 | satisfied | Both legs present **and live**. Neutralizing the guard (`if false`) reds exactly the two new legs and nothing else: `(lean-zv-skip)`, plus both of `(lean-zv-red)`'s assertions — 63 passed / 3 failed against a 66/0 baseline. The fixture edit that round 1 called a silencing is now an extension: `(lean-zv-red)` strips `allowUnverified` from `$LEAN_CFG` on the isolated `EL_TREE` substrate and composes the red into `all` stopping at milestone 3 with milestone 4 never satisfied. |
| AC-7 | satisfied | Both recorded effects are killable, proven by execution. Deleting the opt-out branch's `append_line` → `lean-gate-selftest.sh` rc=1, sole failure `(i-392b)`; re-keying `fail_milestone 3` → `2` → rc=1, sole failure `(iz1b)`. Both mutants left every suite green in round 1. |

## Blockers

None.

## Warnings

| # | Finding |
| --- | --- |
| W1 | **The doc↔schema coupling AC-5 asserts is a value, not a mechanism.** Round-1 W3 found the schema half stale while the prose half had been updated, and nothing red. Round 2 sets the value right but adds no guard, so the next consumer added to one half and not the other drifts exactly the same way. The coupling is not byte-anchorable — a markdown table cell and a JSON string cannot share a `verbatim` block — so `CLAUDE.md`'s remedy is the **DROPPED** form: a row in `scripts/lockstep-manifest.tsv` recording the pair and the reason it stays reviewer-guarded, the way the adjacent `preflight ↔ verifyctl` zero-verifying-lane predicate already is (`lockstep-manifest.tsv:80-87`). Warning, not blocker, on three grounds: the coupling predates #392 (the Stage-6 and `preflight` clauses were unrecorded too), no AC requires it, and round 1 classed the same defect a warning — escalating its residual in round 2 would invert that. Independently raised by `unit-test-mutation-reviewer` at confidence 80. |

## Suggestions

- **S-1** `scenario-liveness-selftest.sh` is not in `lean-gate.sh`'s mutation kill set — `kill_set_for()` returns the same-stem suite plus pair-map rows, and there is no pair-map row for this guard. So `(lean-zv-skip)`/`(lean-zv-red)` compose the verdict paths but never contribute a mutation verdict. That is the tier map working as designed (composition to the scenario suite, mutation to the paired suite) and adding a pair-map row would put a minute-scale suite behind every `lean-gate.sh` mutant. Noted so the split is visible, not as a change request.

## Round-1 findings — disposition

| Round-1 | Status |
| --- | --- |
| B-1 (opt-out `append_line` unkillable) | **Fixed and verified.** `(i-392b)` asserts the record on `$PROG`; it is the sole failure under the deletion, in `lean-gate-selftest.sh` and — via `(lean-zv-skip)` — in `scenario-liveness-selftest.sh` (65/1). |
| B-2 (`fail_milestone` number unkillable) | **Fixed and verified.** `(iz1b)` asserts the `\| milestone-3 \| attempt \|` record; sole failure under `fail_milestone 2`. |
| B-3 (no composed coverage for either verdict path) | **Fixed and verified.** See AC-6. `(lean-el-red)` does not subsume `(lean-zv-red)`: a lane that ran and failed and a lane that was never configured red through different predicates, which is why #379 shipped both of its own legs one commit earlier. |
| W1 (AC-4's oracle cannot observe the guard; no red-on-mutation demo) | **Fixed.** AC-4 now names the catalog tier and states why the generic tier cannot reach ordinals 11/67 under `K_BUDGET=2`; the round-2 commit body carries the red-on-mutation table. The withdrawn "10 applied, 7 killed" citation is replaced by a delta whose two added mutants are the catalog rows. |
| W2 (`(iz2)` under-asserts) | **Fixed.** All three tokens asserted. |
| W3 (schema stale) | **Fixed** in value; see this round's W1 for the residual. |
| S-1 (no fixed-key + `extraLanes` fixture) | Declined. Accepted: round 1 established no live mutant survives from the gap, so a case there is boilerplate under the repo's liveness-not-boilerplate rule. |
| S-2 (setup `lanes[]` run before the guard reds) | Declined. Accepted: matches the spec as written, and round 1 classed it not a deviation. |

## The spec amendment, considered

`docs/plans/second-shift-392-lean.md` was amended in the same commit as the fixes — the file
scope gained `scenario-liveness-selftest.sh` and the schema, AC-5 gained the schema half, and
AC-6/AC-7 are new. A spec amended to match its diff is a blocker; this is the other direction.
Every amendment **adds** an obligation the round-1 review found missing and the diff then meets,
and the one reworded AC (AC-4) replaces an oracle round 1 proved structurally incapable of
observing the guard with one that demonstrably kills it. Nothing was narrowed to fit what
shipped: AC-4's re-baseline clause survives verbatim, and no AC lost a requirement. Recorded
here so the amendment is visible in the ledger rather than inferred from the diff.

## Re-stamp note — same round, not a new one

This record was first written at `b24447f`, then re-issued unchanged on top of the
`Merge branch 'main' into lean/second-shift-392` commit that GitHub's "Update branch" button
created. **No new review round was spent, and none was owed.** The merge changed no line of
this branch's own work:

- The declared freshness arm passes with the patch id unchanged — the branch's diff against
  `origin/main` is byte-identical to the one this round read.
- `origin/main`'s new commits touch none of the files under review: `lean-gate.sh`,
  `lean-gate-selftest.sh`, `scenario-liveness-selftest.sh` and `tools/mutation-catalog.tsv` are
  all untouched by them.
- The two files that do overlap (`docs/config-schema.md`, the schema) still carry exactly this
  branch's one-line clause each in `origin/main...HEAD` — the merge preserved them intact.

The re-stamp exists only because `check-lean-chain.sh`'s **inferred** freshness arm compares
`VERDICT_COMMIT` to `PR_HEAD_SHA` with a two-dot `git diff`, so after a merge from base it
reports every commit the base gained since the branch point as a change to the branch — twelve
files here, all of them the base's. The declared arm, which is merge-invariant, passes on the
same tree. The remedy is the one #372 established: prove the patch is unchanged and re-stamp
the same round. Filed separately as a gate defect.

## Verified green (not findings)

- `lean-gate-selftest.sh` and `scenario-liveness-selftest.sh` both pass with
  `env -u CLAUDE_CODE_SESSION_ID` and **without** `SKIP_STRESS` — the scenario suite at 66/66,
  matching the PR body's claim.
- `shellcheck -e SC1091,SC2015,SC2181` clean on both changed suites; `jq empty` clean on the
  schema. `mutation-sweep-selftest.sh` green — it is what lints the two new catalog rows.
  `check-lockstep-pairs.sh`, `check-frozen-files.sh` and `check-changelog-trailer.sh` all clean
  against the base branch. `check-lean-chain.sh` does not run locally (`LEAN_BRANCH_PREFIX` is a
  CI-job variable), so it is neither evidence for nor against; the round-1 record it would read
  is superseded by this one.
- The PR body's `scenario rc=1 — (lean-zv-skip)` citation is accurate. My own first attempt at
  that probe produced a **false kill** and had to be discarded: writing the mutant with `mv`
  dropped `lean-gate.sh` from 0755 to 0644, which trips the suite's own
  `(lean) … not executable` precondition and skips the entire lean leg (39 passed / 1 failed).
  Re-run write-through, the mutant reds `(lean-zv-skip)` and nothing else (65/1). Recorded
  because the two runs report the same rc for opposite reasons.
- Reviewer panel: 7 dispatched, 7 returned, 0 dark. security / performance / maintainability /
  complexity / test-coverage / scope-completeness / unit-test-mutation all `approve`. The panel's
  only finding is this round's W1. `scope-completeness-reviewer` self-corrected the dispatch base
  to the true merge-base `3eb0e53` and classified the branch's full scope, PASS.
- Probes applied to a working-tree copy of `lean-gate.sh` and reverted with `cp` from a pristine
  snapshot, never `git checkout`; `git status --porcelain` confirmed empty (mode included) after
  each. `rc` is the authority throughout, and every kill is named by its failing case rather than
  inferred from a count.
