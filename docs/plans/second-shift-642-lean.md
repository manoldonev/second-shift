# #642 — the lane's gate, cut to what changes a merge decision

Two thirds of the lane's recorded gate firings changed nothing that shipped, and 20 of its 33
declared decision points have never fired at all. `docs/gate-ablation.md` measured that over a
52-record corpus and acted on none of it. This slice acts on it.

Lane A of the 2026-08-22 backlog recalibration, sequenced behind #641's guard-mass ratchet.

## What this slice does

1. **The per-point reachability verdict.** Every never-fired decision point is classified
   `structurally dead` (delete) or `dead here, live for a consumer` (keep, untouched), each with
   its argument recorded. The split IS the slice's judgment — the ticket leaves it open and the
   report warns explicitly that absence of firings is not evidence of deadness.
2. **Announcement-class refusals stop charging the fix budget.** Every reason the report
   adjudicates `unchanged` routes to the `absent` verb, which `attempt_count()` cannot see.
3. **The three merge-boundary-duplicated milestone-3 lanes report instead of refusing.**
4. **The ablation corpus is re-cut** so the next report measures the new surface.

## Two things the ticket asked for whose subject has moved

Both are recorded here rather than silently absorbed, and both are carried as `D-n` rows below.

- **AC-6's `tools/guard-budget.tsv` has no subject.** #641 (the Phase-0 slice this ticket is
  sequenced behind) landed a *derived, not stored* ratchet: `scripts/check-guard-budget.sh`
  measures guard/test shell mass at the merge-base and at HEAD and compares the two numbers it
  just took. There is no committed ceiling file to ratchet. AC-6's line-count clause is
  unchanged; its second clause is restated against the mechanism that actually exists.
- **An operator comment on the issue (2026-08-23) adds a milestone-5 defect** — `close-out` is
  unreachable after a merge, because milestone 5 requires an *open* PR. It names its own
  preferred shape and says "split it out if it turns out not to be [in this file's
  neighbourhood]". It is in the neighbourhood: `resolve_open_pr` is the same call site AC-3
  re-verbs, so a follow-up ticket would collide with this PR. Carried as AC-8.

## Acceptance Criteria

- **AC-1** (oracle — selftest): every deleted decision point is absent from `lean-gate.sh`,
  `tools/gate-ablation-classes.tsv` and `lean-gate-selftest.sh`, and
  `SKIP_STRESS=1 bash tools/run-selftests.sh --full --exclude tools/install-topology-selftest.sh`
  is green.
- **AC-2** (critic): each deleted point carries a recorded reachability argument; each kept
  never-fired point carries the consumer-reachability reason it was kept for. The register is
  `tools/gate-ablation-classes.tsv`'s own `earn_your_keep` column plus the table in
  [`docs/testing.md`](../testing.md); the commit body carries the deletions' arguments.
- **AC-3** (oracle — selftest): every reason `docs/gate-ablation.md` adjudicates `unchanged`
  reaches `append_absent`, driven by a fixture case per reason; a case asserts no fix-budget
  charge. The set is exactly: `m1/spec-absent` (already there), `m4/verdict-absent`,
  `m5/progress-current`, `m5/exit-artifacts:no-open-pr`,
  `m5/verdict-reference:closing-comment`, `m5/identity-stamp`.
- **AC-4** (oracle — selftest): `m3/lint`, `m3/test`, `m3/extra-lane` report without refusing —
  a red lane yields a non-blocking record and a zero exit at that milestone. `m3/typecheck`,
  `m3/setup-lane`, `m3/no-verify-lane` and the design-render tier are NOT demoted (D-3).
- **AC-5** (oracle — CI): `pr-gates` and `lint-and-selftests` still red on the conditions the
  demoted milestone-3 lanes used to catch, proving the coverage moved rather than vanished.
  This AC's oracle is CI's own run on this PR, not a reviewer re-derivation.
