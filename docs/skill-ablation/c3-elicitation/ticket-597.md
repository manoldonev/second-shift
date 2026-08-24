# A base advance invalidates a verdict whose reviewed lines never changed

A base advance costs a full review round on a PR whose own diff never changed. On #583/PR 593 it
spawned one review session against an unmoved head, and then forced a manual verdict re-stamp for
a merge that altered not one reviewed line.

**Binding design constraint (operator, this session):** verdict invalidation should happen ONLY
when the base change is 100% certain to have affected the PR's own changes. **On any doubt, the
verdict stands.** The current behaviour is the opposite — it invalidates on a signal that cannot
distinguish "your lines moved" from "someone else edited the same file".

## What happened, with timestamps

| time (UTC) | event |
| --- | --- |
| 16:01:24 | `✓ milestone-4 … verdict=approve … covering the current head (patch-id 1decd12550cd)` — gate-confirmed at head `8c8d5cb` |
| 21:43:13 | milestone-5 satisfied; 21:43:24 teardown removed the worktree |
| **21:44:00** | **#595 merges to `main`** (`005bd3c`), touching `CLAUDE.md` and `docs/testing.md` |
| 21:45:02 | close-out `spawn BUILD exited 0` |
| **21:45:03** | **`spawn REVIEW — /dev-pipeline:review-lean 593`** |

At 21:45:03 the head was still `8c8d5cb` — `git log 8c8d5cb..origin/claude/second-shift-583`
was **empty**. The verdict covering it had been gate-confirmed 5h44m earlier and nothing on the
branch had moved since. The only thing that changed in that window is that someone else's PR
merged.

## Why the existing guard did not stop it

`orchestrate-lean.sh:819-822` already has the right guard:

```sh
verdict_rc; rc=$?
if [ "$rc" -eq 0 ]; then
  say "terminal-vocabulary: review-skipped-approved — the current head already carries an approve verdict …"
```

It did not fire, so `verdict_rc` returned non-zero for a head whose verdict had passed the same
check hours before, with no branch commit in between.

**The mechanism is NOT yet established and must be determined from the code, not assumed.** Two
candidates, both plausible and neither confirmed:

1. the staleness **base arm** — at 21:19 it printed `base arm clean — origin/main moved, but into
   no file this branch touches`, which was true of #592 (`plugins/**` only). #595 made it false,
   because it touches `CLAUDE.md` and `docs/testing.md`.
2. something in the milestone-4 freshness read that consults `origin/$BASE_BRANCH` at call time.

A build must pin which, and pin it by running the path — this ticket deliberately does not assert
one. (An earlier draft of this reasoning was wrong on the patch-id: see below.)

## The second cost — a re-stamp for a provably empty delta

After `origin/main` was merged in to clear the conflict (`5d6024e`), `reviewed_patch_id` moved:

```
1decd12550cd77340fef38cb1ddf98d290695b5a  ->  86daf57fb18eb6741c4410c47263e0e5360dda54
```

**Yet the branch's own contribution is byte-identical.** Hashing only the `+`/`-` lines of
`git diff ea299d6 8c8d5cb -- <f>` against `git diff origin/main HEAD -- <f>`, all **nine** files
match:

```
IDENTICAL  CLAUDE.md            IDENTICAL  tools/mutation-baseline.tsv
IDENTICAL  docs/testing.md      IDENTICAL  tools/mutation-catalog.tsv
IDENTICAL  tools/mutation-operators.tsv    IDENTICAL  tools/mutation-sweep-selftest.sh
IDENTICAL  tools/mutation-sweep.sh
IDENTICAL  docs/plans/second-shift-583-lean.md
IDENTICAL  docs/plans/second-shift-583-lean-verdict.md
```

The `CLAUDE.md` conflict was resolved as a **union** — #580's "where it runs" sentence above,
#583's reviewed content-keying sentences below — introducing no new branch line.

`branch_patch_id()` (`lean-gate.sh:780-787`) computes
`merge-base(origin/$BASE_BRANCH, head)` then `git diff <base> <head> -- . ':(exclude)$VERDICT_REL'`.
Merging `main` in **advances that merge-base**, so the id moves even when every reviewed line is
untouched. The gate's own header already anticipates the gap (`:763-765`): patch-id "still moves
the moment a commit — **or a conflict resolution** — alters a line". Here the resolution altered
none, and nothing can currently tell the difference.

## Acceptance criteria

- **AC-1:** WHEN the base advances and the merge introduces no change to any line the PR's own
  diff adds or removes THEN the verdict STANDS — no review is spawned and no re-stamp is required.
- **AC-2:** WHEN the head has not moved since a verdict was gate-confirmed against it THEN no
  REVIEW is spawned, regardless of base movement. An unmoved head is a re-run, not a round.
- **AC-3:** WHEN invalidation does fire THEN the log names WHICH of the PR's own changed lines the
  base is judged to have affected. An invalidation that cannot name one is the "doubt" case and
  must let the verdict stand.
- **AC-4:** WHEN the branch's contribution is compared before and after a base merge THEN the
  comparison is over the `+`/`-` lines of the per-file diff, not over a patch-id whose input
  includes the merge-base — the nine-file hash comparison above, mechanized.
- **AC-5:** WHEN this lands THEN a regression guard reproduces the #583 sequence: verdict
  confirmed at head H, an unrelated PR merges touching a file the branch also touches, and NO
  review is spawned and NO re-stamp is needed.

## Evidence / provenance

- Lane logs: `~/.cache/second-shift/lanes/run-583-r3.log` (**not** gitignored state — the
  `.claude/pipeline-state/583-*` receipts ARE gitignored and will not survive).
- PR 593 heads: reviewed `37bbfbd` -> verdict `8c8d5cb` -> merge `5d6024e` -> re-stamp `6dfb457`.
- The re-stamp itself is committed on PR 593 with the full nine-file identity proof.
- Prior art: #372 introduced `reviewed_patch_id` for exactly this class ("a rebase cannot
  invalidate a verdict about content"); this is the case it left open.

## Non-goals

- Changing what a REAL conflict resolution does — if the resolution alters a reviewed line, the
  verdict SHOULD be invalidated.
- The close-out/sleep failures seen on the same run (separate, environmental).

