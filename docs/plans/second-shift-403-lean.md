# #403 — a merge from the base branch must not void a lean approve the patch-id arm proves is still fresh

## Problem

`check-lean-chain.sh` evidence 5 (freshness) runs TWO arms unconditionally: the INFERRED arm
(a two-dot `git diff --name-only VERDICT_COMMIT PR_HEAD_SHA`) and the DECLARED arm (keyed on
`reviewed_patch_id` when present, else `reviewed_head`). The inferred arm's two-dot diff counts
every commit the base branch gained since the branch point as a change to the branch under
review. A rebase escapes this only incidentally (the record stays the tip, so the diff is
empty); a merge from base — e.g. GitHub's "Update branch" button — lands commits strictly
after the record's commit, and the inferred arm fires a false violation even when the declared
arm, which measures the branch's own diff against the (now-current) base, is unaffected and
still passes.

Observed live on PR #400 / issue #392.

## Fix

Give the declared arm precedence over the inferred arm whenever the record carries a
`reviewed_patch_id`: skip the inferred arm's computation entirely in that case, and let the
declared arm be the sole freshness check. This is the same one-way, never-AND-ed precedence the
neighboring code comment already applies between `reviewed_patch_id` and `reviewed_head` inside
the declared arm itself — extended one level up, to the choice between the two arms.

Records predating the `reviewed_patch_id` key have no declared arm to defer to, so the inferred
arm stays their sole check, unchanged.

## Acceptance criteria

- **AC-1** (oracle — `check-lean-chain-selftest.sh`): a lean PR whose head is a merge from the
  configured base branch, whose record declares a `reviewed_patch_id` matching the recomputed
  one, passes the chain with no violation.
- **AC-2** (oracle — selftest): a record carrying no `reviewed_patch_id` still gates on the
  inferred arm exactly as today — a merge from base still violates for those.
- **AC-3** (oracle — selftest): a genuine post-record change (a fix commit landing after the
  record) still violates, under both record shapes.
- **AC-4** (verified manually, not a permanent selftest case): the AC-1 case reds the suite when
  the fix is reverted.

## Out of scope

Changing what `reviewed_patch_id` measures, and the `reviewed_head` SHA path that records
predating that key gate on.
