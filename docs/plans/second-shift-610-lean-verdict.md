# lean review verdict — #610

verdict=needs-work
run_id: review-610-4
session_id: 469ac7a7-2726-42f8-8086-f430c57931bf
rounds: 4
pr: #625
reviewed_head: 0135a3b9425a3d650650f9028609722fe80123a8
reviewed_patch_id: 30f0e0d21b377cc4bce56b1357fe60e7dfd43225
inherited_patch_id: ae9a73a241a4a8081985dccd7cae87551cc4239c
inherited_from_verdict: 5462f4634fd3bb47e15d88aad980c22c1d172d48
fidelity: not-applicable
model: unknown
capabilities: pr-marker

Round 4, inheriting round 3's coverage of patch `ae9a73a241a4`. Delta read: `5462f463..HEAD` —
the trap fix, the second `origin/main` merge, and the two triage rows that merge minted. I read
wider than the range: the whole branch contribution against the merge-base (`c4a8dd22..HEAD`, 18
files), because the merge puts #626's content in the delta and reading only the range would
confuse main's work for this branch's.

Verdict: **needs-work** — one blocker, and it is not this round's work. Round 3's blocker is
genuinely fixed and every AC is satisfied; the base moved again while the round was running.

## Round 3's blocker is closed, measured rather than read off the commit message

**B-5 (the `EXIT`-trap leak under bash 3.2) — fixed, and fixed in the killable direction.**
`census` no longer arms a trap; it captures the pipeline's status, removes its temp, and returns
the captured status. Probed in an isolated worktree at the reviewed head, scoring each mutant
under brew bash 5.3.9 and under a `bash` shim that `exec`s `/bin/bash` 3.2.57 (the harness that
reproduces the CI lane):

| Tree | bash 5 | bash 3.2 |
| --- | --- | --- |
| shipped head | 52 passed, 0 failed | 52 passed, 0 failed |
| cleanup block deleted (`local rc` / `rm` / `return`) | **51 / 1** | **51 / 1** |
| `return "$rc"` → `return 0` | 52 / 0 | 52 / 0 |
| `(census)` subshell unwrapped | 52 / 0 | 52 / 0 |
| pre-fix trap form restored | 52 / 0 | **51 / 1** |

The last row is round 3's CI red reproduced exactly, which is what makes the first row's green
trustworthy rather than merely reassuring. The second row is the point of the chosen remedy:
deleting the cleanup now fails under **both** shells, where the trap form failed only under 3.2
— on the one lane nobody reads until it is too late. `selftests (macos, bash 3.2)` is green on
this head, along with `lint-and-selftests`.

Also verified: no `die` is reachable between `mktemp` and the cleanup — the two argument-validation
`die`s precede the allocation, and `hash_stdin`'s runs at source time — so nothing the trap used to
cover is now uncovered. `set -uo pipefail` without `-e` is what makes `local rc=$?` reachable at all.

**Round 3's two comment notes are closed honestly.** The suite's comment no longer claims the
`(census)` subshell holds two traps apart, and says the `CREATED` bar proves the shim was reached
rather than pinning `check`'s own two allocations. Both statements are true of the shipped tree —
the probe above independently measures the subshell revert as killing nothing, which is precisely
what the new comment says. Naming what a fix cost is the opposite of the usual failure mode here.

**The stale PR-body prose-budget figures are corrected.** `prose-budget.sh --check` on this head:
3 fails, and they are exactly the three pre-existing rows (`QUERIES.md`,
`figma-faithful-spec-reviewer.md`, `capability-parity-check-selftest.sh`), none of which this
branch touches. `build-lean` 1687, `review-lean` 1657, `onboard` 5106 all read `ok`, matching the
body.

## Blocker

### B-6 — the base moved again: the PR is CONFLICTING, and the resolution cannot leave the reviewed lines intact

#621 ("milestone 3 stops running the full sweep locally, and the supervision stratum goes with
it") landed on `main` at `9f2b5d00` while this round was running. `gh pr view 625` now reads
`CONFLICTING` / `DIRTY`, and `git merge-tree HEAD origin/main` names one conflicted file:

```
CONFLICT (content): Merge conflict in tools/run-selftests-selftest.sh
```

That file carries this branch's own round-1 edit, so resolving it edits `+`/`-` lines that are
inside the reviewed patch — `reviewed_patch_id` is recomputed at milestone 4 and at the merge
boundary, and an `approve` written now would be void on arrival there. Approving and handing back
cost the same number of sessions; the hand-back is the honest one. (Everything else auto-merges:
`build-lean/SKILL.md`, `tools/mutation-slow-suites.tsv`, `.claude/prose-budget-shell.baseline.tsv`.)

