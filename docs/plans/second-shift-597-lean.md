# second-shift #597 — a base advance must not invalidate a verdict whose reviewed lines never changed

Issue: [#597](https://github.com/manoldonev/second-shift/issues/597)
Pre-flight ledger: `.claude/pipeline-state/597-ledger.md` (binding input — gitignored, so its
load-bearing content is restated here)

## Problem, as pinned

A base advance costs a full review round and a manual verdict re-stamp on a PR whose own diff
never changed. On #583/PR 593 it spawned a review session against an unmoved head, then forced a
re-stamp for a merge that altered not one reviewed line.

The pre-flight ledger pinned three separately-reproducible parts. **The ticket named two candidate
mechanisms and neither is right**; the ledger's findings supersede them:

- **F1 — why REVIEW spawned.** `verdict_rc` (`orchestrate-lean.sh`) is anchored in the lane
  worktree (`wt="$(lane_worktree)" || return 3`). The close-out session had already run teardown,
  so `verdict_rc` returned **3** without ever reaching the gate. Because 3 is non-zero it fell into
  the `else` arm, which spawns REVIEW on **every** non-zero rc; the `case` that routes 3 to
  `terminal worktree-missing` is only reached AFTER the spawn.
- **F2 — an arm the ticket does not mention.** The INFERRED freshness arm,
  `git diff --name-only "$v_commit" HEAD`, sees 23 files after a base merge and reds before the
  patch-id arm is reached. A fix confined to patch-id does not satisfy AC-1.
- **F3 — the re-stamp, reproduced.** `1decd12550cd -> 86daf57fb18e`. Only `CLAUDE.md` and
  `docs/testing.md` moved — the exact two files #595 touched — and they moved because their
  **context lines** changed. All eight files' `+`/`-` sets are byte-identical.

**Binding operator constraint:** invalidation happens only when the base change is certain to have
affected the PR's own changes. **On any doubt, the verdict stands.**

## Acceptance criteria

- **AC-1:** WHEN the base advances and the merge introduces no change to any line the PR's own diff
  adds or removes THEN the verdict STANDS — milestone 4 passes, no review is spawned, and the merge
  boundary does not red.
- **AC-2:** WHEN the head has not moved since a verdict was gate-confirmed against it THEN no REVIEW
  is spawned, regardless of base movement. An unmoved head is a re-run, not a round. Concretely
  (F1): `verdict_rc`'s cannot-answer codes are routed **ahead** of the REVIEW spawn, and rc=3 with
  milestone 5 satisfied ends the run as COMPLETE.
- **AC-3:** WHEN invalidation does fire THEN the log names WHICH of the PR's own changed lines the
  base is judged to have affected — the file, a count, and the first offending `+`/`-` line inline.
  A path that cannot enumerate one does not invalidate; the enumeration is the invalidation's
  precondition, not its decoration.
- **AC-4:** WHEN the branch's contribution is compared before and after a base merge THEN the
  comparison is over the `+`/`-` lines of the per-file diff, each side measured against its own
  merge-base — not over a patch-id whose input includes the merge-base.
- **AC-5:** WHEN this lands THEN regression guards reproduce the #583 sequence: a verdict confirmed
  at head H, an unrelated commit landing on the base touching a file the branch also touches, and
  NO review spawned and NO re-stamp needed.
- **AC-6:** WHEN the contribution comparison itself cannot be computed THEN the verdict STANDS and
  the gate line NAMES the fail-open and its reason, so the declared exposure (OR-1) is visible in
  the log of every run it fires on rather than inferable only from the code — and BOTH routes into
  that class are driven by a case: a `reviewed_head` this checkout cannot read, and both sides
  computing with one contribution coming out EMPTY. The second is the one with teeth, since an
  unguarded reader compares the empty side against the full one and INVALIDATES; a guard covering
  only the first route reads as complete while the second stays dark.
- **AC-7:** WHEN `build-lean`'s and `review-lean`'s prose state that a later commit reopens
  milestone 4 while a rebase does not THEN they also state the base-merge case this change adds,
  because this change makes that prose stale.

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | What the scheduler does when `verdict_rc` cannot answer (rc 2/3) | Move the cannot-answer codes AHEAD of the REVIEW spawn — the treatment #531 already gave 4 and 6, whose stated reason ("neither is something a review could clear, so spawning one is pure cost") covers 3 verbatim. On rc=3 consult `progress --satisfied 5`, which the scheduler already calls: satisfied means the lane finished and teardown ran, so the run ends as COMPLETE under new terminal vocabulary; unsatisfied falls to the existing `terminal worktree-missing`. The gate is NOT ref-parameterized (rejected: `REPO_ROOT` is CWD-derived at `lean-gate.sh:493`, and that surface belongs to #141) | user-answered |
| D-2 | How the branch's own contribution is identified | Recompute from the record's existing `reviewed_head` — no new record key, no schema change. When the patch-ids differ, hash the `+`/`-` lines of the per-file diff at `reviewed_head` and at HEAD, each against its own merge-base, and compare. `LEAN_VERDICT_HEADER_KEYS`, the lockstep manifest, `ledger-lint.sh` and the boundary's parsing are all untouched; every in-flight and already-merged record stays readable with NO re-stamp obligation. The one case where `reviewed_head` is absent from history is a rebase — which patch-id already covers, so the two are complementary | user-answered |
| D-3 | Relationship between the inferred arm (F2) and the declared patch-id arm | ONE shared `contribution_unchanged?` predicate, consulted by both `lean-gate.sh:4329` and `lean-gate.sh:4396` as their escape hatch: the naive check reds, the predicate is asked, identical `+`/`-` lines passes and the line says so. Two implementations of "did the reviewed content move" is the drift the lockstep markers exist to prevent, and #394's comment already records the cost of one fact printing as three violations | user-answered |
| D-4 | Whether the merge boundary gets the same tolerance in this PR | YES, same PR. Without it milestone 4 passes and `pr-gates` still reds on the identical base merge — which is what forced the #583 re-stamp — so AC-1 would be only half-true end-to-end. Feasible as-is: `pr-gates` checks out at `fetch-depth: 0`, passes the real head commit as `PR_HEAD_SHA`, and `lean-evidence.sh` already reads the record with the same `record_key` that yields `reviewed_patch_id`. The gate-side and evidence-side predicates carry a `scripts/lockstep-manifest.tsv` row | user-answered |
| D-5 | Default when the contribution comparison itself cannot be computed | The verdict **STANDS**. Per AC-3's letter ("an invalidation that cannot name one is the 'doubt' case and must let the verdict stand") and the operator's session directive: re-reviews only in absolutely grounded cases; on any doubt, let it slide. This is a deliberate fail-open on a freshness check and is declared as OR-1 rather than left implicit | user-answered |
| D-6 | What AC-3's "names WHICH lines" means concretely | An invalidation line ENUMERATES the affected reviewed lines: the file, a count, and the first offending `+`/`-` line inline, matching the existing arms' `(e.g. X)` style. A path that cannot enumerate one does not invalidate — the enumeration is the invalidation's precondition, not its decoration | user-answered |
| D-7 | `render_patch_id` and its `check-lean-chain.sh:816` copy, which carry the identical merge-base flaw | OUT OF SCOPE. It gates only the ARMED design-render lane; this repo arms no ticket, so it cannot fire here, and widening spends velocity on a path with no live consumer. The latent flaw is declared as OR-2 rather than dropped. Scope-trimmed under the operator's "VELOCITY is key" directive | user-delegated |
| D-8 | Where AC-5's regression guard lives | Three tiers, per CLAUDE.md's tier map — the change spans two tools and a composed path, so no single suite covers it: a leg in `lean-gate-selftest.sh` (the two gate arms), a leg in `orchestrate-lean-selftest.sh` (the rc=3 spawn decision), and a scenario in `skills/build-lean/scenario-liveness-selftest.sh` (the composed verdict path reaching a terminal write) | codebase-derived |
| D-9 | Sequencing against the adjacent open tickets | #590 (removing the close-out spawn) touches the same close-out region of `orchestrate-lean.sh` — sequence by landing order, whichever is second rebases; no blocking dependency, since #590 is unlabelled and unqueued. #141 is the same CLASS (which tree the gate grades) but a different defect, and D-1 deliberately declines to ref-parameterize the gate, so the two do not collide. Neither is a duplicate: `dup-scan.sh --issue 597` returned rc=0 (corpus 5), and a manual read of all 39 open issues found no other claimant | codebase-derived |

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | A freshness check that cannot compute its own comparison now passes rather than fails | reversible-default-and-flag |
| OR-2 | The armed design-render lane (`render_patch_id`) keeps the identical merge-base flaw | reversible-default-and-flag |

**OR-1.** Every other unreadable-input path in this gate fails closed — "a check that cannot run
must not report a pass" is written into three of its own refusals. D-5 points this ONE predicate
the other way, on the operator's explicit instruction and AC-3's explicit wording. The residual
exposure, stated plainly: if the `+`/`-` comparison cannot be computed for a head whose patch-id
moved, an unreviewed change can pass milestone 4 and the merge boundary. Reversing it is a
one-line default flip in a single predicate, and the gate line must say which way it defaulted
and why, so the exposure is visible in the log of every run it fires on rather than inferable
only from the code.

**OR-2.** No consumer in this repo arms the design lane, so the flaw cannot fire here today. It
becomes live the first time a ticket arms one, and there is no guard that would notice — this
row is the record that it was seen and deferred, not missed.

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | milestone-4 ✗ line when a base merge moved the patch-id AND a reviewed line genuinely changed | decided (D-6) |
| S-2 | milestone-4 ✓ line when the escape hatch passes — must say the patch-id moved and why that did not invalidate | decided (D-3) |
| S-3 | Scheduler control line at rc=3 with milestone 5 satisfied — the run ends as complete, not as an error | decided (D-1) |
| S-4 | Scheduler control line at rc=3 with milestone 5 unsatisfied — existing `terminal worktree-missing` | decided (D-1) |
| S-5 | `pr-gates` violation line at the merge boundary, and its passing counterpart | decided (D-4) |
| S-6 | The line printed when the comparison cannot be computed — must name the fail-open | decided (D-5) |
| S-7 | The armed design-render lane's fidelity and manifest lines | out-of-scope — D-7; this repo arms no ticket, so no run reaches them |
| S-8 | Tracker comment and PR body copy | out-of-scope — this change writes no tracker or PR text; it only alters gate and scheduler log lines |

**Scope note on D-3.** The escape hatch is wired into exactly the two arms D-3 names. The legacy
`reviewed_head` SHA arm (records predating `reviewed_patch_id`) is left as-is: both keys are in
`LEAN_VERDICT_HEADER_KEYS`, so no record a current `review-lean` writes can reach it, and widening
there would be a decision the receipt never covered (P9).

## Design

Design: none — this repo configures no `design.provider`, and the change alters gate and scheduler
log lines only. No user-facing surface, no route, no render state.

## Implementation

### 1. The shared predicate (AC-4, D-2, D-3, D-4)

A `LOCKSTEP-BEGIN contribution-compare` block, byte-identical in
`plugins/dev-pipeline/skills/build-lean/lean-gate.sh` and
`plugins/dev-pipeline/skills/build-lean/lean-evidence.sh`, carrying three functions:

- `contribution_lines <repo-root> <base-ref> <head-ish> <exclude-path>` — the `+`/`-` lines of
  `diff(merge-base(base-ref, head), head)`, tagged with their path. Column-0 anchored state machine:
  inside a hunk every line carries a ` `, `+`, `-` or `\` prefix, so a body line reading
  `diff --git …` or `@@ …` at column 0 cannot exist. A naive `/^[+-]/` would have eaten the
  `---`/`+++` file headers and mistaken a removed line beginning `-- ` for one.
- `contribution_delta <repo-root> <base-ref> <old-head> <new-head> <exclude-path>` — rc **0** the
  contributions are identical, **1** they differ (stdout enumerates `path<TAB>count<TAB>first`,
  `LC_ALL=C sort`ed for determinism), **2** the comparison could not be computed.
- `contribution_summary` — the rc=1 rows on stdin, rendered as one line in the existing arms'
  `(e.g. X)` style. No silent cap: past the third file it says how many more there are.

An empty contribution on either side is rc=2, not rc=0 — the same guard `branch_patch_id`'s header
already states: two failed computations compare EQUAL, and an unguarded reader prints its ✓ having
hashed nothing.

`scripts/lockstep-manifest.tsv` gains a `contribution-compare verbatim` row over the two blocks.

### 2. `lean-gate.sh` milestone 4 (AC-1, AC-3, AC-6)

A memoized gate-side wrapper `contribution_state <old> <new>` binds the predicate to
`$REPO_ROOT`, `origin/$BASE_BRANCH` and `$VERDICT_REL`, and is asked with
`("$v_head", HEAD)` — the record's own `reviewed_head`, per D-2.

Both arms consult it when their naive check reds:

- the **inferred** arm (`git diff --name-only "$v_commit" HEAD`);
- the **declared** patch-id arm (`reviewed_patch_id` vs `branch_patch_id HEAD`).

rc=1 fails with the D-6 enumeration. rc=0 falls through, and the milestone-4 pass line says the
patch identity moved and why that did not invalidate. rc=2 also falls through, and the line names
the fail-open (AC-6, OR-1).

### 3. `lean-evidence.sh` `arm_freshness` (AC-1, D-4)

Reads `reviewed_head` from the record and, on a patch-id mismatch, asks the same predicate against
`origin/$PR_BASE_REF` and `$PR_HEAD_SHA`. rc=1 keeps the existing violation, extended with the
enumeration; rc=0 and rc=2 pass, each with its own line.

### 4. `orchestrate-lean.sh` (AC-2, D-1)

`verdict_rc`'s cannot-answer codes route ahead of the REVIEW spawn:

- **rc=3** (no lane worktree): `progress --satisfied 5` non-zero ⇒ `terminal closed-out 0`, the run
  is COMPLETE; zero ⇒ the existing `terminal worktree-missing 1`.
- **rc=2** (the gate could not run): `terminal verdict-unreadable 2`, no spawn — a review cannot
  clear a gate that could not run, so spawning one is pure cost.

The now-unreachable `3)` arm of the post-spawn `case` is removed and the removal is stated in place.

Note on what the escape hatch makes `reviewed_head` worth. When the patch-ids disagree,
`reviewed_head` becomes the arm's authority — D-2's decision, and it is what re-shapes
`lean-evidence-selftest.sh`'s case (s): a fabricated `reviewed_patch_id` alone no longer reds, so
that fixture now lands a real code commit after the record and the case asserts the enumeration.
This is no weaker than before: the reviewer writes both keys, and what keeps either honest is the
authorship arms proving a separate review session wrote the record.

### 5. Docs (AC-7)

`build-lean/SKILL.md` and `review-lean/SKILL.md` each carry a sentence saying a later commit reopens
milestone 4 while a rebase does not. Both gain the base-merge case, edited in place so neither
SKILL grows a line.

## Verification

- `find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181`
- `find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty`
- `bash tools/run-selftests.sh --exclude tools/install-topology-selftest.sh`
- `bash scripts/check-lockstep-pairs.sh`

## Non-goals

- Changing what a REAL conflict resolution does — if the resolution alters a reviewed line, the
  verdict SHOULD be invalidated.
- `render_patch_id` / the armed design-render lane (D-7, OR-2).
- Ref-parameterizing the gate (D-1; that surface belongs to #141).
