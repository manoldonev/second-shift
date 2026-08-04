# A lean fix round reviews the delta since the reviewed patch

Closes #375.

A round-*n* verdict record (n ≥ 2) declares the patch identity it **inherited** coverage from, so
the round can read the delta since that tree instead of the whole diff again. The record chain is
what keeps the merge boundary's guarantee intact: today it is "an independent review read this
exact tree"; under inheritance it becomes "a chain of independent reviews collectively covered
this tree, every link verified". Without verified links, delta review would be a silent weakening,
which is why the chain is checked by all three readers rather than recorded and trusted.

## Resolved open regions

The issue names three. Their dispositions were followed, and both answers are the operator's:

| ID | Region | Resolution | Provenance |
| --- | --- | --- | --- |
| OR-1 | Inheritance: reviewer's judgment, or a mechanical property of the record | **Mechanical.** `lean-gate.sh verdict` derives the inheritance keys; there is no flag. | operator answer, this run (`pause-and-ask`) |
| OR-2 | May a `needs-work` round be inherited from | **Yes** — coverage and verdict are separate properties. | operator answer, this run (deviates from the receipt's reversible default) |
| OR-3 | Depth cap on the chain | **No cap** — the receipt's reversible default. Each link is verified against a patch identity rather than trusted transitively, so depth buys no additional trust to bound. Reversible: adding a cap later only ever forces more reading. | receipt default |

**OR-1 rationale.** Every other provenance key in the record is derived from the checkout and
explicitly refuses an argument — `reviewed_head` and `reviewed_patch_id` both carry the reasoning
that a flag lets the caller name something it never read. An `--inherit-from` flag is that same
shape. Deriving it also means a round cannot silently *forget* to record its inheritance, which
would read downstream as a full-coverage claim it did not perform. Honest limit, stated so it is
not overclaimed: this enforces that the declared chain is **real**, not that the reviewer read the
delta. Reading remains the reviewer's obligation exactly as it is for the full diff today.

**OR-2 rationale, and the deviation.** The receipt's reversible default was "inherit only from an
`approve`". Applying it would make the feature inert in the issue's own motivating case — the cost
table is `round 1 → needs-work → fix → round 2`, and under that default round 2 could never
inherit. A `needs-work` round did read the whole tree; its **coverage** is valid and its
**findings** are unresolved. AC-7 hands round *n* the prior findings, so a blocker whose fix is in
the delta is re-read, and a blocker the build ignored is still visible and still a blocker. The
risk the default was guarding — carrying a finding forward as though resolved — is addressed by
that, not by refusing the inheritance.

## Design

**Content-keyed, not SHA-keyed.** The chain is walked by matching `reviewed_patch_id` values, not
commit SHAs. This is #372's own precedent applied one level up: a SHA link dies on a rebase, and
the resulting refusal would charge a review round for a mechanical operation — the exact defect
`reviewed_patch_id` was introduced to remove. `inherited_from_verdict` is recorded as a
human-readable pointer and diagnostic, in the same role `reviewed_head` now holds; no reader gates
on it.

**No new state.** The verdict record is overwritten at one path each round, so the round history is
already `git log -- <verdict path>`. A prior round's record is `git show <commit>:<path>`.

**Two new keys**, written only when a prior round exists:

```
inherited_patch_id: <the reviewed_patch_id of the round this one inherits coverage from>
inherited_from_verdict: <commit carrying that record — pointer, not a gate key>
```

**Which round is inherited from:** the most recent committed version of the record whose
`reviewed_patch_id` differs from the one this round is about to write. The "differs" clause makes a
same-round re-run idempotent (`review-lean` allows re-running a round on the cached identity)
rather than self-inheriting. A prior record carrying no `reviewed_patch_id` (written before #372)
cannot be inherited from; the round degrades to a root record, which is AC-4's shape.

**The delta range** is anchored by patch identity, not by a commit name: `bash G delta <issue>`
walks the branch's own commits and selects the one whose branch patch identity equals
`inherited_patch_id`, then prints `<that commit>..HEAD`. That keeps the range computable after a
rebase, when the SHA the prior record was committed at no longer exists. Unresolvable ⇒ it prints
the full range and says so.

**The search runs strictly backwards.** Each reader's search window starts below the commit
carrying the record it is reading and shrinks past every hit. Two things ride on that. A fix
round can revert the branch to exactly the tree an earlier round reviewed — "the blocker says
the change was wrong" — and the head record's reviewed patch is then an identity an ancestor
record also carries; an unbounded search resolves that round to *itself*, and every honest chain
through it reads as a cycle, making a correct branch unmergeable by a legal fix. A shrinking
window also makes termination structural, so there is no cycle counter to get wrong (and none to
sit unkillable in the code).

**Fail-closed everywhere.** A declared `inherited_patch_id` matching no earlier record on the
branch is refused, by all three readers — never downgraded to "treat it as a root record", which
would convert an unverifiable claim into a satisfied one.

**Each reader keeps its own distinctive arm.** Milestone 4 and the merge boundary ask whether the
links resolve. `lean-reconcile.sh` asks, additionally, whether the chain is a sequence of
*independent* reviews: one session that writes round 1 and then inherits its own coverage in
round 2 produces a chain that resolves perfectly while being a single review. That is the arm
only the operator-side reader can meaningfully make, and inheritance is what makes it
consequential. Considered and dropped: an "each link's commit is an ancestor of the one
inheriting it" arm — on a lean branch the record path is linear and HEAD-anchored, so the
predicate holds by construction, and an arm no fixture can red is coverage in appearance only.

## Acceptance criteria

- **AC-1** (oracle): a round-2 record whose `inherited_patch_id` equals round 1's
  `reviewed_patch_id` passes the merge boundary; one declaring an identity matching no earlier
  verdict record on the branch is refused.
- **AC-2** (oracle): the delta range is computed from the inherited patch identity — resolved by
  matching a branch commit's patch identity, so it survives a rebase — and a fix touching code the
  earlier round already read appears **in** that range.
- **AC-3** (oracle): a chain whose middle link matches no earlier record is refused with a message
  naming the round that broke it (its `rounds:` value), not a generic staleness error.
- **AC-4** (oracle): a round-1 record — no `inherited_patch_id` — is unaffected in all three
  readers, so the change is additive and pre-chain records stay readable.
- **AC-5** (oracle): a record whose `inherited_patch_id` is present but whose prior record is not
  reachable in this checkout is **refused**, never silently degraded to a full-coverage claim.
- **AC-6** (oracle — authorship): a round-*n* record carrying the build run's identity is refused
  exactly as today; inheritance opens no path around P10.
- **AC-7** (critic — `review-lean`): the skill states when a round may inherit and when it must
  re-read in full, and directs the reviewer to the prior record's findings — a round that inherits
  coverage without seeing what was previously found cannot tell a fixed blocker from a
  re-introduced one.
- **AC-8** (oracle): `lean-reconcile.sh` reconciles a multi-round chain, so the third reader does
  not fall behind the other two.
- **AC-9** (oracle — CI): the generic mutation survivor ordinals of every guard this diff edits are
  checked against `tools/mutation-baseline.tsv` and re-baselined if they moved, with the
  site-level evidence recorded in the PR body either way.
- **AC-10** (critic): the PR carries a `Changelog:` trailer.

## Out of scope

- Any change to who may author a verdict, or to the one-identity-per-round rule. This narrows what
  a round must **read**, never who may **write**.
- Consumer-side promotion. `check-lean-chain.sh` and `lean-reconcile.sh` remain dogfood-scoped.
