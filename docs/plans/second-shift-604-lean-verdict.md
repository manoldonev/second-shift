# lean review verdict — #604

verdict=approve
run_id: review-604-3
session_id: 8c5e77cb-a438-4d3e-8dca-045c773b01ee
rounds: 3
pr: #606
reviewed_head: e4eff02e60dfae638dccabdb9ffdbc895d66983a
reviewed_patch_id: 9634dc2d416991305b03a9a2fd3cf1bade5ddd4d
inherited_patch_id: b0c0f2c1b95b5e7db5525a9048e65f2af4d78664
inherited_from_verdict: e00cc4f44d5bc56ca73605f8d2d0598e65fa0be5
fidelity: not-applicable
model: unknown
capabilities: pr-marker

# Review round 3 — PR #606 (issue #604)

**Verdict: approve.** 9 of 9 ACs satisfied, no blockers, 5 warnings (3 carried, 2 new).
Panel 4/4, none dark. Range read: `e00cc4f..e4eff02`, inheriting the coverage of patch
`b0c0f2c1b95b` from round 2. Read wider than the range — see W4.

## Round 2's blocker is closed

`e4eff02` rewrites one comment line at `plugins/dev-pipeline/tools/retro-corpus.sh:241`:

```
-# pipeline-cost-block.sh's helper — pinned by a scripts/lockstep-manifest.tsv row rather than
+# pipeline-cost-block.sh's helper — pinned by the iso-to-epoch LOCKSTEP markers below rather than
```

The new sentence is **true at this head**: `LOCKSTEP-BEGIN iso-to-epoch` is on the next line but
one, the twin at `pipeline-cost-block.sh:187` carries the same anchor, and the checker groups them
as a clean size-2 `verbatim` group. It is also the *better* of the two remedies round 2 offered —
pointing at `docs/testing.md`'s *Couplings considered and declined* would have been wrong, because
that section records couplings deliberately **not** mechanized and this one is.

The comment sits **outside** the marker block, so the edit cannot desync the pair: the two copies'
surrounding prose is already different by design, and `check-lockstep-pairs.sh` compares only what
is between the markers.

Confirmed exhaustive: `git grep -n lockstep-manifest -- . ':!docs/plans/'` returns **nothing** at
this head — zero live path references, `CHANGELOG.md` and `docs/testing.md` included. The ~93
remaining hits are historical plan docs, which AC-7 explicitly leaves alone.

## Per-AC scoring

| AC | Score | Basis |
| --- | --- | --- |
| AC-1 | **satisfied** | Re-run at this head with CI's own bare invocation from the reviewed checkout: `[lockstep] 22 anchor(s) checked, 0 failed`, exit 0. The script takes no manifest argument and `scripts/lockstep-manifest.tsv` is absent. |
| AC-2 | **satisfied** | Inherited — `check-lockstep-pairs.sh` is byte-unchanged since round 1, which verified the size-1 failure live on a constructed tree. Re-confirmed indirectly: the suite's `exit code equals the failed-anchor count (3)` case passes at this head. |
| AC-3 | **satisfied** | Inherited. The live group still reports `subset-of: superset plugins/dev-pipeline/tools/preflight.sh ⊇ …/lean-gate.sh`, and the suite's four relation cases (both polarities, member disagreement, two supersets, unknown token) all pass. |
| AC-4 | **satisfied** | Inherited. Suite cases `a docs/plans quote does not join the group` and `docs/ outside docs/plans/ is still walked` both pass. |
| AC-5 | **satisfied** | Inherited. `docs/testing.md:466` — *Couplings considered and declined* — is unchanged in this delta. |
| AC-6 | **satisfied** | Re-enumerated at this head across every live `LOCKSTEP-BEGIN` site: each carries rationale adjacent to its marker, on one side or the other (several sit *below* the BEGIN, inside the block — `audit-row-fields`, `lean-pr-marker`, `contribution-compare`, `checked-call`). This round's delta strictly **improves** `iso-to-epoch`'s. |
| AC-7 | **satisfied** | The round-2 blocker's one-line remedy landed and the grep above returns zero live path references. Scored against the reviewed head, not the spec's "31". |
| AC-8 | **satisfied** | `check-lockstep-pairs-selftest.sh`: **24 passed, 0 failed** at this head, covering discovery, size-1, both `subset-of` polarities, relation disagreement, the `docs/plans` exclusion, all three F-2 phantom shapes, the malformed-marker rc=2 path, and the live-corpus case. Register rows: round 1's scoped sweep of the rewritten guard (`applied=11 killed=11 survived=0`, all three catalog rows applied and killed) still covers — the guard and both register files are byte-unchanged since. |
| AC-9 | **satisfied** | Inherited. `CLAUDE.md:177` (tier map) and `docs/testing.md:231` (contract row) both describe marker discovery; neither carries a `lockstep-manifest` reference. |

