# lean review verdict — #417

verdict=approve
run_id: review-417-3
session_id: 48042dd1-6025-4d7e-b2ca-34b34c893ef1
rounds: 3
pr: #420
reviewed_head: 2fe3c6a2120df64c214c554fb3995d888f16a41c
reviewed_patch_id: f305fbbf1410cfd7b655770c941dee80aefdcdd7
inherited_patch_id: fb21f1e0d879c0a8134da4f606a38b41a10f172e
inherited_from_verdict: 9c8f86352303b4d705b0515726e92920999dffbf
fidelity: not-applicable
model: unknown

## Round 3 — approve

Range read: `9c8f863..HEAD` (delta since the tree round 2 covered, inheriting patch `fb21f1e0d879`),
**read wider** to the branch's whole contribution (`origin/main...HEAD`, patch `f305fbbf1410`) for the
AC scoring and the scope gate. Reviewed from the lean worktree at the PR head. Design section unarmed
(the spec declares no `## Design`), so fidelity scores `not-applicable`.

Round 2's single blocker is cleared, and cleared correctly — the fix resolves the sibling rather than
papering over an absent one, which is the failure mode that would have read identical. All six of
round 2's warnings are addressed but one, which is closed only in part. No blockers.

**Why a round was spent rather than round 2 re-stamped.** Round 2 was `needs-work`; a fix commit
landed (`2fe3c6a`) and the branch's patch identity moved `fb21f1e0…` → `f305fbbf…`. A new round was
owed and there was nothing to re-stamp.

### The round-2 blocker is cleared

B1 was: `lean-gate-selftest.sh` **(d5)** and `lean-reconcile-selftest.sh` **(R)** reached the sibling
`audit-toolkit` plugin through `$HERE/../../../audit-toolkit/…`, a hop count that holds only in the
marketplace repo. From a version-keyed install cache both took their not-found branch, redding
`tools/install-topology-selftest.sh` — a guard that arrived on `main` with the merge and so could not
have been seen at the branch point.

The fix is a two-rung ladder in each suite: the repo layout, else the lexically-newest cache-layout
sibling that carries an **executable** hook. Hop counts are right in both layouts (from
`plugins/<plugin>/skills/<skill>/`, the repo sibling is `../../../<name>` and the cache form is one
more `../` for the version segment), and it mirrors `check-model-tiers.sh`'s
`resolve_sibling_plugin_root()`.

Verified three independent ways, at the reviewed head:

| Check | Result |
| --- | --- |
| Staged cache, **both** plugins present | `rc=0` on both suites, and **(d5)** / **(R)** each printed their `PASS:` line — the cases RAN, not skipped |
| Staged cache, **`audit-toolkit` absent** | `rc=1` on both suites, at the `audit hook not found — searched <repo path> and <cache path>` branch |
| Staged cache at the **pre-fix** tree (`9c8f863`), sibling present | `rc=1` on both — so the ladder is what closed it, not the staging |
| Full local sweep, no `SKIP_STRESS`, `-P 4`, `env -u CLAUDE_CODE_SESSION_ID -u RUN_ID -u LEAN_RUN_MODEL` | **rc=0**; `install-topology-selftest.sh`: 55 ran, **51 passed, 4 known-red, 0 stale rows, 0 red** (was 49/2-red) |
| CI `selftests (macos, bash 3.2)` on this head | **success** |

The second row is the one that matters. Staging both plugins and watching the suite go green proves
resolution works; it does not prove the case can still **fail**. A "fix" that turned the assertion
into a silent skip would have produced an identical green, and traded one red for an invisible hole —
which is a defect `install-topology-selftest.sh`'s own header names ("passing vacuously"). It reds.

### CI: the mutation-sweep red was a harness artifact, not this PR's debt

The first CI attempt on this head red `lint-and-selftests` at the PR-scoped mutation sweep. It is
**not** a finding, and the evidence is threefold:

1. **Every survivor is baselined.** All twelve reported survivors across the three swept guards are
   present in `tools/mutation-baseline.tsv`. The only baseline-absent id, `lean-reconcile.sh::cmp-z::1`,
   is the one the sweep itself corrected to **KILLED** and explicitly told us not to baseline.
