# lean review verdict — #346

verdict=approve
run_id: review-346-3
session_id: 4e000438-5540-48a3-af9b-37d2d100ba92
rounds: 3
pr: #368
reviewed_head: f47042fc68439af89ae6e7acbdd19d2104c8ee99
model: unknown

## Verdict: approve (round 3)

Round 2's B-1 is discharged by the one commit this round adds, and discharged the way round 2
asked: the clause is restored, the stderr routing round 1 asked for **stays**, and the file is
back at exactly 60/60. All seven ACs are satisfied. Two warnings, neither blocking.

**Re-issued after a rebase, same round, same identity.** This record was first written against
`e36e168`; the branch was then rebased onto `01950af` (picking up #369) and the review's head
ceased to exist. No re-review was performed and none was needed: the branch's own patch is
identical across the rebase — `diff <(git diff <old-base>...e36e168) <(git diff
<new-base>...60c8c18)` returns only blob hashes and hunk offsets, zero content lines. The
scoring below stands unchanged.

That the gate demanded a fresh round for this is a **defect in the gate, not a finding against
this PR**. A rebase rewrites commit SHAs and changes nothing a reviewer read, so binding a
verdict to a SHA makes a mechanical operation look like tampering. The fix is to bind it to the
branch's patch identity (`git patch-id --stable` over `merge-base...HEAD`), which is invariant
under rebase and still moves the moment a real commit or a conflict resolution lands. Filed
separately; not this PR's scope.

## Round 2's B-1 — discharged

AC-7 names two things `run-lean/SKILL.md` must say. Head state, `SKILL.md:52-53`:

> **A decision the receipt never covered is not yours to make (P9).** Write the intent-gap
> record (schema: `interviewing-baseline`), follow its region's disposition, and ratify before
> the handoff — the merge boundary refuses `ratified: no`.

*When BUILD writes one*: "a decision the receipt never covered". *What the merge boundary does
with it*: "refuses `ratified: no`". Both clauses present in one bullet.

`wc -l` is 60, so the cap oracle (`lean-gate-selftest.sh` case `(f)`) is green — confirmed by
the sweep below, not by reading. The `lean-gate.sh` milestone-4 stderr line survives the fix
intact, so this is the addition round 2 specified rather than a revert of round 1's remedy.

The only compression paid for it was dropping "declared" from "its region's declared
disposition". AC-7 asks for the disposition to be named, not for that adjective — nothing the
AC mandates was traded away this time.

## Warnings — verified, not blocking

**W-1 — `scripts/lockstep-manifest.tsv:323` cites the wrong selftest cases.**

The new DROPPED entry justifies declining a lockstep row for the receipt vocabulary by naming
where the coupling is guarded behaviorally instead:

> Guarded behaviorally instead: ledger-lint-selftest.sh drives all three Kind values and both
> dispositions against real receipts (ll-o through ll-y2) … `check-lean-chain-selftest.sh
> (R0)-(R4)` does the same for the record's two keys at the merge boundary.

The `ll-o … ll-y2` half checks out. The other half does not, in two ways: `(R0)` has never
existed, and at head `(R1)`-`(R4)` are **#367's `reviewed_head` cases** — a different contract
entirely. The real guards for `ratified:` / `ratified_by:` are `(S0)`-`(S4)` plus `(S0b)`.

Provenance: at `bb10475` evidence 6's block was `(R)` with cases `(R1)`-`(R4)`, so the citation
was off by an id from the start. Round 2's rebase then renamed the block to `(S)` — the PR body
documents that rename ("both sides had claimed the letter `(R)`") — and the manifest comment did
not move with it. The citation now resolves to real, green cases that assert something else,
which is worse than a dangling reference: a reader who follows it sees passing tests and stops.

Not blocking. The DROPPED decision's *substance* is sound — I confirmed `(S1)`-`(S4)` do drive
both keys, so the row genuinely is unnecessary, and only the pointer is wrong. It stops no
contract from being enforced, which is the same test round 2 used to keep its three surviving
mutants as warnings. But no gate can ever catch this — the repo bans prose-presence guards, so
the manifest's own comments are unexecutable by policy — and the fix is one token
(`(R0)-(R4)` → `(S0)-(S4)`, or `(S0)`/`(S0b)`-`(S4)` to be exact). Worth a follow-up.

**W-2 — the `https://` predicate in the `ratified_by:` citation check has no kill criterion.**

`check-lean-chain.sh:440` requires a literal `https://` before `ratified_by:` counts as a
citation; anything else falls into the self-ratification refusal. Raised by
`unit-test-mutation-reviewer` (confidence 83) and **verified here by execution**, not by reading
the claim: widening the pattern to `ratified_by:[[:space:]]*[^[:space:]]+` leaves
`check-lean-chain-selftest.sh` **all green**. `write_gap` is called three ways — empty (`S1`,
`S2`) and a full URL (`S3`, `S4`) — so the empty-vs-URL boundary is pinned and the
URL-shape-vs-any-string boundary is not. Under the mutant, `ratified_by: confirmed-verbally`
certifies a merge.

Not blocking, and it is a weaker finding than round 1's B-1 despite touching a refusal. That
cluster was five `violate()` branches with *no case driving them at all* — each deletable with
the suite green. This branch **is** driven: deleting the `elif [[ -z "$GAP_BY" ]]` arm reds
`(S2)`. Only the predicate's strictness is unpinned, the code at head is correct, and the file's
own honest-altitude note already scopes this arm to tamper-evidence rather than proof — a
`https://`-shaped string is forgeable anyway. One fixture with a non-URL truthy `ratified_by:`
would close it.

## Warnings carried forward from round 2 — re-confirmed unchanged

`unit-test-mutation-reviewer` re-raised all three and confirmed each region is byte-identical to
round 2's `reviewed_head`. Round 2's adjudication stands and I am not re-litigating it: none is
a `violate()` refusal — `normalize_arity`'s drop-branch is a tolerance, the two-positional-args
check is a usage guard, and `check-lean-chain.sh`'s `break` is a tie-break among states the
one-record-per-issue schema forbids.

| # | Site | Status |
| --- | --- | --- |
| W-3 | `ledger-lint.sh:136` `normalize_arity` drop-branch | unchanged since round 2; still a warning |
| W-4 | `ledger-lint.sh:62` two-positional-args guard | unchanged since round 2; still a warning |
| W-5 | `check-lean-chain.sh:430` intent-gap scan `break` | unchanged since round 2; still a warning |

## Per-AC scoring

| AC | Rung | Score | Evidence |
| --- | --- | --- | --- |
| AC-1 | oracle | **satisfied** | `ledger-lint-selftest.sh` green in the full sweep. `(ll-o)` drives all three Kind values and both dispositions against a real receipt; `(ll-q)`-`(ll-u)` and `(ll-aa)` the ratification bar and the `OR-n` citation arms; `(ll-y1)`/`(ll-y2)` pin mode isolation both directions. Default mode unchanged with no fixture edits — `exitplan-ledger-gate-selftest.sh` green |
| AC-2 | oracle | **satisfied** | `check-lean-chain-selftest.sh` all green. `(S0)` fixture exclusion, `(S0b)` cross-issue scoping, `(S1)` the unratified refusal, `(S2)` the uncited-`yes` refusal, `(S3)` the clearing case, `(S4)` first-match. Absence is printed, not silent — asserted by `(S0)`/`(S0b)` |
| AC-3 | proxy | **satisfied** | `BASELINE.md`: 5/5 seeded gaps, class agreement 4/5, 4 grounded extras, and the S-4 disagreement resolved in the probe's favor per the README's own rule. Recorded in the PR body as the AC requires. The dispatch-by-body caveat is disclosed. Unchanged since round 1 |
| AC-4 | critic | **satisfied** | Loop rule 8 in `interviewing-baseline`, applied at the interviewer (§Step 1 exit criterion, ledger-seed section) and the orchestrator (its own "No draft-first (P8)" section + Step 5.5 receipt exit gate). `spec-reviewer`'s Discovery Coverage carries all four named sub-items — rung per AC, ratified-provenance share, dispositions on open regions, zero-open-regions-on-non-trivial-scope as a finding |
| AC-5 | oracle | **satisfied** | `check-lockstep-pairs.sh` — 13 pairs, 0 failed, both `provenance-enum` rows green. All three edited guards enumerated base-vs-head in the PR body; the one retired baseline row is the `--help` line, and `(T)` kills it in both sed dialects. `catalog::ledger-lint-empty-decision` still anchors. Read as "check and record the evidence, re-baseline if the sites moved" — the alternative reading makes the AC unsatisfiable whenever ordinals legitimately hold, which is the defect the mid-run restatement fixed |
| AC-6 | critic | **satisfied** | `check-changelog-trailer.sh origin/main` — OK |
| AC-7 | critic | **satisfied** | `interviewing-baseline` carries all four required items in full — Kind axis, ratification bar, Open Regions contract, and the intent-gap record schema including the merge-boundary consequence. `run-lean/SKILL.md:52-53` now names both mandated clauses, at 60/60. See above |

The spec is byte-identical to the tree round 1 scored (`git diff 181a805..HEAD --
docs/plans/second-shift-346-lean.md` is empty), so nothing was amended after the fact to match
the diff.

## Strengths

- **The fix took the narrow reading of its own remedy.** Round 2 said "restore the clause, do
  not revert the stderr routing" — and both hold at head. The tempting cheap discharge (drop the
  gate line, reclaim the budget) was available and not taken.
