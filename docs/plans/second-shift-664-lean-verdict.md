# lean review verdict — #664

verdict=approve
run_id: review-664-2
session_id: a7a8a674-e42a-4104-aa12-14424357f924
rounds: 2
pr: #706
reviewed_head: ee8bfe563518ac4eafaac2e7f16f9fbe781df19d
reviewed_patch_id: a01b642299c70d1b3f305a7eca8c782eaf2771f0
inherited_patch_id: 1d9bf997367b96f497faf01f1769b8c58ae08436
inherited_from_verdict: 992684e9a7c8d5ed2f2a0ca23bf89ea641166ee9
fidelity: not-applicable
model: unknown
capabilities: pr-marker

# review-lean #664 / PR #706 — round 2

**Verdict: approve.** No blockers. Range read: `992684e..HEAD` (ee8bfe5) — the round-1 fix
commit, inheriting the coverage of patch `1d9bf997367b`. Round 1's findings were read first;
all four are closed or accounted for below. All eight ACs scored.

## Round-1 disposition

| r1 # | Status | Evidence |
| --- | --- | --- |
| B1 `(inv-cache)` vacuous for its own defect | **closed, re-derived** | `PLUGINS_ROOT` joins the save/re-point/restore block (`:846,849,876`). Restoring the pre-fix line `base="$PLUGINS_ROOT/$plug/$rel"` now gives **43 passed, 1 failed**, and the red is the nightly message verbatim. See AC-3. |
| W1 `guard-budget` red | **closed** | CI at ee8bfe5: `[guard-budget] ✓ … base 53291, HEAD 53670 (delta +379), covered by a 'Guard-mass:' trailer.` |
| W2 duplicate `(inv/sibling)` case id | **closed** | `:703` now emits `(inv/sibling-resolver)`. Zero remaining collisions: `(inv/sibling)` is produced only by the live arm loop's `(inv/$_arm)`. |
| W3 fencepost survivors on the signal range | **closed** | 129 and 164 added to the signal loop; a new `(t6-fence)` loop pins 128 and 165. Four mutants measured dead — see AC-6. |
| W4 stale PR-body mutant numbers | **partly closed, see N1** | The body was rewritten with a measured table; one row is still wrong. |

## Findings

| # | Sev | Where | Finding |
| --- | --- | --- | --- |
| N1 | warning | PR body, "Guards" table, row 3 | The pre-fix loose-sweep revert is claimed as `14 passed, **6 failed** — (t1), (t2/FAIL), (t2/FATAL), (t2/RED), (t2/ERROR), **(t5)**`. Measured here: **15 passed, 5 failed**; `(t5)` stays **green**. Non-blocking — no AC depends on the body — but it is r1's B1 class recurring: an asserted mutant result nothing re-derived. |
| N2 | nit | `tools/install-topology-selftest.sh:262` | The signal range's ceiling `"$rc" -lt 165` covers signals 1–36. On Linux, real-time signals run to 64 (`rc` up to 192), so an RT-signal kill still falls through to the quoting branch and reproduces the exact #664 symptom. Every realistic reaper (SIGINT/SIGTERM/SIGKILL) is inside the range, so this is an observation, not a defect — raised only because `(t6-fence/165)` now pins 165 as a deliberate boundary. |

### N1 — the revert was byte-identical to base, and `(t5)` survives it

The mutant line injected at `:279-281` was verified equal to base's own pre-fix line by digest,
not by eye:

```
git show $(git merge-base origin/main ee8bfe5):tools/install-topology-selftest.sh \
  | grep 'detail="rc=' | md5   → edb97a094e6fd673b9c41e92944566de
the injected line                → edb97a094e6fd673b9c41e92944566de
```

```
[install-topology-detail-selftest] 15 passed, 5 failed
  FAIL: (t1) …  FAIL: (t2/FAIL) …  FAIL: (t2/FATAL) …  FAIL: (t2/RED) …  FAIL: (t2/ERROR)
```

`(t5)` cannot red under it, because the pre-fix composition **also** ended in
`sed 's/^[[:space:]]*//'` — the indent-stripping `(t5)` asserts was never the thing this fix
changed. `(t5)` is not an unguarded line: dropping the `sed` from the marker-first branch at
`:279` reds it (`19 passed, 1 failed`, `got:[rc=1 —       FAIL: indented deeply]`). So the
coverage is real and the table row is not. Fix the row in the body; nothing in the tree changes.

## AC scoring