**Resolve this one by taking MAIN'S side whole — do not keep both sides.** This is the opposite
of round 2's resolution and the reason is worth reading before touching the file:

- This branch's edit to that file is the SELFTEST_JOBS case gaining `-u LEAN_SELFTEST_CACHE_DIR`
  alongside the hostile `LEAN_JOB_CEILING=2` it already carried.
- #566/#621 **deleted the job ceiling outright**: `LEAN_JOB_CEILING` no longer appears anywhere in
  `tools/run-selftests.sh` or `lean-gate.sh` on `main`. Keeping this branch's side resurrects a
  variable nothing sets and nothing reads.
- Main's copy of that case already carries this branch's contribution and more: it hand-rolls the
  `-u LEAN_SELFTEST_CACHE_DIR` scrub, puts a **hostile store** in front of it, and asserts
  two-sidedly (`jobs=3` **and** the absence of `activated from LEAN_SELFTEST_CACHE_DIR`). Its
  comment even records that the argument was re-pointed from the deleted ceiling to the seam the
  gate still hands down.

So main's version subsumes the branch's, and the check afterwards is one command:
`git diff origin/main HEAD -- tools/run-selftests-selftest.sh` must print nothing.

**The merge mints no census work — measured, not assumed.** I censused both base commits in
throwaway roots (`PROSE_BLOCKERS_ROOT` over a `git archive` of `plugins/` at each): `c4a8dd22` and
`9f2b5d00` both yield **38 constructs with byte-identical ids**. #621 changed no
construct-bearing block, so unlike the previous merge this one re-keys nothing and adds no row —
AC-6 survives it, and `check` should still read 13 constructs / 35 rows / rc=0 on the merged tree.
Confirm rather than assume, but expect no work here.

## Warnings

- **The rc-propagation half of the round-4 fix is unguarded.** Mutating `return "$rc"` to
  `return 0` leaves the suite at 52/0 under both shells (measured above), and
  `unit-test-mutation-reviewer` predicted the same site independently (confidence 82). It matters
  in one direction: `check` reads `(census) >"$tmp_census" || exit $?`, so a masked failure would
  let `check` compare the record against a truncated census and report `✓ zero undispositioned`
  vacuously — a fail-open in a verification tool. The status capture is correct as written; what
  is missing is a case that drives `census`'s pipeline to a non-zero exit and asserts `check`
  refuses. Not a blocker, and not new breakage — the pre-fix code returned the pipeline's status
  implicitly, so this is an unguarded *preservation* of correct behavior rather than a regression.
  Worth one case whenever this file is next open; it is small.
- **The PR body's Round 3 paragraph is stale**: it says "12 constructs, 34 rows" where the head
  reads 13 and 35 after the round-4 dispositions. The AC-6 block in the same body is correct.
  Body-only, so it costs no round — one edit alongside the B-6 fix.
- **`mutation-sweep-pr` is green on this head and computed ZERO verdicts**, unchanged from round 3
  and for the same designed reason (`tools/prose-blockers.sh` is deferred wholesale by the
  slow-list row this PR adds). I closed the substance instead of assuming it: cold PR-scoped sweep
  in an isolated worktree with the deferral overridden and its own cache dir —
  `applied=8 killed=8 survived=0`, **9 verdicts computed live, 0 served from cache**, 45s.
  `sites_beyond_budget: cmp-z:4+logic:23+default:1` is unchanged, so the cleanup site is still
  outside the mutant budget and the hand-written leak case remains the only thing covering it.
- **`tools/prose-blockers.sh.bak` is sitting untracked in the lane worktree.** It cannot reach the
  PR (untracked, outside `git diff`) and does not touch `reviewed_patch_id`, but it will confuse
  the next session's `git status`. The build session recorded that a bare `rm` was denied to it;
  worth clearing by hand.