2. **The sweep classifies it as its own fault.** The redding line is
   `RED: pool disagreement … the harness is at fault, not the guard`, and the script's exit contract
   names `pool disagreement` as "the harness contradicting itself, **never a coverage gap**". No
   in-diff remedy exists, by the sweep's own instruction.
3. **It does not reproduce, and it re-ran green.** A local diff-scoped sweep on the same committed
   tree produced **identical** survivor sets (6/4/2, 9/5/4, 13/7/6) with **no** disagreement, rc=0.
   Re-running the CI job on the unchanged head returned **`lint-and-selftests: success`**.

The mutant also predates the branch at that site: `cmp-z::1` keys the `sed -n '2,Np'` help line, whose
ordinal is 1 at both `3b9c810` and `HEAD` — the branch moved the range, not the `-n `.

This is the shape prior runs recorded: a baseline-absent survivor RED is not automatically the PR's
debt, and a survivor its paired suite kills must never be baselined.

**CI at the reviewed head, attempt 2:** `lint-and-selftests` ✓, `selftests (macos, bash 3.2)` ✓,
`release-pr-gates` skipped, `pr-gates` ✗ — the missing approve verdict **only**; spec, claim,
authorship and inheritance-chain arms all green. That is the expected pre-review state.

### Round-2 findings, re-checked

| # | Round-2 finding | Status |
| --- | --- | --- |
| W1 | PR body named the reconcile fixture `(Q)`; it is `(R)` | **fixed** — body now reads `(R)` |
| W2 | `audit-selftest.sh:224` cited `(N)` | **fixed** — now `(R)` |
| W3 | spec OR-1 **and AC-2's last sentence**: "falls back to today's path, so no worse off" is false for submodules and bare checkouts | **partly fixed** — see W3′ below |
| W4 | spec OR-2's latency left unmeasured | **fixed** — now carries +16–17 ms/call, ≈ +37%, with method |
| W5 | the "honest limit on the four removals" paragraph contradicted its own table | **fixed** — now scoped to three of four, `cmp-eq::1` called out as genuinely new coverage |
| W6 | PR title had no conventional prefix | **fixed** — `fix(audit-toolkit): …` |

### Warnings

| # | Severity | Where | Finding |
| --- | --- | --- | --- |
| W3′ | warning | spec AC-2, last sentence | Round-1/2 warning W3 named **two** sites: OR-1 and AC-2's trailing sentence. OR-1 was corrected; AC-2 still reads "No new failure mode for any layout: the fallback *is* the status quo" — the exact reasoning OR-1 now retracts. The two sections argue opposite things ~60 lines apart, and AC-2 is the normative one. Carried at its original severity, not escalated |
| W7 | nit | `lean-gate-selftest.sh`, `lean-reconcile-selftest.sh` (rung 2) | `tail -1` picks the **lexically** newest version dir, not the semantically newest: with `2.1.0` and `10.0.0` staged it selects `2.1.0`. Correct today (the real cache holds `2.0.0 < 2.0.1 < 2.1.0`) and inherited verbatim from `resolve_sibling_plugin_root()`, so it is a consistent pre-existing pattern rather than a new gap. Consequence when it bites is a false red (an older writer driven against a newer reader), not a vacuous pass. A follow-up should fix both copies and the precedent together |

Not findings, checked and dismissed: the ladder being duplicated across the two suites rather than
factored out — each suite must resolve its own sibling, drift between the copies breaks nothing, the
precedent carries no lockstep row either, and the comment says so; and the `for … done | tail -1`
construct under `set -uo pipefail` with no `set -e`, which is safe (the assignment is unchecked) and
is confirmed portable by the green bash-3.2 lane.

### Per-AC scoring

