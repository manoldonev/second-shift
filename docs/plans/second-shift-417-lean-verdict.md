# lean review verdict — #417

verdict=approve
run_id: review-417-3
session_id: 48042dd1-6025-4d7e-b2ca-34b34c893ef1
rounds: 3
pr: #420
reviewed_head: 55a91555b67eb0dec4552adcc0e295f28adfb7f3
reviewed_patch_id: 1fec4979fcd6a9f9068dc2102e1d0782c96c777c
inherited_patch_id: fb21f1e0d879c0a8134da4f606a38b41a10f172e
inherited_from_verdict: 9c8f86352303b4d705b0515726e92920999dffbf
fidelity: not-applicable
model: unknown

## Round 3 — approve (re-stamped after a `main` merge)

Range read: `9c8f863..HEAD` (delta since the tree round 2 covered, inheriting patch `fb21f1e0d879`),
**read wider** to the branch's whole contribution for the AC scoring and the scope gate. Reviewed
from the lean worktree at the PR head. Design section unarmed, so fidelity scores `not-applicable`.

Round 2's single blocker is cleared, and cleared correctly — the fix resolves the sibling rather than
papering over an absent one, which is the failure mode that would have read identical. All six of
round 2's warnings are addressed but one, which is closed only in part. No blockers in the diff.