## Per-AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | Live on this head: `census` emits 13 rows over 26 files, two consecutive runs byte-identical, tier line `stop=13 (default), bold=59, all=227 - the default excludes 214`. The behavioral selftest is 52 cases and is 52/0 under bash 5 **and** bash 3.2 — the case that reported round 3's defect now passes because the defect is gone, not because the case was weakened (deleting the fix still fails it, 51/1, under both). |
| AC-2 | satisfied | 35 rows, exactly one disposition each — 30 `gate-backed`, 4 `promoted`, 1 `deleted`; `check` rc=0 with zero undispositioned over the merged tree. The two rows this round adds are the merge working as designed: `pb-5658947b` is the exit-code table re-keyed in place (content-derived ids; the base added a code) and `pb-30bb039d` is genuinely new to the corpus, a block that acquired a stop marker when the base appended a sentence about milestone 1's refusal. Both `pointer-kept` — deleting prose the base just wrote would re-litigate a landed PR, which is not this prune's call. The all-dark rule still keeps its operative site (`pb-94ee597a`); only its duplicate went. |
| AC-3 | satisfied | `check`'s mechanical arm resolves every enforcer path. I read the two new rows' sites rather than grepping them: `orchestrate-lean.sh` emits all eight codes 0–7 that `run-lean/SKILL.md`'s table names, and `lean-gate.sh` really does refuse an unresolved pause-and-ask region at milestone 1 (`override_affordance` prints the per-region `record` command for an attended session), so `pb-30bb039d`'s prose is a pointer at a real refusal rather than a rule with no control. |
| AC-4 | satisfied | All four `promoted` rows are `filed`; #622, #623 and #624 are all still OPEN. No guard shipped, which D-1 authorizes for anything larger than one-guard-small. |
| AC-5 | satisfied | Six tab-separated columns on all 35 rows; every disposition and action inside the declared enums (`check`'s malformed-record arm would exit 4 otherwise). The two new rows key their enforcer on the declared path-plus-tuple format. |
| AC-6 | satisfied | `check` on this head: `census: 13 construct(s) over 26 file(s); record: 35 row(s)`, `✓ zero undispositioned constructs`, rc=0. No standing CI guard wired, per D-9 and the AC's own text. |
| AC-7 | satisfied | `prose-budget.sh --check`: 3 fails, all three pre-existing and untouched by this branch. The regenerated rows record post-prune truth; `build-lean` reading 1687 against a 1624 row is the base's later prose, inside the +5% tolerance and correctly NOT re-regenerated — regenerating would raise the ratchet for prose this PR did not write. The shell baseline gains exactly the two new files. Residual ownership (#553/#554/#566/#541, and the agent-contract corpus routed to phase 2) is named in the record header per row. |

Design fidelity: `not-applicable`. The spec disarms it (`Design: none`) and the repo's config
declares no `design.provider` and no `stageParams.webComponentGlobs`, so the disarm is justified
rather than convenient.

## Panel

Six reviewers selected, **six returned** — no dark reviewer this round, after
`test-coverage-reviewer` went dark in rounds 2 and 3. Five `approve` with zero findings
(security, maintainability, complexity, test-coverage, scope-completeness);
`unit-test-mutation-reviewer` returned `approve-with-nits` with the one finding recorded as a
warning above. Security's three findings were all suppressed below threshold and correctly so
(operator-supplied env in a local CLI with no request surface). Scope-completeness surfaced the
stale body paragraph at confidence 70, also recorded above.

`performance-reviewer` was **not selected**, under the round-2+ lineup-reduction rule: it returned
zero findings in three prior rounds and the round-4 change (removing a trap, adding an `rm`) has no
performance surface. Not a coverage gap by darkness — a deliberate narrowing, named so it is
visible. `a11y-reviewer` and the design-fidelity dimension were not routed: no changed path matches
`stageParams.webComponentGlobs` (`apps/web/**/*.{tsx,jsx}` — the shipped default; this repo
declares none). `db-reviewer` and `pipeline-reviewer` were not triggered.

## What round 5 needs

Merge `origin/main` (`9f2b5d00`) and resolve `tools/run-selftests-selftest.sh` by taking main's
copy whole — the branch's edit there is subsumed, and keeping both sides resurrects a variable
#566 deleted. Verify with `git diff origin/main HEAD -- tools/run-selftests-selftest.sh` printing
nothing, then re-run `bash tools/prose-blockers.sh check` on the merged tree (expect 13/35/rc=0 —
the two bases census identically, so no new row is owed) and fix the body's "12 constructs, 34
rows" line. Nothing else is outstanding: the three warnings above are notes, not gates.

## Strengths

- **The fix chose the killable shape over the convenient one.** Keeping the trap and adding an
  `rm` beside it would have been green everywhere a build session looks and killable only on the
  macOS lane; removing the trap makes the cleanup the sole path, so deleting it fails under both
  shells. The commit message argues exactly that, and the probe confirms it.
- **The round names what the fix cost.** With `census` trap-free the `(census)` subshell no longer
  holds two traps apart, and the suite's comment now says so instead of claiming a kill it no
  longer makes — measured true here. A build session volunteering the weakening of its own prior
  guard is rare and is what stopped this round rediscovering it as a finding.
- **The merged-in prose was dispositioned rather than pruned.** Re-keying a construct in place and
  admitting a new one as `pointer-kept` is the record behaving as designed under a content-keyed
  id scheme; deleting prose the base had just deliberately written would have been the tempting
  and wrong move.