- **AC-6** (proxy, AMENDED — see D-6): combined `lean-gate.sh` + `lean-gate-selftest.sh` line
  count drops against this branch's merge-base by the measured figure recorded in the PR body,
  and `scripts/check-guard-budget.sh origin/main` reports a negative guard/test mass delta (D-1 —
  this replaces the ticket's `tools/guard-budget.tsv` clause, whose subject #641 deleted). The
  ticket's **≥30%** bar is NOT met and is not chased; D-6 records why, and the operator's call on
  whether that is acceptable is deliberately left open rather than absorbed.
- **AC-7** (critic): `Changelog:` trailer.
- **AC-8** (oracle — selftest): milestone 5 accepts a **merged** PR for the lane branch as
  satisfying the same obligation an open one does, so `close-out` stays reachable after a merge
  (D-2, from the operator's 2026-08-23 comment; shape (1) of the two it names).
- **AC-9** (doc): the ablation corpus is re-cut and `docs/gate-ablation.md` regenerated against
  it, and every prose statement this change falsifies is updated — `build-lean/SKILL.md`,
  `docs/testing.md`, `docs/pipeline-manifesto.md` and `lean-gate.sh`'s own exit-code header.

## Decision Ledger

| D-n | Question | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | AC-6 names `tools/guard-budget.tsv`, which does not exist. | #641 replaced the stored ceiling with a derived base-vs-HEAD comparison in `scripts/check-guard-budget.sh`. The AC's line-count clause stands unchanged; its ratchet clause is restated against that script. A mass decrease needs no write — the next PR's base is this one's HEAD. | codebase-derived |
| D-2 | The issue's second comment adds milestone-5 scope. | Carried as AC-8, shape (1) — milestone 5 accepts a merged PR. It touches `resolve_open_pr`, the same site AC-3 re-verbs, so splitting it out would collide with this PR. Source: <https://github.com/manoldonev/second-shift/issues/642#issuecomment-5385775226> | ticket-sourced |
| D-3 | Which milestone-3 points demote? | Exactly the three the ticket names, and only them. `m3/typecheck` is NOT demoted: the demotion's premise is measured CI duplication, and typecheck has none measured (this repo configures none, and a consumer's CI is unknown). `m3/setup-lane` and `m3/no-verify-lane` are the "the check could not run" and "nothing was verified" points — demoting either makes milestone 3 green having verified nothing. | codebase-derived |
| D-4 | How is AC-6's 30% reached, given that the never-fired points are almost all consumer-live? | By P5, not by manufacturing deletions. The decision-point deletions alone are ~200 lines; the remaining mass is comment prose — 2,782 of `lean-gate.sh`'s 5,518 lines and 2,083 of the selftest's 7,043. The survival rule: a comment stays when it states a CONSTRAINT a future edit could violate (an invariant, an ordering requirement, a fail-closed reason, a pinned dialect); it goes when it is incident narrative — what a past PR did, what an earlier design was, what was tried and retired — with no live constraint attached. Where narrative carries a constraint, the constraint survives in one line and the narrative does not. This is the same axis `scripts/check-guard-budget.sh` measures and the same posture `prose-budget.sh` took to its own baselines in #641. | codebase-derived |
| D-6 | AC-6 asks for ≥30% off the two files. Is it reachable? | **No — measured at −0.8%, and the premise is refuted by AC-2's own verdict.** The ticket's arithmetic assumes the delete bucket is most of the 20 never-fired points ("Every dead decision point deleted takes its selftest cases with it"). The per-point reachability pass returns **2** structurally dead, not ~15: every other never-fired point is reachable by a consumer, and the ticket's own warning is that deleting those "would remove function from the shipped product to tidy the dogfood canary — the exact inversion this recalibration exists to reverse." The remaining mass is comment prose, and D-4's P5 pass takes what is honestly deletable from it; the balance would have to come from deleting rationale that states live constraints, or from deleting reachable gates. Neither is a cut this ticket asks for. MEASURED, after the P5 pass ran: `lean-gate.sh` 5,519 → 5,233 (−286, of which −293 are comment lines); `lean-gate-selftest.sh` 7,044 → 7,231 (+187, entirely the new AC-3/AC-4/AC-8 coverage); combined 12,563 → 12,464, **−0.8%**. `scripts/check-guard-budget.sh` reports **−31** across all guard/test shell. The pass stopped where it did because it ran out of archaeology: the gate's remaining large comment blocks are 830 lines over 54 blocks, most already compressed, and what is left below that is 3-to-7-line per-site rationale stating live constraints. Scaling the target is the operator's call, not the slice's. | codebase-derived |
| D-5 | Delete outright, or demote-then-delete? | Outright. Operator-ratified 2026-08-22 in the ticket: a further corpus cycle to confirm what 52 records already show is the over-caution being diagnosed, and `git revert` is the undo. | user-answered |

## Explicitly out of scope

`m4/patch-stale`, `m4/chain-break` and `m4/verdict-not-approve` stay blocking — they carry the
corpus's two sharpest dated incidents and P10 independence is the lane's load-bearing property.
Milestone 2 is not demoted: the ticket scopes the demotion to three named milestone-3 points,
and milestone 2's two checks cost two script invocations, not a suite sweep.
