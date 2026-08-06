# lean review verdict — #403

verdict=approve
run_id: review-403-1
session_id: 1b569a66-dcd0-440c-8431-eddc66d43d1b
rounds: 1
pr: #406
reviewed_head: 7172c5b51fe1218b540e38866002cb33624e601a
reviewed_patch_id: dab24252c4e9f7ce6e32b7c89712883c567564bc
inherited_patch_id: none
inherited_from_verdict: none
model: unknown

# Review round 1 — PR #406 / issue #403

Range read: `ab12060..HEAD` — the full branch diff (`bash G delta 403` printed FULL: nothing
verifiable to inherit, so this is a chain root). Three files: `scripts/check-lean-chain.sh`,
`scripts/check-lean-chain-selftest.sh`, `docs/plans/second-shift-403-lean.md`. Read wider than
the range where the delta was misleading: `plugins/dev-pipeline/skills/run-lean/lean-gate.sh`
(milestone 4, the sibling reader of the same record), `lean-reconcile.sh`, `run-lean/SKILL.md`,
`.github/workflows/ci.yml`, `scripts/lockstep-manifest.tsv`, `tools/mutation-operators.tsv`.

Reviewer: `review-lead` panel of 6 via `code-review.mjs` (0 dark) + operator-run execution
probes. Not routed: `db-reviewer` / `pipeline-reviewer` (no DB or queue surface);
`a11y-reviewer` + the design-fidelity dimension (no changed path matched
`stageParams.webComponentGlobs`, resolved to the default `apps/web/**/*.{tsx,jsx}`);
`unit-test-mutation-reviewer` (no co-located unit spec — this repo's tests are shell selftests).

## Verdict: approve

All four `AC-n` satisfied, each verified by execution here rather than taken from the PR body.
No blockers. Three warnings, none of which the AC set covers and none of which reaches the gate
this PR is about.

## Per-AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | `(W2)` drives a **real** `git merge` from an `origin/main` advanced by two unrelated commits, and requires all three of rc=0, `freshness (inferred): skipped`, `freshness (declared, patch-id`, plus the absence of `changed between that commit and the PR head`. Non-vacuity is pinned separately by `(W1)`: the merge really did land files after the record's commit, so an unguarded inferred arm has something to wrongly fire on. |
| AC-2 | satisfied | `(W3)` re-runs the same merge shape against a record written by the 3-arg `write_verdict` (no `reviewed_patch_id` — the default, asserted rather than assumed by the pre-existing `(R5)`), and requires rc=1 **with** the inferred arm's own message. |
| AC-3 | satisfied | Both record shapes. Patch-id shape: `(W4)` lands a genuine branch-side commit after the record and requires rc=1 via `now hashes to` — the declared arm's message, so the kill is attributable to the arm that survived the skip; `(W5)` shows a fresh round clears it, so the check has a remedy. No-patch-id shape: the pre-existing `(O1)` (`a verdict that predates a later code commit is refused at the merge boundary`), which `(R5)` pins as gating on the SHA fallback. |
| AC-4 | satisfied | Reproduced independently, not read from the PR body. Reverted the precedence branch write-through (`scripts/check-lean-chain.sh:503` → `if false; then`, `cat` not `mv`, exec bit verified 0755 before and after) and ran the suite: **1 FAILURE**, sole failure `(W2)`, every other case including `(W1)`/`(W3)`/`(W4)`/`(W5)` still green. Restored write-through from a pristine copy; `shasum` matches and `git status` is empty. |

## Findings

| # | Class | Where | Finding |
| --- | --- | --- | --- |
| W1 | warning | `scripts/check-lean-chain.sh:503` | The diff removes the merge boundary's only assertion that the verdict record is **committed**, for records carrying `reviewed_patch_id`. `VERDICT` is discovered by `find` over the working tree (line 337), not from git, so an untracked record is found; the empty-`VERDICT_COMMIT` refusal (`present in the tree but carries no commit`) was the sole check that git had ever seen it, and it now sits inside the skipped branch. The declared arm cannot cover it: both sides of its `git diff` are commits, so an untracked record is excluded from each and its patch-id matches — the chain reports a clean pass on a record that was never committed. The gate's own header, unchanged by this diff, still promises "the record must be COMMITTED". `lean-reconcile.sh` degrades the same state to a `note:`, not a refusal, so nothing else refuses it either. **Not a blocker**: unreachable at the only place this script is a gate — `actions/checkout@v5` with `fetch-depth: 0` produces a tree that *is* the commit — and the branch was already untested before this diff, so no coverage regressed. Remedy is one hoist: resolve `VERDICT_COMMIT` and refuse on empty **above** the precedence branch, and skip only the two-dot `STALE` computation. |
| W2 | warning | `plugins/dev-pipeline/skills/run-lean/lean-gate.sh:1199` | The sibling reader keeps the identical defect. Milestone 4 runs `git diff --name-only "$v_commit" HEAD` unconditionally and `fail_milestone 4`s on a non-empty result, returning before the patch-id arm at line 1224 is ever reached — so the same "Update branch" merge this PR makes benign at the merge boundary still reds milestone 4 in a build session. `run-lean/SKILL.md` mandates `bash G all` before step 9 and states "the verdict is bound to the branch's patch", a promise now honored by one reader and not the other; the two files' headers contradict outright (`check-lean-chain.sh`: the declared arm "SUBSUMES" the inferred one — `lean-gate.sh`: "TWO ARMS, and neither subsumes the other"). **Not a blocker**: outside the spec's scope, no AC covers it, the binding gate is the merge boundary and it is fixed, and the lane already documents rebase as the in-session remedy for a moved base — so the residual is a confusing local red, not a blocked merge. Worth its own issue. |
| W3 | warning | `docs/plans/second-shift-403-lean.md:36` | AC-4's evidence tier was downgraded from the issue's without a recorded rationale. Issue #403: "**AC-4** (oracle — selftest): each AC above is a case, and the AC-1 case reds the suite when the fix is reverted." Spec: "**AC-4** (verified manually, not a permanent selftest case)". **Cleared, and the clearance is recorded here because silence on this rule reads as an oversight**: the dropped clause is satisfied anyway (AC-1→`(W2)`, AC-2→`(W3)`, AC-3→`(W4)`); a revert probe cannot be a permanent selftest case, so the issue's own tier label was unsatisfiable by any implementation; and the spec commit `58f2ede` precedes the implementation commit `7172c5b`, making this milestone-1 authoring rather than a post-hoc amendment to match the diff. The substance is satisfied regardless — see AC-4 above. Neither the spec nor the PR body notes the change, which is the part worth fixing. |
| N1 | nit | `scripts/check-lean-chain-selftest.sh` (W) block | The `(W)` block leaves the fixture repo with `refs/remotes/origin/main` advanced three commits and two extra branches (`w-base`, `w-base2`) live. Harmless today — `(W)` is last in the file, and it carries a careful note about what came *before* it — but nothing warns the next author appending a case after it. |

## Claims in the PR body, checked rather than taken

- **Mutation ordinals stable, no re-baseline.** Verified by enumerating each operator's matched-line
  list on `origin/main` and on `HEAD`. `cmp-z` (`-z |-n `) goes 46 → 47 sites: the new site is the
  precedence `if` at line 503, which lands at **ordinal 31**. `K_BUDGET=2`, so only ordinals 1–2 are
  ever mutated, and both are unmoved (the line-13 comment, and the `--help` `sed` line). `cmp-eq`,
  `default`, `logic` and `fail-open` are byte-identical in count and leading entries. The five
  baselined rows for this file (`cmp-eq::1/2`, `cmp-z::1`, `default::1/2`) are correctly untouched.
- **`--help` range.** `sed -n '2,121p'` now ends exactly on line 121 (`# Exit 0 = pass or …`),
  stopping before `set -uo pipefail` at 122. Pinned by the suite's existing help case, which
  asserts both presence and the stop.
- **`shellcheck -e SC1091,SC2015,SC2181`** on both touched scripts: clean.
- **`check-lockstep-pairs.sh`**: 16/16, 0 failed. No row pins the freshness prose between the two
  readers, which is why W2 cannot red any lane.
- **Full sweep**, `env -u CLAUDE_CODE_SESSION_ID`, no `SKIP_STRESS`, `-P 4`: rc=0, 933 PASS, zero
  failures.

## Reviewer panel

| Reviewer | Verdict | Findings | Confidence |
| --- | --- | --- | --- |
| Scope Completeness | Pass | 0 | — |
| Security | Pass | 0 | — |
| Performance | Pass | 0 | — |
| Complexity | Pass | 0 | — |
| Maintainability | Pass | 0 | — |
| Test Coverage | Pass | 0 | — |

Two suppressed items below the confidence threshold, both corroborating findings reached
independently here: `security-reviewer` at 45 on the lost committed-ness check (W1) and
`scope-completeness-reviewer` at 75 on the AC-4 wording (W3). W2 was reached by the
cross-reviewer self-check — no reviewer had `lean-gate.sh` in its diff scope.