**Why round 3 is RE-STAMPED rather than round 4 spent.** A `main` merge landed after the round-3
record was written, with one conflict. The branch's contribution across that merge is **byte-identical**:
`diff` of the two contribution diffs shows 798 `+`/`-` lines on each side and **zero** differences —
every delta is a blob hash, one hunk offset, or a context line. That is the re-stamp test, and it
passes, so no round is owed. The recomputed `reviewed_patch_id` still moved
(`f305fbbf1410` → this record's value) because the surrounding context shifted, which is why the
record is rewritten at all.

**The conflict, and how it was resolved.** One file, `tools/mutation-baseline.tsv`. This branch
removes `audit-history.sh::logic::2`; main's #435 anchors three new `lean-evidence.sh` rows
immediately after that line. Disjoint guards, so the resolution is the union — the branch's four
removals and one addition, plus main's three rows. Verified not by inspection but by construction:
the resolved file is **byte-identical** to main's copy minus this branch's removals plus its
addition. The TSV's pre-existing sort-order complaint (line 6, the `catalog::` block) reproduces
identically on main's own copy, so it is not an artifact of the resolution.

**Authorship, stated plainly.** This review session performed that merge resolution at the operator's
instruction, so for that one hunk the reviewer is not independent of the author. The mitigation is
that the resolution is mechanically checkable rather than a judgment call, and the check above is the
one a reader can re-run. Nothing else on the branch was touched by this session.

### The round-2 blocker is cleared

B1 was: `lean-gate-selftest.sh` **(d5)** and `lean-reconcile-selftest.sh` **(R)** reached the sibling
`audit-toolkit` plugin through `$HERE/../../../audit-toolkit/…`, a hop count that holds only in the
marketplace repo. From a version-keyed install cache both took their not-found branch, redding
`tools/install-topology-selftest.sh`.

The fix is a two-rung ladder in each suite: the repo layout, else the lexically-newest cache-layout
sibling that carries an **executable** hook. Hop counts are right in both layouts, and it mirrors
`check-model-tiers.sh`'s `resolve_sibling_plugin_root()`. Both ladders survived the merge intact.

Verified at the pre-merge head:

| Check | Result |
| --- | --- |
| Staged cache, **both** plugins present | `rc=0` on both suites, and **(d5)** / **(R)** each printed their `PASS:` line — the cases RAN, not skipped |
| Staged cache, **`audit-toolkit` absent** | `rc=1` on both suites, at the `audit hook not found — searched <repo path> and <cache path>` branch |
| Staged cache at the **pre-fix** tree (`9c8f863`), sibling present | `rc=1` on both — so the ladder is what closed it, not the staging |
| Full local sweep, no `SKIP_STRESS`, `-P 4` | **rc=0**; `install-topology-selftest.sh`: 55 ran, **51 passed, 4 known-red, 0 red** (was 49/2-red) |
| CI `selftests (macos, bash 3.2)` | **success** |

The second row is the one that matters. Staging both plugins and watching green proves resolution
works; it does not prove the case can still **fail**. A fix that turned the assertion into a silent
skip would have produced an identical green — a defect `install-topology-selftest.sh`'s own header
names ("passing vacuously"). It reds.

### CI: the mutation-sweep red was a harness artifact, not this PR's debt

The first CI attempt red `lint-and-selftests` at the PR-scoped mutation sweep. Not a finding:

1. **Every survivor is baselined.** All twelve across the three swept guards. The only baseline-absent
   id, `lean-reconcile.sh::cmp-z::1`, is the one the sweep itself corrected to **KILLED** and
   explicitly told us not to baseline.
2. **The sweep classifies it as its own fault** — `RED: pool disagreement … the harness is at fault,
   not the guard`, and the exit contract calls it "the harness contradicting itself, **never a
   coverage gap**". No in-diff remedy exists, by the sweep's own instruction.
3. **It does not reproduce, and it re-ran green.** A local diff-scoped sweep on the same tree gave
   **identical** survivor sets (6/4/2, 9/5/4, 13/7/6) with no disagreement, rc=0; re-running the CI
   job on the unchanged head returned **`lint-and-selftests: success`**.

The mutant also predates the branch at that site: `cmp-z::1` keys the `sed -n '2,Np'` help line,
ordinal 1 at both `3b9c810` and the head — the branch moved the range, not the `-n `.

Note for triage: rounds 1 and 2 never saw this red because `run all selftests` failed first and the
sweep step was **skipped**, not passing.

### Two build-role obligations the merge imported — build side, not review findings

This run started 2026-08-06 and has now merged `main` twice. Two gate contracts shipped in between
that its build session never had the chance to satisfy. Both remedies are **build-role** calls; the
review session must not make either, and neither costs a review round:

- **`bash G entry 417`** — #422 added an entry-attestation precondition over `claim|delta|all|1..5`.
  This run's progress file has no `entry` row (milestones 1–3 were recorded before that gate shipped),
  so milestone 4 will refuse until it is recorded.
- **`bash G mark 417`** — #430 restructured `check-lean-chain.sh` to delegate to the new
  `lean-evidence.sh`, which requires a bot-authored build-identity marker comment on the PR. PR #420
  carries none; the payload's zero-marker branch raises a violation ("the BUILD run's identity is
  unknown and the verdict's independence is uncheckable"), so `pr-gates` will red on it.

The marker one is pointed: that arm compares the marker's `run_id`/`session_id` against the verdict's,
so a marker posted by *this* session would trip the very independence violation it exists to catch.

### Round-2 findings, re-checked

| # | Round-2 finding | Status |
| --- | --- | --- |
| W1 | PR body named the reconcile fixture `(Q)`; it is `(R)` | **fixed** |
| W2 | `audit-selftest.sh:224` cited `(N)` | **fixed** — now `(R)` |
| W3 | spec OR-1 **and AC-2's last sentence** | **partly fixed** — see W3′ |
| W4 | spec OR-2's latency left unmeasured | **fixed** — +16–17 ms/call, ≈ +37%, with method |
| W5 | the "four removals" paragraph contradicted its own table | **fixed** |
| W6 | PR title had no conventional prefix | **fixed** |

### Warnings

| # | Severity | Where | Finding |
| --- | --- | --- | --- |
| W3′ | warning | spec AC-2, last sentence | Round 1's warning named **two** sites: OR-1 and AC-2's trailing sentence. OR-1 was corrected; AC-2 still reads "No new failure mode for any layout: the fallback *is* the status quo" — the exact reasoning OR-1 now retracts with its submodule / bare-checkout table. AC-2 is the normative one. Carried at its original severity, not escalated |
| W7 | nit | both suites' rung 2 | `tail -1` picks the **lexically** newest version dir, so with `2.1.0` and `10.0.0` staged it selects `2.1.0`. Correct today (the cache holds `2.0.0 < 2.0.1 < 2.1.0`) and inherited verbatim from `resolve_sibling_plugin_root()`, so a consistent pre-existing pattern, not a new gap. When it bites the result is a false red, not a vacuous pass. Worth a follow-up fixing both copies and the precedent together |

Checked and dismissed: the ladder being duplicated rather than factored out (each suite must resolve
its own sibling; drift breaks nothing; the precedent carries no lockstep row and the comment says so),
and `for … done | tail -1` under `set -uo pipefail` with no `set -e` (the assignment is unchecked; the
green bash-3.2 lane confirms portability).

### Per-AC scoring

Scored by the letter, every AC every round, against the whole spec.

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 writer anchors on the main checkout, both common-dir forms | satisfied | inherited — `audit-tool-calls.sh` byte-identical to the tree rounds 1–2 covered |
| AC-2 fallback is today's path, hook never blocks | satisfied | mechanism ships and is pinned (Tests 12/13); scored on its mechanism, with the trailing generalization carried as W3′ |
| AC-3 `audit-history.sh` resolves identically, held by a `verbatim` row | satisfied | `check-lockstep-pairs.sh`: 18 pairs, 0 failed |
| AC-4 `/audit` + `QUERIES.md` + onboarding name the resolved dir | satisfied | inherited — byte-identical |
| AC-5 `audit-selftest.sh` covers (a)(b)(c) against a throwaway repo | satisfied | green in-repo and under the install topology; only the `(N)`→`(R)` comment token changed this round |
| AC-6 the false refusal is pinned | satisfied | `(d5)` green in the repo **and now from a staged cache**, where it previously could not run at all |
| AC-7 the second reader is pinned on its DEFAULT path | satisfied | `(R)` likewise; still sets no `LEAN_AUDIT_DIR` |
| AC-8 the location contract is stated where it was false | satisfied | inherited — unchanged |
| AC-9 the mutation registry is re-keyed in this diff | satisfied | the round-3 delta touches only `*-selftest.sh` and spec prose, which the sweep's guard universe excludes by rule, so no ordinal moved. `cmp-z` ordinals re-derived at both revs: ordinal 1 is the same site. Local diff-scoped sweep: every survivor baselined. The merge's baseline resolution is the verified union above |

AC-6 and AC-7 are the two the round-2 blocker bore on, and both are stronger than when round 1 scored
them: the pins existed then but were unreachable from any install.

### Verification performed

| Check | Result |
| --- | --- |
| Full selftest sweep at the pre-merge head, no `SKIP_STRESS`, `-P 4` | **rc=0**, 0 failures |
| `tools/install-topology-selftest.sh` (pre-merge head) | 55 ran, 51 passed, 4 known-red, **0 red** |
| Staged-cache probes: sibling present / absent / pre-fix tree | pass-and-RAN / red / red |
| Local diff-scoped `mutation-sweep.sh --mode pr` | rc=0, survivor sets identical to CI, **no pool disagreement** |
| `shellcheck`; `jq empty`; lockstep; frozen-files; changelog-trailer | clean / clean / 18 pairs 0 failed / clean / present |
| Reviewer panel over the round-3 delta (6 reviewers) | 6/6 usable, **no dark reviewers**, 0 critical, 0 warnings, 1 nit (= W7) |
| CI re-run on the unchanged pre-merge head | `lint-and-selftests` **success** |
| Merge conflict resolution | proven byte-identical to the clean union |
| Branch contribution across the merge | **byte-identical**, 798 `+`/`-` lines, zero differences |
| Both ladders after the merge | present and intact in each suite |

**Stated rather than implied.** The full selftest sweep was run to completion on the **pre-merge**
tree, not on the merged one; the merged tree's sweep is delegated to CI, which is the authority and
runs it cold on both lanes. The branch's own contribution is byte-identical across the merge, so what
changed under this record is the base, not the reviewed code — the class of risk that leaves is a
base-imported guard, which is exactly what CI is positioned to catch and a local run is not.

`bash G delta 417` could not be run: #422's entry precondition gates it and this run has no `entry`
row. Running `entry` from the review session would forge a build-role attestation, so the range was
re-derived by hand from `cmd_delta`'s own algorithm (`inherit_candidate` → `fb21f1e0…` at `9c8f863`,
then the matching commit in `base..HEAD`), and this round read wider than it anyway. The gate derives
`inherited_patch_id` itself at `verdict` time, so the chain keys are unaffected.
