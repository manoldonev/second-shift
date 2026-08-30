# lean review verdict — #664

verdict=needs-work
run_id: review-664-1
session_id: 7c09891a-9650-485c-9220-b70b1051f48e
rounds: 1
pr: #706
reviewed_head: 11fcdab62a3315a3af74da238df7e83d06b39661
reviewed_patch_id: 1d9bf997367b96f497faf01f1769b8c58ae08436
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown
capabilities: pr-marker

# review-lean #664 / PR #706 — round 1

**Verdict: needs-work.** One blocker. Range read: `808aa29..HEAD` (11fcdab) — the full branch
diff (round 1, nothing to inherit). All eight ACs scored below.

## Findings

| # | Sev | Where | Finding |
| --- | --- | --- | --- |
| B1 | blocker | `plugins/dev-pipeline/tools/pipeline-doctor-selftest.sh:838-852` | `(inv-cache)` is **vacuous for the defect it names**: restoring the pre-fix line `base="$PLUGINS_ROOT/$plug/$rel"` leaves the suite at **44 passed, 0 failed**. AC-3 is unsatisfied and the PR body's mutant claim is false. |
| W1 | warning | `tools/install-topology-selftest.sh` (CI `pr-gates`) | `check-guard-budget.sh` red: +351 guard lines, no `Guard-mass:` trailer. Recorded, not a blocker (merge-boundary policy). |
| W2 | warning | `plugins/dev-pipeline/tools/pipeline-doctor-selftest.sh:703` | The sentinels-missing arm reuses the case id `(inv/sibling)`, which the live arm loop also emits, so a log can carry two different `(inv/sibling)` verdicts. |
| W3 | warning | `tools/install-topology-detail-selftest.sh:183,198` | The signal range `rc -gt 128 && rc -lt 165` is exercised only at interior points (130/137/143) and controlled only at rc=1. A fencepost mutant on either comparison survives. Add `rc=128` and `rc=165` (must fall through to the ordinary-failure branch) and `rc=129`/`rc=164` (must be named as signal deaths). |
| W4 | warning | PR body, "Guards" table and "Verification" | "5 of 10 cases red" / "16 passed" — the revert now reds **8 of 16**. Stale after the second commit added the signal arm. Cosmetic (PR body is not a committed artifact). |

### B1 — `(inv-cache)` cannot fail under the code it was written to catch

AC-3 requires a case that "runs in the ordinary in-repo sweep and **fails under the pre-fix
code** … where the pre-fix path join structurally cannot resolve." Measured at 11fcdab in an
isolated worktree (`second-shift-worktrees/probe-664`, same clone, not `/tmp`), reverting **only**
the one changed line in `inv_scan`:

```diff
       sibling) plug="${hit%% *}"; rel="${hit#* }"; hit="$plug/$rel"
-               base="$(inv_sibling_path "$plug" "$rel")" ;;
+               base="$PLUGINS_ROOT/$plug/$rel" ;;
```

```
[pipeline-doctor-selftest] 44 passed, 0 failed
  ok: (inv-cache) all 3 sibling delegation(s) resolve from a version-keyed install cache, …
  ok: (inv-cache-control) a delegation staged nowhere is still reported missing …
```

**Why.** The case fabricates the cache by re-pointing `INV_PLUGIN_DIR` / `INV_PLUGINS_DIR`
(`:840-843`) — two globals **introduced by this PR**, read only by `inv_sibling_path`. The line
the defect lived on reads `PLUGINS_ROOT`, which the case never re-points, so the pre-fix join
resolves against the real monorepo tree, every sibling exists, and the case passes. The
fabrication is invisible to exactly the code path it claims to bound.

`(inv-cache-control)` does not catch this either: the injected absent delegation is absent under
*both* layouts, so it passes for the pre-fix arm too.

**What `(inv-cache)` does cover today.** Deleting rung 3 from `resolve-sibling.sh` reds it — but
that mutant already reds the pre-existing `(rs3-gate)` and `(rs3-doctor)`. So the case's *unique*
contribution over what the file already had is precisely the one claim it cannot make.

**Verified patch** (3 added lines, in `pipeline-doctor-selftest.sh`):

```diff
 INV_SAVED_PLUGIN_DIR="$INV_PLUGIN_DIR"
 INV_SAVED_PLUGINS_DIR="$INV_PLUGINS_DIR"
+INV_SAVED_PLUGINS_ROOT="$PLUGINS_ROOT"
 INV_PLUGIN_DIR="$INV_CACHE/dev-pipeline/$INV_MYVER"
 INV_PLUGINS_DIR="$INV_CACHE/dev-pipeline"
+PLUGINS_ROOT="$INV_CACHE/dev-pipeline"
@@
 INV_PLUGIN_DIR="$INV_SAVED_PLUGIN_DIR"
 INV_PLUGINS_DIR="$INV_SAVED_PLUGINS_DIR"
+PLUGINS_ROOT="$INV_SAVED_PLUGINS_ROOT"
```

