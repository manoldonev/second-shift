# lean review verdict — #604

verdict=needs-work
run_id: review-604-2
session_id: 67f9216d-6910-4f0c-a46e-164977a0de6b
rounds: 2
pr: #606
reviewed_head: 019bfaaa2ba3a2730cc1df62180dbeb775ac10d4
reviewed_patch_id: b0c0f2c1b95b5e7db5525a9048e65f2af4d78664
inherited_patch_id: f0dd7254d10175bcf0d6a78c4074e45cc25bfa9e
inherited_from_verdict: b1eeebcaf143cdeac0966d3659744cbfbc684741
fidelity: not-applicable
model: unknown
capabilities: pr-marker

# Review round 2 — PR #606 (issue #604)

**Verdict: needs-work.** One blocker. Panel 6/6, none dark.
Range read: `b1eeebc..019bfaa` (the second base merge), inheriting the coverage of patch
`f0dd7254d101` from round 1. Read wider than the range — see "Why the delta under-reports" below.

## Why this round exists, and why the delta under-reports it

Round 1 approved at `414521f`. The operator then merged main a **second** time (`019bfaa`,
bringing `733d2d5` / #603). That advance voided the round-1 record, and #601's
contribution-compare hatch says why rather than merely that: the branch's own lines moved —
**7 unique lines, all in `scripts/lockstep-manifest.tsv`**, measured by hashing the `+`/`-` line
sets per file against each side's own merge-base.

Those 7 lines are the `iso-to-epoch` row and its rationale block, which #603 appended to the
manifest and which this branch's `git rm` resolution now also deletes. So the branch's
contribution genuinely grew, and this is a real round, not a re-stamp.

`G delta` prints `b1eeebc..HEAD`, which contains only main's 8 files — the manifest is not in it,
because the file was already deleted at `b1eeebc` and the merge only kept it deleted. The new
contribution is visible only against `origin/main`. I reviewed both.

**The merge dropped nothing of main's.** For each of the 9 files main touched in
`3b55bc7..733d2d5`, I compared `733d2d5` against the merge head: only `lockstep-manifest.tsv`
(deleted, as designed) and `retro-corpus.sh` (the branch's own AC-7 re-point at :200) differ.
Every other byte of #603 is present.

## Blocker

| # | Severity | Site | Finding |
| --- | --- | --- | --- |
| B1 | **Blocker** | `plugins/dev-pipeline/tools/retro-corpus.sh:241` | **AC-7 unsatisfied: a live file still points at the manifest this PR deletes.** The comment above the `iso_to_epoch` block reads "*This is a verbatim second copy of `pipeline-cost-block.sh`'s helper — pinned by a `scripts/lockstep-manifest.tsv` row rather than extracted*". That file does not exist at this head. It is a dangling pointer to a mechanism this PR retires, sitting one line above the `LOCKSTEP-BEGIN` marker that is now the actual pin. |

**Why blocker rather than warning.** AC-7's obligation is that live files pointing at the manifest
are re-pointed; its "31" is a spec-time measurement, not a frozen subject, and every AC here is
scored against the reviewed head. The head has one such file. Three further reasons:

- It is **wrong information, not missing information**. Round 1's W2 recorded a *lost* clause and
  I scored it a warning; this is the inverse — a reader is told the enforcement lives in a file
  that is gone, and may conclude the pin was dropped and edit one copy freely.
- It is **invisible to every other gate**. The line is not in the branch's diff (it arrived via
  the merge's other parent), CI has no prose guard for it, and `check-lockstep-pairs.sh` passes
  because the coupling *is* enforced. This round is the only place it gets caught.
- The remedy is **one line**, matching the wording this same PR already used at
  `retro-corpus.sh:200`: re-point to `docs/testing.md`'s *Couplings considered and declined*, or
  simply to the marker pair.

Confirmed exhaustively: `grep -rIn 'lockstep-manifest' . --exclude-dir=.git` outside
`docs/plans/**` returns **this file alone**. The ~93 remaining hits are historical plan docs,
which AC-7 explicitly leaves untouched. `docs/testing.md` and `CLAUDE.md` are clean.

Two reviewers reached this site independently (maintainability at confidence 90 as `minor`,
scope-completeness at confidence 92 as `blocker`), and I had it from my own read before the panel
returned. The Scope Completeness Gate returned FAIL, which is a hard gate.

## Per-AC scoring

| AC | Score | Basis |
| --- | --- | --- |
| AC-1 | **satisfied** | Re-verified at this head with CI's own bare invocation from the reviewed checkout: `22 anchor(s) checked, 0 failed` (21 at round 1; `iso-to-epoch` is the 22nd, arriving with the merge). `scripts/lockstep-manifest.tsv` is absent. |
| AC-2 | **satisfied** | Inherited — `check-lockstep-pairs.sh` is byte-unchanged in this delta. Round 1 verified the size-1 failure live on a constructed tree. |
| AC-3 | **satisfied** | Inherited; unchanged. The live `subset-of` group still reports `superset preflight.sh ⊇ lean-gate.sh` in this run. |
| AC-4 | **satisfied** | Inherited; unchanged. |
| AC-5 | **satisfied** | Inherited; `docs/testing.md`'s *Couplings considered and declined* is unchanged in this delta. |
| AC-6 | **satisfied** | Re-scored for the **new** anchor: `iso-to-epoch` carries rationale adjacent to its `LOCKSTEP-BEGIN` at **both** sites (`pipeline-cost-block.sh:180-186`, `retro-corpus.sh:238-243`), and that rationale is a strict **superset** of the manifest text the merge deleted — the `-u`-is-load-bearing contract and the "#546 owns every executable line" reason both survive. Nothing informative was lost with the row. Presence is met at every anchor; B1 is about one clause naming a retired mechanism, which is AC-7's property, not AC-6's. |
| AC-7 | **unsatisfied** | See B1. |
| AC-8 | **satisfied** | Inherited. The live-corpus case reads the anchor count out of the checker's own output rather than pinning a literal, so 21→22 does not red it — confirmed by `lint-and-selftests` passing on this exact head. |
| AC-9 | **satisfied** | Inherited; `CLAUDE.md` and `docs/testing.md` are unchanged in this delta and carry no `lockstep-manifest` reference. |

**8 of 9 satisfied.** The spec was committed once (`7861d73`) and never amended — verified by
`git log --follow` on the spec file. No after-the-fact fitting.

## Verification at this head

- **CI ran on the reviewed head** (`headSha` = `019bfaaa`): `lint-and-selftests` pass,
  `selftests (macos, bash 3.2)` pass, `mutation-sweep-pr` pass. `pr-gates` fails on exactly one
  thing — the voided verdict record, which this round replaces. No other red.
- **No new mutation obligation.** The delta touches no guard and no register row;
  `check-lockstep-pairs.sh`, `tools/mutation-baseline.tsv` and `tools/mutation-catalog.tsv` are
  byte-unchanged since round 1. Round 1's scoped sweep of the rewritten guard
  (`applied=11 killed=11 survived=0`, all three catalog rows applied and killed) still covers this
  head; I did not re-run it, and say so rather than implying fresh evidence.
- **The `iso-to-epoch` pair is correctly discovered.** Both markers are whole-line, the two blocks
  are byte-identical, and the checker groups them as a clean size-2 group with no row — which is
  the ticket's own thesis demonstrated a second time, exactly as it was by #601's
  `contribution-compare` pair at round 1.

## Warnings carried forward from round 1 (none blocking, none re-verified this round)

| # | Site | Status |
| --- | --- | --- |
| W1 | `check-lockstep-pairs.sh` walk | A `find`-based walk reads **untracked** working-tree files, so a stray `.bak`/`.orig` can join a group and mask the size-1 failure. CI is unaffected (clean checkout); it bites the local run CLAUDE.md recommends. Unaddressed. |
| W2 | deleted `lean-evidence` DROPPED row | The clause "neither file can import the other" is now at no site. Unaddressed. |
| W3 | `check-lockstep-pairs-selftest.sh` runtime | Straddles the 5s slow-list bar (~4.1s measured). Deliberately left off the slow list — adding a row would defer the guard from the PR lane. Recorded so the nightly warn is not misread. |

## Note for the next round's dispatch

The scope reviewer flagged, correctly, that dispatching it with the lean **delta** base
(`b1eeebc`, a commit on the branch) shows it only the base merge and would have produced a false
all-unsatisfied FAIL. It self-corrected to `origin/main...019bfaaa` and scored the real
contribution. The delta bounds what a round *reads*; the scope gate must still see the whole
contribution, so it should be dispatched with the PR base regardless of the round's delta.

## Verdicts

| Reviewer | Verdict | Findings | Confidence |
| --- | --- | --- | --- |
| Scope Completeness | **Fail** | 1 blocker, 1 nit | 92–95 |
| Security | Pass | 0 (1 suppressed at 30) | — |
| Performance | Pass | 0 | — |
| Complexity | Pass | 0 | — |
| Maintainability | Pass (nits) | 1 minor | 90 |
| Test Coverage | Pass | 0 | — |

`a11y-reviewer` and the design-fidelity dimension were **not routed**: no changed path matched
`stageParams.webComponentGlobs` (unset; default `apps/web/**/*.{tsx,jsx}`). Not a coverage gap.

## Remedy

One line at `plugins/dev-pipeline/tools/retro-corpus.sh:241`. Everything else on this branch is
ready.
