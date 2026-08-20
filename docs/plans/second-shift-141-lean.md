# second-shift #141 — lean-gate.sh asserts it is grading the lane tree

**Ticket:** [#141](https://github.com/manoldonev/second-shift/issues/141) — *lean-gate grades
whichever tree it is invoked from — a shared-checkout run reports a confident verdict against main.*

**The binding spec is the owner's re-scope comment of 2026-08-16**
([issuecomment-5309508824](https://github.com/manoldonev/second-shift/issues/141#issuecomment-5309508824)),
not the issue body. That comment retires the body's AC-1 through AC-4 and its `plan-lint` /
`prose-budget` riders verbatim: the original `verifyctl` mechanism was refuted at the 2026-07-20
intake (every lane already subshell-`cd`s into the statectl-derived worktree, so a CWD assertion
there was vacuous) and `verifyctl` itself died with #348. What survived is the defect CLASS, and
it now lives at the heart of the lean lane.

## The defect

`lean-gate.sh` resolves `REPO_ROOT` from the invoking shell's
`git rev-parse --show-toplevel` and asserts nothing about which BRANCH that root is on. Every
milestone answer is then derived from that tree: the spec path, the diff range, the verify lanes,
the render receipt. Run `bash G 3 <issue>` from the shared checkout and it grades `main` — and
reports a plausible verdict about it. The tells all read as good news (`nothing to sweep` on a
guard-adding diff; a selftest count one lower than the branch's), which is why hand-back
adjudications have burned review rounds arguing wrong-checkout.

`cmd_delta` has the same shape on the REVIEW side: it derives its range from `$REPO_ROOT` HEAD, so
from the main checkout it prints *"FULL range — nothing verifiable to inherit"* over an EMPTY
diff, and the reviewer reads nothing. `verdict` is protected today by prose alone
(`review-lean/SKILL.md` step 6: *"do not run this from the main checkout"*).

## The fix

After `REPO_ROOT` is resolved and before `require_entry_attested` runs, the milestone-evaluation
and review-role subcommands assert that `REPO_ROOT`'s checked-out branch IS this run's lane branch,
and refuse with a distinct exit when it is not. The roles that legitimately run from the main
checkout are not guarded at all, so nothing needs an opt-out to keep working; the opt-out exists
for the one consumer that drives the gate from fixture trees.

## Acceptance criteria

- **AC-1** — Each of `1`, `2`, `3`, `4`, `5`, `all`, `delta` and `verdict` refuses with **exit 9**
  when `REPO_ROOT`'s checked-out branch is not the run's `$LEAN_BRANCH`. The refusal happens
  before any evaluation: nothing is read, no progress row is appended, no fix attempt is charged,
  and no budget is spent. A **detached HEAD** (`rev-parse --abbrev-ref HEAD` = the literal `HEAD`)
  refuses on the same path — fail-closed.
- **AC-2** — The refusal names, in its own output: the branch found, the lane branch expected, and
  the path of every worktree already registered on the lane branch — falling back to the
  `git worktree add` command when none is.
- **AC-3** — The subcommands whose role IS the main checkout stay unguarded and unchanged:
  `entry`, `claim`, `mark`, `teardown`, `inflight`, `progress`, `staleness` and the internal
  `m3-run`. No `orchestrate-lean.sh` call site changes.
- **AC-4** — `LEAN_GATE_ANY_TREE=1` disarms the assertion, and every disarmed call announces that
  it did so on stderr, naming the branch found and the lane branch expected. The seam is listed in
  the header's Seams register.
- **AC-5** — Exit 9 is documented in `lean-gate.sh`'s header exit table and in
  `build-lean/SKILL.md`'s *Rules that are not negotiable*, and `--help` still prints the whole
  header block.
- **AC-6** — `review-lean/SKILL.md` is corrected where this change contradicts it: step 3 states
  that the PR head must be checked out **by branch name**; step 4's *"the main checkout always
  qualifies"* remedy is replaced (it was never necessary — the progress record is anchored at
  `--git-common-dir/..`, which a lane worktree resolves to identically); step 6's advisory
  *"do not run this from the main checkout"* is marked as now enforced.
- **AC-7** — `lean-gate-selftest.sh` covers, per case: the refusal on a guarded subcommand from a
  non-lane branch (exit 9, nothing recorded); the PASS when the tree IS on the lane branch; the
  detached-HEAD refusal; the refusal's worktree-naming arm and its `git worktree add` fallback;
  at least one unguarded subcommand still succeeding off the lane branch; and the disarm seam
  with its stderr announcement.
- **AC-8** — `tools/mutation-catalog.tsv` carries a row that mutates the new guard's dispatch arm
  and is killed by the AC-7 cases.

## Design

Design: none — this change renders nothing a user reads. Its only surfaces are operator-facing
stderr messages and a shell exit code; the repo configures no `design.provider`.

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Which subcommands the lane-tree assertion guards | The five milestones plus `all`, plus the two REVIEW-role subcommands `delta` and `verdict`. Grounded: `cmd_delta` (lean-gate.sh:4650) derives its range from `$REPO_ROOT` HEAD, so from the main checkout it prints "FULL range — nothing verifiable to inherit" over an EMPTY diff and the reviewer reads nothing; `verdict` is protected today by prose alone (review-lean SKILL.md:82). Deliberately NOT guarded: `entry` and `claim` (SKILL.md steps 1-2, before the worktree exists), `mark` (a PR comment write, reads no tree), `teardown` (runs from either side by design), `inflight` / `progress` / `staleness` (SCHEDULER role), `m3-run` (internal re-exec, inherits its guarded launcher's tree) | user-answered |
| D-2 | What the assertion compares | Branch-name equality: `git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD` must equal the already-derived `$LEAN_BRANCH` (lean-gate.sh:649). A detached HEAD yields the literal `HEAD` and therefore REFUSES — fail-closed, matching this file's posture throughout. A shared checkout with the lane branch checked out PASSES: the tree being graded is then correct, which is what the gate is actually about. Worktree-set membership via `lean_worktrees_for_branch` was considered and rejected as stricter than the defect requires | user-answered |
| D-3 | The opt-out mechanism, and its named consumer | An env seam `LEAN_GATE_ANY_TREE=1`, added to the documented Seams register in the header, which ALWAYS announces on stderr when it disarms — the precedent being this file's own config-path announcement, on the principle that a guard nobody can see disarmed is a guard nobody can audit. Its consumer is named rather than hypothetical: `lean-gate-selftest.sh`, whose roughly 208 guarded-subcommand call sites run from at least six fixture trees built with bare `git init`, against nine issue keys and three branch prefixes — one tree cannot be on nine lane branches. This is what the retired AC-3 could not supply. No scheduler consumer exists (see D-8) | user-answered |
| D-4 | The refusal's exit code | 9. Codes 0, 1, 2, 4, 5, 6, 7 and 8 are allocated; 3 is excluded deliberately because it is the RESERVED VERIFY-LANE INPUT CODE documented in the header, and reusing it would file "wrong tree" under "infrastructure died". A distinct integer also lets the new cases assert a code instead of grepping a message, which is what CLAUDE.md's no-prose-presence-guards rule wants. Semantics: NOTHING was evaluated, no fix attempt charged | user-answered |
| D-5 | Whether the refuse path gets a liveness scenario | No — per-tool cases only, and the reason is recorded in `scenario-liveness-selftest.sh`'s reach-boundary block so the next reach audit is a diff rather than a re-derivation. The ARMED PASS path is already composed for free: `scenario-liveness-selftest.sh:1279` and `:1679` define `g()` as a subshell that cds into a real worktree on `claude/acme-<key>` before invoking the real gate, so a wrong predicate reds three scenarios. The REFUSE path composes with nothing — exit 9 stops the run before any downstream component observes it — so a scenario for it would be a per-tool case in scenario clothing | user-answered |
| D-6 | Whether the new seam joins `SEAM_SCRUB` | No. It follows `LEAN_GATE_OBSERVE` and `LEAN_GATE_WAIT_CEILING_SECS`, both deliberately unscrubbed. `SEAM_SCRUB` is a `subset-of` lockstep row against `preflight.sh`'s superset and CLAUDE.md states it is not widenable from the lean-gate side alone, so scrubbing would drag `preflight.sh` and `scripts/lockstep-manifest.tsv` into the diff. Containment is at the case level instead: the new guard cases `unset LEAN_GATE_ANY_TREE`, exactly as `gate()` already unsets RUN_ID, CLAUDE_CODE_SESSION_ID and GH_BOT | user-answered |
| D-7 | Where the guard fires relative to `require_entry_attested` | BEFORE it, as its own `case "$SUB"` block ahead of the existing one at lean-gate.sh:5088-5090. Grounded: the entry refusal's exit-2 message already ends "Re-run from the build worktree before handing this back", so today a wrong-tree call surfaces as an entry-attestation failure naming the wrong primary cause. Ordering the branch guard first makes the real cause the reported one | codebase-derived |
| D-8 | Whether the scheduler needs the opt-out the ticket anticipated | It does not, and the ticket's parenthetical is superseded. `orchestrate-lean.sh` already cds to `$MAIN_ROOT` for every main-checkout-role call — `staleness` at 460 and 632, `inflight` at 649, `progress` at 658, 664 and 682 — and `verdict_rc()` at 610 cds to `lane_worktree()` before milestone 4. The main-checkout roles and the guarded set are already disjoint, so no scheduler call site changes | codebase-derived |
| D-9 | review-lean SKILL.md step 4's delta remedy, now contradicted | Its sentence "the main checkout always qualifies" must be corrected in this PR. It was singling out an unnecessary case: the progress record is anchored at `--git-common-dir/..`, which a lane worktree resolves to identically (lean-gate.sh:494-501), so the lane worktree always qualified too. New wording routes the exit-2 remedy through the lane worktree, or any checkout of the build host's clone with the lane branch checked out | codebase-derived |
| D-10 | review-lean SKILL.md step 6's `verdict` prose | Unchanged in substance but now ENFORCED rather than advisory: "do not run this from the main checkout — the record would name a patch you never reviewed" becomes an exit-9 refusal. Note this beside it so a reader does not take the rule as still unbacked | codebase-derived |
| D-11 | Mutation-sweep obligations landing in the same diff | One, not two. A `tools/mutation-catalog.tsv` row for the new guard, modelled on `lean-gate-entry-precondition`, which mutates the sibling dispatch arm this guard sits beside. There is NO re-baseline obligation: CLAUDE.md was amended on 2026-08-20 to state that generic survivor ids are content-keyed rather than position-keyed, so inserting the guard above or beside an existing site re-keys nothing. The one obligation that survives is re-anchoring: catalog anchors are literal seds, and `lean-gate-entry-precondition`'s sed matches the exact dispatch line this guard lands beside, so BUILD must confirm that adding a separate `case` block leaves that sed still matching | codebase-derived |
| D-12 | Where the exit-code table is mirrored | Two places only: the header block in `lean-gate.sh` and the "Rules that are not negotiable" section of `build-lean/SKILL.md`. Both take the 9 row. `orchestrate-lean.sh` maps no milestone rc that changes | codebase-derived |
| D-13 | Interaction with `LEAN_GATE_OBSERVE=1` | The guard applies uniformly and is not skipped under observe. Observe means "same taxonomy, record nothing" — a wrong-tree observe still returns a false ANSWER, which is the defect. `cmd_all`'s internal observe pre-pass runs after the top-level guard has already passed, so nothing double-fires | codebase-derived |
| D-14 | Which text is the binding spec | The owner's 2026-08-16 re-scope comment, not the issue body. It retires AC-1 through AC-4 and the plan-lint and prose-budget riders explicitly: https://github.com/manoldonev/second-shift/issues/141#issuecomment-5309508824 | ticket-sourced |
| D-15 | Branch naming when the reviewer obtains the PR head via `gh pr checkout` | Parked under OR-1 | deferred |

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | Whether `gh pr checkout` always produces a local branch named exactly `$LEAN_BRANCH`, which D-2's predicate requires of the REVIEW role | reversible-default-and-flag |

**OR-1, and why a default is safe here.** For a same-repo PR `gh pr checkout` names the local
branch after `headRefName`, which is `$LEAN_BRANCH` by construction — the build session pushes to
origin, so every lean PR in this repo is same-repo and the predicate holds. On a fork-origin PR
`gh` may name the branch `<owner>-<headRefName>`, which would refuse. The default is to ship the
predicate as decided and note the fork case in the refusal message, because reversing it is cheap:
the operator's remedy is one `git switch -c "$LEAN_BRANCH"`, and if a consumer ever runs the lean
lane from a fork the fix is a widened predicate, not a redesign. Flag it in the PR body so the
assumption is visible rather than discovered.

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | The wrong-tree refusal an operator reads on exit 9 — it must name the branch found, the branch expected, and the lane worktree path when one is registered, falling back to the `git worktree add` command when none is | decided (D-2, D-4) |
| S-2 | The stderr line printed whenever `LEAN_GATE_ANY_TREE` disarms the guard | decided (D-3) |
| S-3 | The exit-code table an operator consults, in the lean-gate.sh header and in build-lean/SKILL.md | decided (D-4, D-12) |
| S-4 | review-lean SKILL.md step 4, whose stated delta remedy stops being reachable | decided (D-9) |
| S-5 | review-lean SKILL.md step 6, whose advisory verdict rule becomes enforced | decided (D-10) |
| S-6 | The seam register in the lean-gate.sh header, which an operator reads to learn what may be overridden | decided (D-3) |
| S-7 | Rendered UI, routes, empty and loading states | out-of-scope — this change renders nothing a user reads; it is a shell guard whose only surfaces are operator-facing messages and exit codes |
