# Bind the lean verdict to the branch's patch identity, not a commit SHA — #372

## What this closes, precisely

#363 gave the verdict record a **declared** freshness arm: the reviewer writes
`reviewed_head: <sha>`, and both readers refuse when that SHA is absent from history or when
anything but the record differs between it and the head. That arm catches a real hole — a
reviewer who reads head A, waits while a fix lands at B, then commits an honest record on top
of B leaves the **inferred** arm (which anchors on the commit carrying the record) with nothing
to complain about.

It also fires on a **rebase**, and that is the defect. A rebase rewrites commit SHAs and changes
no reviewed content; in CI's fresh checkout the pre-rebase object does not exist at all, so
`git cat-file -e` hard-fails and the gate demands a whole new review round for a mechanical
operation. Observed on PR #368 between the round-3 approve and the merge attempt: the branch's
own patch was byte-identical across the rebase and the record still had to be re-stamped by hand.

The arm's own rationale concedes the mismatch — SHA identity cannot tell a clean replay from a
conflict resolution, so it charges a round for the common harmless case and buys nothing extra
for the rare harmful one.

**The fix is to key the declaration on patch identity instead of commit identity.**
`git patch-id --stable` hashes patch *content*: invariant under rebase, blob-hash churn and
hunk-offset shifts, and it moves the moment a commit or a conflict resolution changes a line.
Empirically confirmed before writing this spec — a clean rebase over a moved base returned the
identical id, and a one-line change moved it.

So the new arm is **strictly stronger** than the one it replaces, not a relaxation: it still
reds every post-approve push, and it additionally *distinguishes* a resolution from a replay,
which the SHA arm cannot express at all.

Explicitly **not** covered, and stated in the code rather than implied away: a base change that
breaks the branch with no textual conflict. The patch-id is unchanged there and the verdict
correctly still stands — the merged result failing is CI's job. Conflating the two is what made
the SHA arm over-strict in the first place.

## Decisions

- **D-1 — the key is `reviewed_patch_id:`, a 40-char hex id.** Same `<key>: <token>` shape as
  `run_id:`/`session_id:`/`reviewed_head:`, so every existing extractor (`record_key`, the
  `grep -oE` in `check-lean-chain.sh`, `lean-reconcile.sh`) reads it unchanged. No key contains
  another as a substring, so first-match extraction stays unambiguous.
- **D-2 — the id is computed over `merge-base(base, head)..head`, excluding the verdict record
  path.** The exclusion is required on **both** sides and is the one thing a plausible
  implementation gets wrong: at write time HEAD does not yet carry the record, at read time it
  does, so without it the recompute never matches and the arm reds on every correct record.