**9 of 9 satisfied.** The spec was committed once (`7861d73`) and never amended — `git log --follow`
on the spec file shows the single commit. No after-the-fact fitting.

## Verification at this head

- **CI is green on the exact reviewed head** (`headSha` = `e4eff02`): `lint-and-selftests` pass,
  `selftests (macos, bash 3.2)` pass, `mutation-sweep-pr` pass. `pr-gates` fails on **one** step —
  `lean chain reconciliation` — which is the record round 2 wrote and this commit voided; this
  round replaces it. All three of its other steps (frozen files, changelog trailer, pipeline chain)
  pass.
- **Scoped mutation sweep of the delta, run because the delta edits a swept file.** In an isolated
  worktree at `e4eff02`, `tools/mutation-sweep.sh --mode pr --base HEAD~1` scopes the diff to
  `retro-corpus.sh` alone: **applied=9 killed=7 survived=2**, and both survivor ids are exactly the
  two rows already in `tools/mutation-baseline.tsv`
  (`…retro-corpus.sh::logic::37f27e369b81`, `…::default::1b0909258639`). No new survivor, and no
  re-key obligation — ids are content-derived (#583) and the changed line is a comment neither row
  is keyed on.
- **The pending base advance is pre-cleared.** `origin/main` moved to `69c50ff` (release v10.0.0)
  while this round ran. Its seven files are disjoint from the branch's fifty. A trial merge in an
  isolated worktree resolves clean, and the branch's own `+`/`-` line set measured against each
  side's merge-base is **byte-identical before and after** (2419 lines, zero diff) — so #601's
  contribution-compare hatch takes the `drc=0` arm and this record survives that merge rather than
  costing a fourth round. A merge that touches a line will still void it.

## Warnings

| # | Site | Finding |
| --- | --- | --- |
| W4 | 9 live sites, 6 files | **New this round.** The build's remedy for AC-7 was a grep for the *path literal*, so nine live comments that name the retired **unit** without naming the file survived it — and round 2's confirmation grep had the same shape. Two describe the enforcement mechanism as a row: `lean-gate.sh:269` (printed by `--help`) still calls the seam-scrub relation "a `subset-of` lockstep row against preflight.sh", 3,000 lines above the site comment this same PR rewrote to "the SUBSET side of the `seam-scrub` group"; and `docs/pipeline-manifesto.md:221` says `LEAN_OUTPUT_DISPOSITIONS` is bound by "a lockstep row". Five attribute a doctrine to the manifest — "the duplicate machinery the lockstep manifest calls worse than none" at `lean-evidence.sh:954`, `lean-gate.sh:3122` and `:3162`, `check-lean-chain.sh:791` and `:799`. Two are negative forms that stay true — `ledger-lint.sh:143`, `tools/mutation-exclusions.tsv:21`. |
| W5 | `tools/mutation-slow-suites.tsv` | **New this round.** The scoped sweep warns: `retro-corpus-selftest.sh measured 18s (>= 5s)` with no row recording it, so its guard is still swept in the PR lane. The cost is **main's**, not this PR's — #603 grew that suite by 415 lines — but this PR is the first change to put `retro-corpus.sh` in a PR diff scope, so it is the first to surface it. Advisory warn, never red. Left unfixed deliberately: adding the row would *defer* the guard from the PR lane, the same trade W3 declines. |
| W1 | `check-lockstep-pairs.sh` walk | Carried from round 1, unaddressed. The `find`-based walk (D-4) reads **untracked** working-tree files, so a stray `.bak`/`.orig` can join an anchor group and mask the size-1 failure. CI is unaffected (clean checkout); it bites the local run CLAUDE.md recommends. |
| W2 | deleted `lean-evidence` DROPPED row | Carried from round 1, unaddressed. The clause "neither file can import the other" is now at no site. |
| W3 | `check-lockstep-pairs-selftest.sh` runtime | Carried from round 1. Straddles the 5s slow-list bar (~4.1s measured). Deliberately left off the slow list — a row would defer the guard from the PR lane. Recorded so the nightly warn is not misread. |

### Why W4 is a warning and round 2's B1 was a blocker

The test round 2 applied was whether a reader is given **wrong information they would act on**. B1
named a **file path that resolves to nothing** — a reader checking whether the `iso_to_epoch` pin
still existed would open `scripts/lockstep-manifest.tsv`, find no such file, conclude the pin was
dropped, and edit one copy freely. W4's nine sites name a **unit whose replacement is adjacent and
self-evident**, and in each one the actionable clause is still true: `lean-gate.sh:269`'s operative
content — preflight.sh carries the superset, you cannot widen `SEAM_SCRUB` from this side alone —
holds exactly, and the reader who follows it finds `# LOCKSTEP-BEGIN seam-scrub superset` there.
The "worse than none" doctrine survives verbatim at `docs/testing.md:724-729`, under a heading that
says in as many words that it was kept from the manifest's own header. No AC binds them either:
AC-7's letter is comments pointing at `scripts/lockstep-manifest.tsv`, of which there are now zero,
and AC-3's — the relation encoded in the marker — is met in the code.

The generalisable half is worth more than the nine edits: **when a PR retires an artifact, grep for
its NAME and its UNIT, not just its path.** A path-literal remedy converges on green while the
vocabulary that only that artifact ever had stays scattered through the tree.

## Verdicts

| Reviewer | Verdict | Findings | Confidence |
| --- | --- | --- | --- |
| Scope Completeness | **Pass** | 0 (1 suppressed at 85) | — |
| Security | Pass | 0 (1 suppressed at 40) | — |
| Performance | Pass | 0 | — |
| Maintainability | Pass | 0 | — |

Panel reduced per the multi-round rule: the round-3 delta is one comment line, and round 2's only
blocker came from scope-completeness and maintainability. Complexity and test-coverage were not
selected (Small change size, no test file touched); `a11y-reviewer` and the design-fidelity
dimension were not routed, because no changed path matched `stageParams.webComponentGlobs` (unset;
default `apps/web/**/*.{tsx,jsx}`). Neither is a coverage gap.

The scope reviewer was dispatched with the **PR base** (`733d2d5...e4eff02`), not the round delta —
round 2's own note. It scored the full contribution and returned no findings. Its one suppressed
note at confidence 85 is an AC-8 count observation (the spec says two catalog rows are re-anchored;
the tree ships three, one still-valid plus two new, and the four baseline rows were removed rather
than re-keyed because their content-derived sites no longer exist). That is the same spec-time-
measurement class as AC-7's "31", the substance is satisfied, and round 1 closed the removals by
scoped sweep. Not carried as a finding.

## Ready to merge

Yes, once this record is the branch head and `pr-gates` re-runs. The branch will need a base merge
onto `69c50ff` first; that merge is measured above to move no reviewed line, so it does not cost a
round.