Scored by the letter, every AC every round, against the whole spec.

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 writer anchors on the main checkout, both common-dir forms | satisfied | inherited — `audit-tool-calls.sh` byte-identical to the tree rounds 1–2 covered; `audit-selftest.sh` green in the full sweep |
| AC-2 fallback is today's path, hook never blocks | satisfied | mechanism ships and is pinned (Tests 12/13); scored on the AC's mechanism, with its trailing generalization carried as W3′ |
| AC-3 `audit-history.sh` resolves identically, held by a `verbatim` row | satisfied | `check-lockstep-pairs.sh`: 18 pairs, 0 failed, at this head |
| AC-4 `/audit` + `QUERIES.md` + onboarding name the resolved dir | satisfied | inherited — files byte-identical |
| AC-5 `audit-selftest.sh` covers (a)(b)(c) against a throwaway repo | satisfied | green in-repo and under the install topology; only the `(N)`→`(R)` comment token changed this round |
| AC-6 the false refusal is pinned | satisfied | `(d5)` green in the repo **and now from a staged cache**, where it previously could not run at all |
| AC-7 the second reader is pinned on its DEFAULT path | satisfied | `(R)` likewise; still sets no `LEAN_AUDIT_DIR` |
| AC-8 the location contract is stated where it was false | satisfied | inherited — unchanged content |
| AC-9 the mutation registry is re-keyed in this diff | satisfied | the round-3 diff touches only `*-selftest.sh` files and spec prose, which the sweep's guard universe excludes by rule, so no ordinal moved. Re-derived `cmp-z` ordinals for `lean-reconcile.sh` at both revs: ordinal 1 is the same site at each. Local diff-scoped sweep: every survivor baselined |

AC-6 and AC-7 are the two the round-2 blocker bore on, and both are now stronger than when round 1
scored them: the pins existed then but were unreachable from any install.

### Verification performed this round

| Check | Result |
| --- | --- |
| Full selftest sweep, no `SKIP_STRESS`, `-P 4`, `env -u CLAUDE_CODE_SESSION_ID -u RUN_ID -u LEAN_RUN_MODEL` | **rc=0**, 0 failures |
| `tools/install-topology-selftest.sh` | 55 ran, 51 passed, 4 known-red, 0 stale, **0 red** |
| Staged-cache probes: sibling present / absent / pre-fix tree | pass-and-RAN / red / red — the fix resolves, and can still fail |
| Local diff-scoped `tools/mutation-sweep.sh --mode pr --base origin/main` | rc=0, 30 verdicts, survivor sets identical to CI, **no pool disagreement** |
| `shellcheck -e SC1091,SC2015,SC2181` over all `*.sh`; `jq empty` over all `*.json` | clean / clean |
| `check-lockstep-pairs.sh` / `check-frozen-files.sh` / `check-changelog-trailer.sh` | 18 pairs 0 failed / clean / trailer present |
| `cmp-z` ordinal re-derivation at `3b9c810` and `HEAD` | ordinal 1 is the same site at both — unmoved |
| Reviewer panel over the round-3 delta (6 reviewers) | 6/6 usable, **no dark reviewers**, 0 critical, 0 warnings, 1 nit (the lexical sort, = W7) |
| CI re-run on the unchanged head | `lint-and-selftests` **success**; `pr-gates` red on the missing verdict only |

The panel was re-run this round rather than inherited: round 2 inherited round 1's panel on
byte-identical content, so this delta is the only content on the branch a panel had not seen.
`scope-completeness-reviewer` re-anchored itself on `merge-base(origin/main, HEAD)` and assessed the
**whole** branch against #417 — approve, no unsatisfied scope items.

### Stated rather than implied

`bash G delta 417` **could not be run**: main's entry-gate precondition (#422) merged into this branch
on 2026-08-08, and this run's progress file carries no `entry` row because milestones 1–3 were
recorded on 2026-08-06, before that gate shipped. `entry` is a build-role write attesting the *build*
run's ledger was live, so the review session running it would forge exactly the row the authorship
split exists to protect. The range was instead re-derived by hand from the gate's own algorithm
(`inherit_candidate` → `fb21f1e0…` at `9c8f863`, then the matching commit in `base..HEAD`), and this
round then read **wider** than that range anyway. The gate derives `inherited_patch_id` itself at
`verdict` time, so the record's chain keys are unaffected.

Operational note for the build side, not a finding against this PR: the same precondition gates
`all|1..5`, so the build session will need `bash G entry 417` (idempotent, and legitimately its own
call) before it can run milestone 4.