- **D-3 — precedence: `reviewed_patch_id` present ⇒ it is the gate.** The SHA-keyed
  `cat-file -e` and `diff --name-only <reviewed_head>` refusals do not run. `reviewed_head`
  stays in the record as a diagnostic pointer (OR-1's reversible default: keep it). Its
  *presence* is still required — that refusal predates this change and is unrelated to
  freshness — but it stops being a refusal about staleness on its own.
- **D-4 — `reviewed_patch_id` absent ⇒ today's SHA path, unchanged.** Records written before
  this key was emitted stay readable rather than being refused by the upgrade itself. Unlike
  #363's migration posture, no remedy is *needed* here: the old path is not wrong, only
  over-strict, and a pre-key record that passes it is a record whose head never moved.
- **D-5 — an empty patch-id is a refusal, never a match.** `git patch-id` prints **nothing**
  for an empty diff (verified). Two empty strings compare equal, so an unguarded implementation
  turns "the computation failed" into a silent ✓ over nothing — the exact fail-open shape
  `check-lean-chain.sh`'s (Q1)/(Q2) cases close one level up. Both the write side and both read
  sides refuse on an empty or unresolvable id.
- **D-6 — OR-2, resolved: each reader uses the base it already has.** `lean-gate.sh` uses the
  configured `topology.repos[<host>].baseBranch`; `check-lean-chain.sh` uses `PR_BASE_REF`,
  which is all CI has (the runtime config is gitignored and never reaches a checkout — the
  same constraint that makes the artifact suffixes a lockstep pair there). They agree whenever
  the PR targets the configured base, which is the lean contract: `run-lean` step 3 cuts the
  worktree from the configured base. A PR retargeted elsewhere is off-contract and reds at the
  merge boundary — fail-closed. The alternatives were rejected as disproportionate: resolving
  the PR's declared base in `lean-gate.sh` puts a network call inside the one write path that
  must never mis-stamp a record, and a recorded `reviewed_base_ref` key buys a diagnostic at
  the cost of another schema key and another refusal arm. The residual cost is a misleading
  message, so the CI refusal **names the base it resolved against**.
- **D-7 — the pass lines name their arm.** `patch-id <short>` on the new path, the existing
  `declaring reviewed_head <short>` wording on the fallback. Without this, AC-3's case cannot
  distinguish "the fallback ran" from "the new arm ran and happened to pass", and a change that
  silently dropped the fallback would stay green.

## Acceptance criteria

- **AC-1** (oracle — `lean-gate-selftest.sh`): milestone 4 passes a record whose
  `reviewed_patch_id` matches the current head **after a rebase that replays the branch
  unchanged** — including the case where the declared `reviewed_head` is orphaned by that
  rebase, which is the shape the old arm hard-failed on — and fails one where a commit landed
  after the record was written.
- **AC-2** (oracle — `check-lean-chain-selftest.sh`): evidence 5's declared arm does the same at
  the merge boundary, including the case the current arm cannot express: a rebase whose conflict
  resolution changed a line is refused, while a clean replay passes.
- **AC-3** (oracle — both suites): a record carrying `reviewed_head` but no `reviewed_patch_id`
  still gates on the existing SHA path, and the pass line identifies that arm (D-7), so the case
  cannot be satisfied vacuously by the new arm.
- **AC-4** (oracle — both suites): the exclusion holds — a record committed on top of the
  reviewed head recomputes to the same patch-id.
- **AC-5** (critic — doc scope): `run-lean`'s SKILL.md no longer says a rebase reopens milestone
  4; `review-lean`'s SKILL.md no longer says a rebase voids the verdict; and
  `check-lean-chain.sh`'s header states what the patch-id does and does not cover.
  *(The issue's AC-5 names `interviewing-baseline` for the second surface. That is a slip —
  `plugins/intake-toolkit/skills/interviewing-baseline/SKILL.md` contains no occurrence of
  `rebase`, `verdict` or `reviewed_head`, verified by grep. `review-lean/SKILL.md:59` is the
  file that carries the prose the issue describes, and is covered here instead. This AC is not
  narrowed: all three named surfaces are covered, one of them re-pointed to the file that
  actually holds the text.)*
- **AC-6** (oracle — CI): the generic mutation survivor ordinals of every guard this diff edits
  are checked against `tools/mutation-baseline.tsv` and re-baselined if they moved, with the
  site-level evidence recorded in the PR body either way.
- **AC-7** (critic): the PR carries a `Changelog:` trailer.
- **AC-8** (oracle — vacuity, D-5): an unresolvable or empty patch-id on either read side is a
  refusal, not an unmeasured pass. Covered on both readers, because the two compute it from
  different inputs and neither guard implies the other.

## Out of scope

- Dropping `reviewed_head` from the record (OR-1's non-default). It stays as a diagnostic
  pointer and as the fallback path's key.
- Any change to the **inferred** freshness arm, in either reader. It anchors on the commit
  carrying the record, survives a rebase already, and is untouched.
- Detecting a base change that reds the suite without a textual conflict. Named above as CI's
  job; documented, not gated.
