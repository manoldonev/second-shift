# lean review verdict — #413

verdict=needs-work
run_id: review-413-3
session_id: 39d4dc0d-90c9-4d39-869a-aa994d807d47
rounds: 3
pr: #415
reviewed_head: 847ea5466ed211e1e0193df7131b8bcac7c30204
reviewed_patch_id: 4b8fcb842c9993343d201931823584f69f800a81
inherited_patch_id: d1082fe6abd36dedb7683795d071e24af555a4b5
inherited_from_verdict: 5db7ef83ce359a67c1f71407cd4c9919e19541f3
fidelity: not-applicable
model: unknown

# Review round 3 — PR #415 (#413), verdict: needs-work

Range read: the **whole branch contribution**, `3b9c810..HEAD` (20 files), at head `847ea54`.
Rounds 1 and 2 findings were read first. Design: `not-applicable` — `design` is `null` in this
repo's runtime config, so the spec's `Design: none` disarm is justified; step 5b skipped.

**Why this round exists, and why the range is the whole branch.** Round 2 approved
`reviewed_patch_id d1082fe6abd3` at `reviewed_head 51f08a7`. The branch has since taken three
merges — `b88afe1` and `782fb17` (two independent merges of `main`, at different tips) and
`847ea54` reconciling them. That moved the branch's own patch identity to `4b8fcb842c99`, so the
round-2 record is void. This is not a clean replay: diffing the branch's contribution before
(`c3f8300..5db7ef8`) against after (`3b9c810..HEAD`), with hunk offsets normalized, the
contribution changed **content** in two places, both conflict resolutions integrating `main`'s
newly-landed entry-attestation precondition (`require_entry_attested`, #416/#422). Everything
else is context churn from `main`. A resolution round is a verification round, so this one read
the whole contribution rather than a delta.

`bash G delta 413` could not be used to derive the range: `delta` is in
`require_entry_attested`'s gated set, this run predates the attestation row, and the only
self-heal the refusal offers is `bash G entry 413` — a build-role write that would stamp this
review session's ledger and session id into the build run's progress file. The gate's own header
already anticipates this ("That mostly bites `delta`, which the review session runs"). The range
was derived by hand instead, and widened to everything. Not a defect of this PR.

## Findings

| ID | Sev | Where | Finding |
| --- | --- | --- | --- |
| B-1 | blocker | `scripts/check-lean-chain.sh:372,400-407` | The merge boundary is red on this PR, and this PR's own step 4b is why. The body-key resolver takes the **first** `closes\s+#N` anywhere in the body — code spans and narrative prose included. This PR's body documents AC-11's counterexample verbatim as ``body `Closes #392` ``, so the body key resolves to **#392** while the branch and the committed spec both say #413, and 4b hard-fails. |
| B-2 | blocker | `plugins/dev-pipeline/skills/run-lean/lean-gate-selftest.sh:257-274` | `(e5)` can no longer fail for the reason it exists. The merge re-aimed it at the entry-attestation refusal, which fires **before** milestone 1's body, so nothing inside `cmd_1` is observable from this fixture. |
| W-1 | warning | PR body | The body's claim that `pr-gates` is red "only for the expected pre-review reason" is stale — at this head it reds at 4b, a hard fail, and never reaches the verdict arm. |
| W-2 | warning | process | The round-2 approve was written at `5db7ef8`, a commit CI **never ran on** (zero check-runs). Its CI claims were carried forward from `d56d9ca`. |

### B-1 — the shipped mechanism false-reds this PR

`pr-gates` at `847ea54` (run 31265352870):

```
[lean-chain] ✗ key mismatch: the PR body resolves to #392 but the head branch
'claude/second-shift-413' resolves to #413, and the diff commits #413's lean spec
(docs/plans/second-shift-413-lean.md). check-pipeline-chain.sh exempts on that spec, so
declining here would leave this PR judged by neither gate.
```

Reproduced from this checkout, zero-network, against the branch's own gate with the real body
and the real changed-file list — `rc=1`, byte-identical message. The counterfactual isolates the
cause: neutralizing **only** the prose token (`Clos&#101;s #392`, leaving the real `Closes #413`
trailer untouched) makes the same invocation print

```
[lean-chain] applicable via lean-artifact (docs/plans/second-shift-413-lean.md): branch=claude/second-shift-413
[lean-chain] source issue: #413
```

so the gate classifies correctly and AC-6's property holds; it is the prose match, and nothing
else, that reds it.

The sibling's half of the same input set, driven with `ci.yml`'s real constants, exempts:

```
[pipeline-chain] lean-authored PR — pipeline chain check not applicable.
[pipeline-chain]   head branch: claude/second-shift-413 (key #413)
[pipeline-chain]   the diff commits this key's lean spec (…-413-lean.md); scripts/check-lean-chain.sh owns it.
```

So 4b is behaving exactly as AC-17 specifies — refusing rather than declining onto a gate that
already declined. The defect is not the refusal; it is that the input it refuses on is a phantom
key lifted out of a code span.

**Why this is the PR's debt and not incidental.** Before this PR a body/branch key disagreement
made this gate *decline* — silent, exit 0. AC-17 made it **fatal**. That converts a pre-existing
looseness in the key derivation into a merge-blocker, and it exposes a lockstep gap in exactly
the shape the PR's own manifesto section warns about: `lean-gate.sh` milestone 5 asserts
`closes\s+#$ISSUE` appears **at least once** (`-ge 1`, `lean-gate.sh:2233`), while the boundary
gate takes the **first** match (`check-lean-chain.sh:372`). Two derivations of one key. The lane
passes its own milestone 5 and then produces a PR its own boundary gate rejects — which is the
generalizable lesson this PR records ("hold the key derivation in lockstep, not only the pattern
the key feeds"), re-committed one level up.

Landing an approve verdict does **not** clear this: 4b fails before the evidence arm.

The immediate unblock is a PR-body edit, which costs no commit. Scoring it a blocker rather than
a warning is deliberate and is the one call in this record most open to push-back: the body edit
fixes this instance, but the derivation gap ships, and the next lean PR whose body legitimately
quotes a `Closes #N` — a review narrative documenting precisely this bug class, which is how this
one arose — reds the same way.

### B-2 — `(e5)` is coverage that cannot fail

Probed, not argued. `require_branch_name` injected into `cmd_1`'s body — the regression the
case's own comment names ("A refusal quoting 'cannot resolve a branch prefix' would mean the
prefix check had migrated into milestones 1-4, which is the regression this case has always
existed to catch") — and the suite returns:

```
rc=0
[lean-gate-selftest] all green
  PASS: (e5) an unresolvable prefix does not reach milestone 1 — only the entry precondition stops it
```

`(e5)` passes, and so does every other case in the ~200-case suite: the mutant is unkilled
repo-wide, not merely missed by this one case. Mutant applied via a verified non-identical write
(`cmp` against a backup), restored by `cp` from that backup.

The consequence is that the lazy-resolution placement — the design AC-1's rationale calls
load-bearing, and which the PR body defends as protecting the pinned #392 milestone-3 contract —
now has no test that can fail if someone makes it eager.

Remedy direction, **proposed but not probed by me**: seed the attestation with the prefixed
`$CFG` into `p3.md` so `entry` succeeds and the row lands, then run milestone 1 under
`CFG_NOPREFIX` against that same progress file, and assert `rc=0` plus an appended
`| milestone-1 |` record plus the absence of the prefix message. That reaches `cmd_1` and makes
its behavior observable again. Verify it the usual way — it must red under the mutant above.

## What the merge got right

Worth stating, because the merge was mostly correct and only one resolution went wrong:

- The sibling resolution in the same file is **right**: `(n0b)` gained
  `attest_at "$TREE" "$CFG_JIRA" "$WORK/p-jbranch.md" "$JKEY"`, without which milestone 1 would
  exit 2, the header would carry no `branch:` line, and the case would have failed rather than
  silently passed. It restores the case instead of hollowing it.
- No branch content was lost to the merges. Key-level comparison of the three line-oriented data
  files against both parents: `lockstep-manifest.tsv` and `mutation-slow-suites.tsv` lose nothing
  from either side; `mutation-baseline.tsv` drops exactly one key
  (`pipeline-cost-block.sh::cmp-z::1`), which the branch never touched and which `main`'s #429
  removed — the merge correctly took `main`'s deletion.
- CI is green at this exact head for everything except `pr-gates`: shellcheck, JSON, actionlint,
  the full selftest run (11m48s), `contract lockstep pairs`, and the PR-scoped mutation sweep at
  **17 seconds** against its `timeout-minutes: 15` bound.

## Reviewer panel

| Reviewer | Verdict | Findings |
| --- | --- | --- |
| Security | Pass | 0; 3 suppressed. One (conf 55, `check-lean-chain.sh:372`) independently names B-1's mechanism — "'Closes #N' is grepped anywhere in the PR body (code spans/prose included), so classification can be steered by quoted text" — and correctly triages it as *non-security* ("effect bounded to gate ownership"). It did not check whether it fires on this PR; it does. |
| Performance | Pass | 0 — no performance surface in a shell/CI diff. |
| Complexity | Pass | 0 — reads the change as a net reduction in configuration surface. |
| Maintainability | Pass | 0 |
| Scope completeness | **Fail** (conf 95) | The staged lane (`stages/2-worktree.md:27,31`) still spells `.tracker.branchPrefix // "claude/acme-"` and never calls the shared resolver — scored against AC-3, AC-5 and proposal 2. **Overridden, as in rounds 1 and 2.** Pre-flight ledger `D-1` is `user-answered`, pre-implementation, and says in terms: the staged lane's prose "is left untouched" and "AC-5 narrows to 'one implementation among live consumers'". The ledger is a binding input the scope gate cannot see. Recorded as a note, not a blocker — and escalating a round-1 note to a round-3 blocker would be its own error. The divergence between the tracked scope and the shipped scope is real and still unfiled; the PR body flags it. |
| Test coverage | **Dark (no output)** | `turn-budget: agent emitted no text on either attempt (maxTurns cap reached mid-exploration)`. Third consecutive round dark on this PR. |
| Unit-test mutation | **Dark (no output)** | Same error, same shape. In round 2 this reviewer carried the test dimension after test-coverage died; this round **both** are dark, so the entire test-integrity dimension went unreviewed by the panel. B-2 is the in-session substitute, not panel-corroborated. |

Both deaths are the tracked emit-deadline shape (the harness's own diagnosis: "needs an emit
deadline, not a bigger cap"), not a signal about this diff.

`a11y-reviewer` and the design-fidelity dimension were **not routed**: no changed path matches
`stageParams.webComponentGlobs` (unset, so the shipped default `apps/web/**/*.{tsx,jsx}`). Not a
coverage gap — this diff has no web-component surface. `db-reviewer` and `pipeline-reviewer` were
not selected (no DB layer, no queue/worker files).

The two blockers in this record are both in-session findings, each established by execution
rather than by reading. That is the honest characterization of this round: the panel found
nothing new, and the reviewer whose domain would most likely have found B-2 went dark.

## Per-AC scoring (18 ACs, at `847ea54`)

Scored by the letter of what each AC requires the implementation to do. Both blockers above are
genuine defects that no AC's text covers — B-1 because AC-17 does not constrain the body-key
derivation, B-2 because AC-14 enumerates the resolver, scenario-liveness and the two chain-gate
suites but not `lean-gate-selftest.sh`. Reporting them as blockers outside the AC table is the
same posture rounds 1 and 2 took with AC-11 and AC-17.

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | `lean_branch_prefix` absent from both consumers; `(e1)`/`(e2)`/`(e3)` pin prefix-verbatim, `<branchPrefix><key>`, and no `lean/` anywhere in the header. |
| AC-2 | satisfied | `(n0b)` asserts branch `abc/acme-7` with the artifact path keeping `ACME-7` verbatim. |
| AC-3 | satisfied | `branch-prefix-selftest.sh` detection cases; configured value wins. |
| AC-4 | satisfied | zero-candidate and tie refusals both driven, naming what was considered. |
| AC-5 | satisfied | one resolver, two callers — `lean-gate.sh:281`, `retro-corpus.sh:197`. |
| AC-6 | satisfied | `LEAN_BRANCH_PREFIX` absent from `ci.yml`; residual mentions are the deletion narrative (which AC-13 requires) and a case that drives a stale export to prove it is ignored. Property confirmed live by the B-1 counterfactual. The PR body's claim that it classified *this* PR that way is stale — see W-1. |
| AC-7 | satisfied | sibling reports not-applicable; staged-PR verdict unchanged. |
| AC-8 | satisfied | `lean-spec-suffix` row at `lockstep-manifest.tsv:274`; `check-lockstep-pairs.sh` 18/0 locally and in CI. |
| AC-9 | satisfied | legacy `lean/`-prefixed heads still classify via the artifact arm. |
| AC-10 | satisfied | key-matched exemption; different-key spec stays gated. |
| AC-11 | satisfied | key-matched applicability on both sides; unresolvable-reference case still fails. |
| AC-12 | satisfied | OR-1 driven through both real gates. |
| AC-13 | satisfied | `run-lean/SKILL.md` 42 lines (cap 60), no "lean prefix" in step 3; `pipeline-retro` recipe uses `$BRANCH`; manifesto section rewritten. |
| AC-14 | satisfied | by its letter — the resolver's suite, the scenario leg decision, and both chain-gate suites. B-2 is in `lean-gate-selftest.sh`, which this AC does not enumerate. |
| AC-15 | satisfied | CI at this head: shellcheck, JSON, actionlint, full selftest run all green; locally shellcheck rc=0, `jq empty` rc=0, lockstep 18/0. |
| AC-16 | satisfied | CI at this head: `mutation sweep (PR-scoped)` 17s against `timeout-minutes: 15`. |
| AC-17 | satisfied | the mechanism ships, is scoped by `(D3b)`, and demonstrably fires — see B-1 for the false-positive its key source produces. |
| AC-18 | satisfied | bare invocation anchors on the main checkout; `(k2)`/`(k2b)` drive it from a real worktree. |
