# lean review verdict — #720

verdict=approve
run_id: review-720-1
session_id: a18fa087-1bc2-4648-802b-4e50bcfa8d85
rounds: 1
pr: #738
reviewed_head: 40fc588d28297ea822d51855f14b89e2bb2d132e
reviewed_patch_id: ccf036ade3620edc8042770cbb1ecd4dd804b032
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: opus
capabilities: pr-marker

Round 1, full branch range `630b1f89..40fc588d` (root round — no prior record to inherit
from). Every AC re-measured at this head; the panel's five core reviewers returned no
findings, and the scope reviewer's three blockers are addressed individually below.

## Verdict

**approve.** The deletion is complete, the six removed refusals are each demonstrably
re-asked at the merge boundary, and no surviving arm lost its pin. No blockers.

## Acceptance criteria

| AC | Score | Evidence at `40fc588d` |
| --- | --- | --- |
| AC-1 | satisfied | `grep -cE '(fail\|block)_milestone 4[ ]'` = **15** at head, **21** at base. Enumerated all 15: the six named sites are gone and every declared keeper is present (absent/not-approve/`reviewed_head`/2x identity/2x uncommitted/chain/7 armed fidelity-render). The suite's own `(ac1)` pin reads 14 `fail_milestone 4 "` with signature `11112555555566`; I re-derived that signature from the file (4x1 / 1x2 / 7x5 / 2x6) and it matches. |
| AC-2 | satisfied | Measured id-set delta: 561 -> 539 distinct ids, **23 removed, 1 added**, exactly the spec's enumeration. I individually classified all 12 unlisted removals: `(t3)`/`(u3)` are remedy halves of `(t2)`/`(u2)`; `(v0)`/`(v4-fixture)`/`(vb-fixture)` are fixture guards; `(v3a)`/`(vb0)`/`(vb4a)` are non-vacuity guards; `(v1)`/`(v2)`/`(v3)` assert the deleted declared arm. None asserts anything about a surviving arm. `(v5-fixture)` -> `(v6-fixture)` is the forced rename. |
| AC-3 | satisfied | `(j1)`/`(j2)`/`(n1)`/`(n2)`/`(u1)` produce **zero diff lines** in `lean-gate-selftest.sh` over the range, and `lean-gate-selftest` is `all green` in CI at this head. |
| AC-4 | satisfied | `gate-ablation.sh check` rc 0; the generated block (`docs/gate-ablation.md:176-519`) is untouched — the +9 lines land at `:132`, outside it. `check-gate-buckets.sh` rc 0 (285 sites / 156 rows), with exactly the six orphaned rows removed. Both classes rows kept: compared column-wise, **only column 6 differs** on each. |
| AC-5 | satisfied | 5,922+8,479 -> **13,984** lines, under the 14,151 ceiling (actual reduction 417). `git diff --quiet ... check-lean-chain.sh` rc 0. `lean-evidence.sh` non-comment changed lines = **0** (re-ran the spec's oracle). The marker removal is forced, not chosen: `check-lockstep-pairs.sh:221` hard-fails an anchor with one site. See W1. |
| AC-6 | satisfied | Legs 5, 7, 7b and leg 6's head-declaring half are gone; a keyed-record **remedy half** was added beside the surviving key-less refusal. Ran the suite at this head: 76 assertions. `(lean-taxonomy)`/`(lean-authorship)` green in CI. See N1 on the 79-vs-76 figure. |
| AC-7 | satisfied | All four enumerated sites updated and each accurate against the code: `build-lean/SKILL.md` step 8 + the post-approve rule, `review-lean/SKILL.md` step 7, `docs/testing.md` (key lockstep + never-fired points), `docs/gate-ablation.md` finding 4. |
| AC-8 | satisfied | The table is in the PR body and states plainly that it grades nothing. Independently re-ran **all 36** `mutation-catalog.tsv` rows targeting `lean-gate.sh` against the edited file: every one still changes the file and still yields `bash -n`-valid output — **0 anchor drift**. |

Design fidelity: **not-applicable.** The spec declares no `## Design` section and the repo's
config carries no `design.provider`, so the armed path is not reachable and step 5b is skipped.

## The deletion is sound

I traced each of the six removed refusals to its surviving counterpart rather than taking the
spec's word for it:

| Removed from `cmd_4` | Refused at the boundary by |
| --- | --- |
| no `run_id`, no `session_id` | `lean-evidence.sh` `arm_verdict` (both, explicitly) |
| INFERRED patch-stale | `check-lean-chain.sh`'s own inferred arm, on the no-`reviewed_patch_id` path |
| no `reviewed_patch_id` | `arm_freshness` refuses it outright on a consumer's `all` invocation; on this repo's boundary the inferred + `reviewed_head` SHA arms cover the same record |
| patch identity uncomputable | `arm_freshness` `envfail` |
| DECLARED patch-stale | `arm_freshness`, via `delegate freshness` |

`ARMS` defaults to `verdict,identity,freshness,intent-gap,override`, so a consumer fetching
`lean-evidence.sh` at any pinned ref gets all of them. The deletion is also clean: **zero**
`contribution_*` references remain in `lean-gate.sh`, `contribution_lines` had no caller but
`contribution_delta`, and `branch_patch_id`/`render_patch_id` both survive with live callers
(`cmd_verdict`, the inheritance walk, milestone 3, the armed render arm). The writer still
stamps `reviewed_patch_id`.

Keeping `(v6)` was the right call, and I checked it rather than accepting D-4: it drives
`bash "$GATE" verdict`, i.e. `cmd_verdict`, and asserts rc 2 on an unresolvable base. No
milestone-4 site ever backed it, so the ticket's Delete list is simply wrong about it, and
deleting it would have dropped the only pin on a surviving arm — the botch the ticket's own
adversarial table exists to catch.

## Findings

| # | Severity | Finding |
| --- | --- | --- |
| W1 | warning | **The spec's AC-5 and AC-2 were amended in the same commit as the code** (`40fc588d`), not at milestone 1: AC-5's oracle changed from "`lean-evidence.sh` unchanged" to "comment lines only", and `(t3)` was added to AC-2's list. This is the shape review-lean names as a blocker, so I tested it rather than waving it through — and it does not hold here. The original bar is **unsatisfiable jointly with the ticket's own Delete instruction**: deleting `lean-gate.sh`'s `contribution-compare` copy orphans the lockstep marker, and `check-lockstep-pairs.sh:221` hard-fails an anchor with one site. The substituted oracle closes the exact botch the AC named ("move the checks into `lean-evidence.sh`") and I measured it at 0. Since the orphan is only discoverable once the second copy is deleted, a milestone-1 amendment was not available. Not a blocker — but **issue #720's body still carries the superseded AC-5 and AC-2 text**, so a reader going to the issue gets the retired bar. Correct it at merge. |
| W2 | warning | Issue #720's Delete list names `(v6)`; the PR keeps it. Verified correct (above). Same disposition as W1: the departure is argued in the spec's Decision Ledger D-4 and in the PR body, but the issue body records no deferral. |
| N1 | note | The PR body's "79 -> 76 passing" for `scenario-liveness-selftest.sh` reads as contradicted by CI, which reports **79 passed** at this head. It is not. CI runs the PR **merge ref**, so the head job includes #736's three `(lean-design-override)` assertions, which are on `main` but not on this branch: 76 (branch) + 3 (#736) = 79. Confirmed by diffing the base and head CI assertion id lists — the only removals are `(lean-freshness)`, `(lean-patch-id)`, `(lean-base-advance)`, exactly the three deleted legs. My local run of the suite at this head reports 76. Worth knowing because it also means CI proves the branch's `(ac1)` completeness pin **survives merging `main`**. |
| N2 | note | `lean-reconcile.sh:29` now reads half-false: "they compare the declared head against a moving head" describes milestone 4 and `check-lean-chain.sh`, but after this change milestone 4 only checks that `reviewed_head` is **present** — the comparison is the boundary's alone. One clause, in a file AC-7 does not enumerate. Fix opportunistically. |
| N3 | note | The two amended `earn_your_keep` cells in `tools/gate-ablation-classes.tsv` splice the new sentence onto the old one with no separator ("...records deleting SINCE #720 only the `reviewed_head` arm is live here..."). Cosmetic; the column is unread by `gate-ablation.awk`. |

## CI

- `lint-and-selftests` **pass** at `40fc588d` — cited, not re-run: same head, and it is the sweep this repo's Verification recipe names. `lean-gate-selftest` and `lean-evidence-selftest` both `all green`; `scenario-liveness` 0 failed.
- `mutation-sweep-pr` **pass**, and it is a **vacuous** pass: both in-scope guards deferred as slow suites, 0 mutants swept, with the runner's own `WARN: PR mode graded NOTHING`. The PR body says exactly this. Real verdicts come from the nightly run; the anchor-drift half I verified by hand.
- `pr-gates` **fail**, on exactly one violation: `no committed verdict record`. That is the expected pre-approve state and this record clears it. No other step in the job errored — no policy red (`guard-budget`, `Changelog:` trailer, frozen files) and no correctness red.
- `selftests (macos, bash 3.2)` was still pending at review time; its `scenario-liveness` block had already reported 79 passed / 0 failed.

## Strengths

- The disclosure discipline is the best part of this PR. The mutation table says "this table
  grades nothing, and says so" instead of banking a vacuous green; the departures are argued
  from the code in three places; and the id-set delta is enumerated by id rather than by count,
  which is what made it checkable at all.
- Deleting `scenario-liveness`'s legs 5/7/7b was the harder and correct call — leaving them
  would have asserted a contract the chain no longer carries. Adding the keyed-record remedy
  half beside the surviving key-less refusal keeps that leg a check with a remedy rather than
  a wall.
- The `(v6)` departure is the single most valuable judgment in the diff: following the ticket
  literally would have deleted live coverage of the one arm now standing between a key-less
  record and a boundary that rejects one outright.