| AC | Verdict | Evidence |
| --- | --- | --- |
| AC-1 root cause named, `(inv/sibling)`, rung-1-vs-`resolve_sibling` | satisfied | `docs/plans/second-shift-664-lean.md` §Root cause. Unchanged in this delta; inherited from round 1 and re-read. |
| AC-2 `install-topology-selftest.sh` passes locally, doctor suite among the passes, 0 red | satisfied | **Re-measured here at ee8bfe5**, not cited: `[install-topology] summary: 53 ran, 53 passed, 3 skipped, 0 red`, `RC=0`, with `  pass:  plugins/dev-pipeline/tools/pipeline-doctor-selftest.sh` in the log. All 3 skips carry a suite-declared reason. No CI lane runs this suite on the PR lane (nightly since #620), so there was nothing to cite. |
| AC-3 in-repo case that **fails under the pre-fix code** | **satisfied** (was the r1 blocker) | Pre-fix join restored in an isolated worktree of this clone at ee8bfe5 → `[pipeline-doctor-selftest] 43 passed, 1 failed`; the red is `FAIL: (inv-cache) under a version-keyed install cache the arm cannot find: …ledger-lint-selftest.sh …check-model-tiers-selftest.sh …check-reviewer-references-selftest.sh` — the nightly message verbatim. Fix in place → `44 passed, 0 failed`. The control `(inv-cache-control)` is present and green. The re-point window does not leak: `PLUGINS_ROOT` occurs at `:687,694,846,849,876` only, `694` precedes the window, nothing after `876` reads it, and the file runs `set -uo pipefail` with no `-e`, so no path strands the re-point. |
| AC-4 fix resolves through the **executed** production ladder | satisfied | `:700-717` lifts `resolve-sibling.sh`'s `# >>> resolve-sibling` block by sed and executes it with the doctor's `PLUGIN_DIR`/`PLUGINS_DIR`. Live, measured: renaming the sentinels → `42 passed, 3 failed`, `FAIL: (inv/sibling-resolver) resolve-sibling sentinels not found …`. |
| AC-5 `detail` names the suite's own failure line; signal arm | satisfied | `tools/install-topology-selftest.sh:275-281` marker-first + loose fallback, `:262-268` signal arm. Verified behaviorally by AC-6's mutants, not by reading. |
| AC-6 AC-5's path guarded by an executing test, all four arms | satisfied | `tools/install-topology-detail-selftest.sh` — `20 passed, 0 failed` at ee8bfe5. Five independent mutants, each applied alone in an isolated worktree of this clone and scored by case id: pre-fix loose sweep → 5 red (N1); delete the signal arm → 5 red `(t6/129,130,137,143,164)`; `-gt 128`→`-ge 128` → `(t6-fence/128)` red ("killed by signal 0"); `-lt 165`→`-le 165` → `(t6-fence/165)` red ("signal 37"); narrow to `-gt 129 && -lt 164` → `(t6/129)` and `(t6/164)` red. The fence arms are not vacuous: for rc=128/165 the fallback grep matches "fail**s**" in the fixture, so `detail` composes non-empty and the `"rc=$n — "*` glob is satisfied only by an actual fall-through. |
| AC-7 `docs/testing.md` install-topology section corrected | satisfied | `:598-618`. Unchanged in this delta; inherited from round 1. |
| AC-8 `Changelog:` trailer | satisfied | CI at ee8bfe5, `pr-gates` step 2: `[changelog-trailer] OK — a 'Changelog:' trailer is present.` |

## CI at the reviewed head (ee8bfe5)

| Job | Result | Reading |
| --- | --- | --- |
| `lint-and-selftests` | pass (4m28s) | Cited, not re-run — same head, same command. |
| `selftests (macos, bash 3.2)` | pass (5m54s) | Same. Both touched suites are discovered by the glob and green under bash 3.2. |
| `mutation-sweep-pr` | pass (10s) | No `mutation-catalog.tsv` row exists for either touched suite, so nothing was graded here — it is not evidence either way. |
| `pr-gates` | fail | frozen-files ✓, changelog-trailer ✓, **guard-budget ✓ (+379, covered)**, pipeline-chain n/a → **lean-chain ✗ only**: `verdict record … reads 'verdict=needs-work', not 'verdict=approve'`. That is the round-1 record, and it is the expected state of a lean PR before this round's approval. Not a finding. |

## Design fidelity

`not-applicable` — the spec carries no `## Design` section and declares no `RS-n` rows.

## What was executed here

From `second-shift-worktrees/664` @ ee8bfe5 (clean, `== origin`) and two detached worktrees of
the same clone at the same commit (never `/tmp`):

- `bash tools/install-topology-selftest.sh` → `53 ran, 53 passed, 3 skipped, 0 red`
- `bash plugins/dev-pipeline/tools/pipeline-doctor-selftest.sh` → `44 passed, 0 failed`
- `bash tools/install-topology-detail-selftest.sh` → `20 passed, 0 failed`
- seven mutants, each applied alone and reverted, scored by case id (AC-3, AC-4, AC-6, N1)
- `shellcheck -e SC1091,SC2015,SC2181` on all three touched shell files → clean
- one `test-coverage-reviewer` dispatch over the delta: **no findings**, and its leak/vacuity
  traces agree with the greps above.