Measured with the patch applied:

- pre-fix arm restored → `43 passed, 1 failed`, and the red is the nightly message verbatim:
  `FAIL: (inv-cache) under a version-keyed install cache the arm cannot find: …ledger-lint-selftest.sh …check-model-tiers-selftest.sh …check-reviewer-references-selftest.sh`
- fix in place → `44 passed, 0 failed`. No false red.

The point of AC-3 is that the fabricated environment, not the resolver's own new variables, is
what decides the arm's answer. Re-pointing `PLUGINS_ROOT` is what makes the cache the only place
those files exist. Consider re-pointing `DOCTOR_DIR` / `OWN_PLUGIN_DIR` in the same save/restore
block so a future arm that reaches for a doctor-relative join is bounded too.

**Re-run the mutant before re-submitting** — an asserted mutant result nothing re-derives is how
this one shipped.

## AC scoring

| AC | Verdict | Evidence |
| --- | --- | --- |
| AC-1 root cause named, `(inv/sibling)`, rung-1-vs-`resolve_sibling` | satisfied | `docs/plans/second-shift-664-lean.md` §Root cause: names the case, both layouts, and the ladder. |
| AC-2 `install-topology-selftest.sh` passes locally, 0 red | satisfied | Run here at 11fcdab: `[install-topology] summary: 53 ran, 53 passed, 3 skipped, 0 red`, with `plugins/dev-pipeline/tools/pipeline-doctor-selftest.sh` among the passes. All 3 skips are suite-declared (rc 77) and carry their reason. |
| AC-3 in-repo case that **fails under the pre-fix code** | **unsatisfied** | B1: the pre-fix line leaves the suite `44 passed, 0 failed`. |
| AC-4 fix resolves through the **executed** production ladder | satisfied | `:700-717` lifts `resolve-sibling.sh`'s `# >>> resolve-sibling` block by sed and runs it as a stub with the doctor's `PLUGIN_DIR`/`PLUGINS_DIR`; no hand-copied predicate. Rung-3 deletion reds it, so the stub is live. |
| AC-5 `detail` names the suite's own failure line; signal arm | satisfied | `tools/install-topology-selftest.sh:279-281` marker-first + loose fallback; `:266-274` signal arm. Verified behaviorally (below). |
| AC-6 AC-5's path guarded by an executing test, all four arms | satisfied | `# >>> red-detail` wraps the whole dispatch; `tools/install-topology-detail-selftest.sh` eval-executes it against fixture logs. 16/16 green here (bash 5 **and** bash 3.2) and in CI. Reverting the composition to the pre-fix `grep … \| head -1` reds **8 of 16**: `(t1)`, `(t2/FAIL)`, `(t2/FATAL)`, `(t2/RED)`, `(t2/ERROR)`, `(t6/130)`, `(t6/137)`, `(t6/143)`. Decoy log and PASS-carrying infra fixture both present; `(t6-control)` proves the signal range does not swallow rc=1. |
| AC-7 `docs/testing.md` install-topology section corrected | satisfied | `:598-618` bounds the standing `:590` claim explicitly — detection held, PR-lane timing and diagnosability did not. |
| AC-8 `Changelog:` trailer | satisfied | Both fix commits carry one; CI `pr-gates` step 4 "changelog trailer guard" = success. |

## CI at the reviewed head (11fcdab)

| Job | Result | Reading |
| --- | --- | --- |
| `lint-and-selftests` | pass (4m36s) | Cited, not re-run — same head, same command. `[install-topology-detail-selftest] 16 passed, 0 failed` in its log, so the new suite is discovered by the glob. |
| `selftests (macos, bash 3.2)` | pass (5m34s) | Same. |
| `mutation-sweep-pr` | pass (15s) | No `mutation-catalog.tsv` row exists for either touched suite, so nothing was deferred or graded here. |
| `pr-gates` | **fail** | Step 3 frozen-files ✓, step 4 changelog-trailer ✓, step 5 `guard-budget` ✗ (+351, no `Guard-mass:`), steps 6–7 skipped by `-e`. Policy, not code — W1. |

## Design fidelity

`not-applicable` — the spec carries no `## Design` section and declares no `RS-n` rows.

## What was executed here

From the reviewed checkout (`second-shift-worktrees/664` @ 11fcdab, clean, `== origin`):
`pipeline-doctor-selftest.sh` 44/0 · `install-topology-detail-selftest.sh` 16/0 · both again
under `/bin/bash` 3.2.57 · `shellcheck -e SC1091,SC2015,SC2181` clean on all three shell files ·
`install-topology-selftest.sh` 53 ran / 53 passed / 3 skipped / 0 red. Mutants M1/M2/M3 and the B1 patch in a detached
probe worktree of the same clone.