- **Round 1's B-1 remains genuinely discharged.** I spot-checked the surviving refusals rather
  than assuming: the `elif [[ -z "$GAP_BY" ]]` arm cannot be deleted with the suite green, which
  is exactly the property round 1 was buying.
- **The eval baseline is honest about what it is.** Dispatch-by-body is disclosed as a real
  difference from production dispatch, with the `maxTurns` consequence named and a re-check
  scheduled after release — rather than presented as an equivalent run.
- **`(S0b)` and `(T)` are the two cases that could each have been written as theater and were
  not** — a cross-issue record for #99, and a help-range assertion pinned in both directions so
  it kills on BSD and GNU sed alike.

## Reviewers

| Reviewer | Verdict | Findings | Confidence |
| --- | --- | --- | --- |
| Scope Completeness | Pass | 0 (1 suppressed) | — |
| Maintainability | Pass | 0 | — |
| Unit Test Mutation | Pass (nits) | 4 | 83–90 |

Round-3 lineup reduced per review-lead's prior-round rule: the reviewer holding round 2's
findings, the one whose domain the fix commit touches, and the unconditional scope gate. No
reviewer went dark. W-1 is the orchestrator's own finding — no reviewer raised it, and none was
given the spec.

## Verification run

Run in the PR head worktree at `e36e168`, tree clean:

- `shellcheck -e SC1091,SC2015,SC2181` over every `*.sh` — clean
- `jq empty` over every `*.json` — clean
- Full selftest sweep, `-P 4`, **without `SKIP_STRESS`** — exit 0, no failing suite
- `check-lockstep-pairs.sh` — 13 pairs, 0 failed
- `check-changelog-trailer.sh origin/main` — OK
- W-2's mutant applied by hand and reverted; the tree was confirmed clean afterwards and the
  suite re-run green against the restored file
