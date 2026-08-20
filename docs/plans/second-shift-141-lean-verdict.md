# lean review verdict — #141

verdict=approve
run_id: review-141-1
session_id: fd0a2c63-489c-4569-bed4-8679d15c2352
rounds: 1
pr: #599
reviewed_head: 9a55d9a1c603490f1912bac33bfccafed3ed193c
reviewed_patch_id: 1423c68abc99d00a76a2ed402f0819b4e876b1ce
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: opus
capabilities: pr-marker

# Review round 1 — PR #599 / issue #141

**Verdict: approve.** No blockers. Three warnings, none of which leaves an `AC-n` unmet.

Range read: `06e48be..9a55d9a` (root round, whole branch diff — `bash G delta 141` printed the
full range, nothing to inherit). Reviewed from a checkout of the PR head on
`claude/second-shift-141`.

## Per-AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | `require_lane_tree` (lean-gate.sh:5084-5113) dispatched from the `case` at :5161 for `1\|2\|3\|4\|5\|all\|delta\|verdict`, exiting 9. Placement verified independently: the only top-level statements between `LEAN_BRANCH`'s derivation (:669) and that dispatch are variable assignments, function definitions and the role-keyed `resolve_cached_id` read — which passes `persist=0` for every guarded subcommand, so no path writes before the refusal. Detached HEAD reads back the literal `HEAD` and refuses. Cases `(lt1)`, `(lt1a)`, `(lt4)` green locally. |
| AC-2 | satisfied | The refusal prints the branch found, `$LEAN_BRANCH`, and every path from `lean_worktrees_for_branch` (plural by construction, #530), falling back to `git -C '$MAIN_ROOT' worktree add <path> '$LEAN_BRANCH'`. `(lt5)` / `(lt5b)` green. The fallback command correctly omits `--force`, because it is printed only on the branch where no worktree holds the ref. |
| AC-3 | satisfied | The guarded `case` list is literal and disjoint from the eight main-checkout roles. Verified against the scheduler independently of the PR body: `orchestrate-lean.sh`'s only guarded call is `verdict_rc()`:610, which `cd`s to `lane_worktree()` — a function that matches on `branch refs/heads/<BRANCH>` and so cannot return a detached or off-branch tree — and both files derive the branch through the same `resolve_branch_prefix` call, so the two names cannot diverge. Every other call site `cd`s to `$MAIN_ROOT` and runs an unguarded subcommand. `rc=9` is therefore unreachable there; if it ever were, the `*)` arm terminates as `verdict-gate-failed`, which is fail-closed. `(lt2)` green. See W2 for what `(lt2)` does not pin. |
| AC-4 | satisfied | `LEAN_GATE_ANY_TREE=1` returns 0 after a `warn` (stderr, :402). Listed in the header Seams register (:289-297) beside `LEAN_GATE_OBSERVE`. `(lt7)` / `(lt7a)` green. |
| AC-5 | satisfied | Header exit table gains the `9 =` row (:204-209); `build-lean/SKILL.md:38` under *Rules that are not negotiable*. `--help` range moved `2,297p` → `2,317p`; verified by hand that line 317 is the last header line (`# bash 3.2 compatible`) and 318 is `set -uo pipefail`, and the pre-existing case `(w)` — which asserts exactly that boundary — is green. |
| AC-6 | satisfied | `review-lean/SKILL.md` step 3 now says *by branch name* and names the fork-`gh pr checkout` remedy; step 4's *"the main checkout always qualifies"* is replaced with the lane-branch-checkout wording; step 6 is marked ENFORCED. D-9's grounding checked: `MAIN_ROOT` is `--git-common-dir/..` (:524), which a linked worktree resolves to identically. |
| AC-7 | satisfied | Ten new cases `(lt1)`–`(lt7a)`, all green in my own run: `lean-gate-selftest.sh` **all green, 463 cases**; `scenario-liveness-selftest.sh` **63 passed, 0 failed**. |
| AC-8 | satisfied | `lean-gate-lane-tree-arm` added to `tools/mutation-catalog.tsv`. Applied it myself under `sed -E` (the sweep's actual invocation, where `\|` is a literal pipe): it changes exactly line 5162 and the result is `bash -n` valid, so it is neither anchor-drift nor an invalid program. Its kill by `(lt1)` is structural rather than asserted — `(lt1)` enumerates all eight subcommands and requires `rc=9` from each, so narrowing the arm to `verdict` fails it. D-11's re-anchor obligation independently discharged: the sibling `lean-gate-entry-precondition` sed still matches after the insertion (applied, verified). |

Design: `not-applicable`. The spec disarms with `Design: none — this change renders nothing a
user reads`, and the disarm is justified: this repo's config carries no `design` key at all, so
there is no provider the disarm could be hiding from.

## What I checked beyond the ACs

- **Repo guards, all clean on this head**: `shellcheck -e SC1091,SC2015,SC2181` over the three
  changed shell files; `check-lockstep-pairs.sh` (22 pairs, 0 failed); `check-fail-open-shapes.sh`;
  `stack-generality-lint.sh`; `check-frozen-files.sh main`; `check-changelog-trailer.sh main`.
- **No other executor invokes a guarded subcommand.** Grepped every `.sh`/`.md`/`.yml` in the repo
  for `lean-gate.sh`: outside `lean-gate.sh` itself and the two suites that now export the seam,
  nothing dispatches `1`..`5`/`all`/`delta`/`verdict`. No CI workflow calls the gate, so the
  `actions/checkout` detached-HEAD shape cannot trip the new refusal.
- **Milestone 3's self-invocation is unaffected**: :3494 re-execs `m3-run`, which is outside the
  guarded set.
- **Commit hygiene**: `feat(dev-pipeline):` is the honest verb for a new capability, a
  `Changelog:` trailer with a `Migration:` line is present, `Closes #141` resolves
  (`closingIssuesReferences` populated), and no release-owned file is touched.
- **CI on 9a55d9a**: `lint-and-selftests` SUCCESS, `selftests (macos, bash 3.2)` SUCCESS,
  `mutation-sweep-pr` SUCCESS. `pr-gates` FAILURE, and its whole failure is
  `✗ no committed verdict record (a file named *-141-lean-verdict.md)` — the artifact this round
  produces. Nothing else in that job is red.

## Findings

| # | Severity | Where | Finding |
| --- | --- | --- | --- |
| W1 | warning | `plugins/dev-pipeline/skills/build-lean/SKILL.md`, `plugins/dev-pipeline/skills/review-lean/SKILL.md` | The diff pushes two instruction-layer files past the committed prose ratchet without re-baselining: `build-lean/SKILL.md` grows 1488→1623 words and `review-lean/SKILL.md` 1683→1788, both over the +5% tolerance in `.claude/prose-budget.baseline.tsv` (a TRACKED file). Measured: `prose-budget.sh` reports **3 fails on `main`, 5 on this head** — the two new ones are this PR's. It is a warning rather than a blocker because the job that runs it (`nightly-guards.yml`'s `prose-budget`) is scheduled nightly, not on the PR lane, and is *already* red on `main` (green 2026-08-17, red 2026-08-19 on the three pre-existing rows), so this cannot flip a green job. Remedy is one line: `bash plugins/dev-pipeline/tools/prose-budget.sh --update-baseline` and commit the two rows, or trim the prose to fit. |
| W2 | warning | `plugins/dev-pipeline/skills/build-lean/lean-gate-selftest.sh` `(lt2)` | AC-3 enumerates **eight** unguarded subcommands; `(lt2)` pins **five** (`entry progress teardown inflight staleness`). `claim`, `mark` and `m3-run` are unpinned, so an over-fire that added them to the guarded arm would ship green. **Measured, not predicted**: in an isolated worktree off this head I mutated the arm to `1\|2\|3\|4\|5\|all\|delta\|verdict\|claim\|mark) require_lane_tree` and ran both suites — `lean-gate-selftest.sh` **all green, 463 cases**, `scenario-liveness-selftest.sh` **63 passed, 0 failed**. The mutant survives everything. This is the shape CLAUDE.md's completeness rule warns about: `(lt2)`'s own title is honest about covering five, but the AC it serves names eight, and the reader of a green sweep sees "the unguarded set is pinned". Not a blocker — the ACs are met by their letter (AC-7 asks only for *"at least one unguarded subcommand"*), and a `claim` over-fire would make the lane unstartable on the very next run rather than reporting a false green, so it is not the silent-verdict class #141 exists to close. Cheapest fix is adding `claim mark` to `(lt2)`'s `for` loop; `m3-run` needs a `--m3-token` argument and so wants its own line. |
| W3 | nit | `plugins/dev-pipeline/skills/build-lean/lean-gate-selftest.sh` | The case whose comment header reads `# (lt5a) ...and with NO worktree registered...` emits `(lt5b)` in both its `pass` and its `fail` strings. The emitted id is the one that matters (it is what the PR body's mutation table cites and what any probe harness scores by), so the comment is the stale half — but a reader grepping the suite for `(lt5a)` finds a comment and no case, and `(lt5a)` names no case at all. One-character fix in the comment. |

## Round accounting

Round 1, `RUN_ID=review-141-1`. Approve — the two warnings and the nit are follow-up-sized and
none of them makes an `AC-n` unmet.
