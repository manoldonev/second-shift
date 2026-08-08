# lean review verdict — #413

verdict=approve
run_id: review-413-4
session_id: d8cb1ace-f4a6-44eb-99cc-a302b4054cdb
rounds: 4
pr: #415
reviewed_head: 43b8428d507b5621779e5a5fc6155cfed56038e6
reviewed_patch_id: 8915d6c32621e3f299bb0ce96fe6771145ff91ba
inherited_patch_id: 4b8fcb842c9993343d201931823584f69f800a81
inherited_from_verdict: d7de9261674761429a118ce596d27f93c00eead6
fidelity: not-applicable
model: unknown

# Review round 4 — PR #415 (#413), verdict: approve

Range read: the delta since round 3's reviewed tree `4b8fcb842c99` — commit `43b8428`, 5 files,
+133/−23. Rounds 1–3 findings were read first. Design: `not-applicable` — `design` is `null` in
this repo's runtime config, so the spec's `Design: none` disarm is justified; step 5b skipped.

**Why the range is a delta, and why the merge in it is not a re-verification round.** Round 3
reviewed `4b8fcb842c99` at head `847ea54` and returned `needs-work`. The branch has since taken
its round-3 verdict record (`d7de926`), one merge of `main` (`c2995ee`), and the fix (`43b8428`).
The merge is a **clean replay**: diffing the branch's contribution before
(`3b9c810..d7de926`) against after (`a7f069a..c2995ee`), with hunk offsets normalized and `index`
lines dropped, gives **zero** differing content lines. No conflict was resolved, so unlike round 3
this is not a resolution round and the delta is exactly the fix commit.

`bash G delta 413` is still unusable here: `delta` sits in `require_entry_attested`'s gated set,
this run predates the attestation row, and the only self-heal offered is `bash G entry 413` — a
build-role write. The range was derived by hand, as in round 3. Not a defect of this PR.

**Both round-3 blockers are fixed, and both fixes were established by execution, not by reading.**

- **B-1 closed.** Driven from this checkout, zero-network, against the branch's own gate with the
  PR's *real* body and *real* 20-file list: `applicable via lean-artifact
  (docs/plans/second-shift-413-lean.md)`, `source issue: #413`, and the only red is the verdict arm
  (`reads 'verdict=needs-work'`) — the expected pre-review shape. Counterfactual isolates the cause:
  neutralizing only the branch-key preference (`if false && …`) restores the round-3 hard fail
  byte-for-byte (`the PR body resolves to #392 …`). The body still carries the quoted token; the
  gate no longer cares.
- **B-2 closed.** `require_branch_name` injected into `cmd_1`'s body — the exact regression `(e5)`'s
  comment names — and `(e5)` is the **only** red across the suite (206 pass / 1 fail). Restored by
  `cp` from a backup, `cmp`-verified non-identical before the run. Round 3's probe had this mutant
  unkilled repo-wide; it now dies in one case.

Both of the spec's own probe claims for the new cases reproduce exactly: with the preference
disabled `(D3c)` is the only red in 73 cases; with it made unconditional (membership test dropped)
`(D3)` and `(D3d)` are the two reds.

## Findings

No blockers. Four warnings and two suggestions; none of them fires on this PR, and none is
lane-reachable. Each was established by driving the real gates from this checkout.

| ID | Sev | Where | Finding |
| --- | --- | --- | --- |
| W-1 | warning | `scripts/check-lean-chain.sh:395-407` | The fix **creates** a new both-exempt cell. A branch outside the pipeline prefix but carrying trailing digits, whose body closes both that number and another key, and whose diff commits the *other* key's lean spec, is now silent on both sides. Pre-fix the same input was applicable here. |
| W-2 | warning | `scripts/check-lean-chain.sh:398-408` | The "agree by construction" guarantee holds **within** the closes pattern only. A body whose reference to the branch key is `Part of #<branch key>` while prose quotes some other closing keyword still resolves the phantom key and reproduces B-1's hard fail across the closes/part-of boundary. |
| W-3 | warning | `scripts/check-pipeline-chain.sh:175,187` | AC-19's headline says "**the two chain gates** derive the issue key in lockstep". The sibling still resolves by first match and hard-fails on any mismatch, so the two gates' derivations now **diverge** where before the fix they were identical. Pre-existing behavior, newly asymmetric. |
| W-4 | warning | `scripts/check-lean-chain.sh:402` | The `-x` in `grep -qxF` is what makes the membership test exact rather than substring, and dropping it survives the whole 73-case suite. New code, unpinned. |
| S-1 | suggestion | `scripts/check-lean-chain.sh:122-126`, `docs/pipeline-manifesto.md:173` | The gate's `--help`-printed input contract still says `PR_HEAD_REF` is "read for classification ONLY at step 4b"; it is now read at step 4 and decides which key the whole applicability arm uses. |
| S-2 | suggestion | `docs/pipeline-manifesto.md:189-196` | The new paragraph attributes the trigger to "this section's own counterexample". The counterexample that fired lives in the spec's *AC-11, restated* section and in the PR body; this manifesto section quotes no closing keyword at all. |

### W-1 — a new cell where neither gate reads the evidence

Driven, both gates, one input set. Branch `lean/acme-42`; body closes #99 and #42; diff commits
`docs/plans/acme-99-lean.md`:

```
check-lean-chain.sh    rc=0  non-lean change — not applicable.
                             note: the diff carries lean spec(s) — docs/plans/acme-99-lean.md —
                             but none for this PR's own issue (#42) … Classified to the pipeline
                             chain gate, not this one.
check-pipeline-chain.sh rc=0 non-pipeline change — chain check not applicable.
                             configured prefix: claude/second-shift-
```

Both silent, each naming the other — the confident double hand-off step 4b exists to prevent. 4b
cannot see it: `KEY_BRANCH == KEY` here (the preference *succeeded*), so the mismatch arm never
evaluates.

The same inputs against the pre-fix gate (`git show c2995ee:scripts/check-lean-chain.sh`) print
`applicable via lean-artifact (docs/plans/acme-99-lean.md)`, `source issue: #99`, and demand the
evidence. So the cell is introduced by this commit, not inherited.

**Why a warning and not a blocker.** It needs a branch the lane cannot write. `tracker.branchPrefix`
is `claude/second-shift-` and `ci.yml`'s `PIPELINE_BRANCH_PREFIX` is the identical string, so every
branch either lane produces is prefix-matched and the sibling classifies it; for a prefix-matched
branch the same inputs make `check-pipeline-chain.sh` hard-fail on its own key check, which I drove
to confirm. Legacy `lean/`-prefixed heads are prefix-mismatched but have branch key == spec key, so
they do not reach this cell either. This is the same shape and the same reachability call as round
2's non-key-suffix cell, which was scored a warning under an approve — AC-17's invariant was already
known not to hold universally, and this widens a residual rather than opening a new class.

### W-2 — the guarantee is pattern-local

`KEY="$(resolve_body_key 'closes…')"` short-circuits the `part of` fallback whenever the closes
pattern matches *anything*, including a quoted mention. Driven, branch `claude/acme-42`, body
`Part of #42` plus prose quoting a closing keyword and #99, diff committing `acme-42-lean.md`:

```
✗ key mismatch: the PR body resolves to #99 but the head branch 'claude/acme-42' resolves to #42,
  and the diff commits #42's lean spec … Have the body close #42 …
```

That is B-1, intact, one pattern over. Not lean-lane-reachable — milestone 5 requires
`Closes #<issue>` at least once, so a lane-produced body always puts the branch key in the closes
set and the preference always applies. But the gate explicitly supports the `Part of` shape (`(M2)`:
"a sub-issue of a program epic"), and for that shape the remedy the message prints is wrong advice.
The narrow fix is to consult the branch key across **both** patterns before falling back; the
narrower one is to say in the comment, the spec and the manifesto that the guarantee is
closes-local. Either way the three shipped sites currently state it unqualified.

Credit: `unit-test-mutation-reviewer` (conf 80). I reproduced it before reporting it.

### W-3 — the sibling never got the lockstep

`check-pipeline-chain.sh:175` is still
`grep -oiE 'closes[[:space:]]+#[0-9]+' | head -n1`, feeding a hard fail at `:187`. Driven with a
staged-prefixed branch and a body whose real trailer is the branch key but whose prose quotes
another:

```
[pipeline-chain] applicable: branch=claude/second-shift-413 key=413
[pipeline-chain] ✗ key mismatch: PR body references #392 but the head branch resolves to #413.
```

Unchanged by this diff and not this PR's debt — but AC-19's headline claims both gates, and after
this commit the two derivations differ where they previously agreed. Scoring the AC by the letter of
the mechanism its body specifies (which is scoped to `check-lean-chain.sh` and ships) keeps it
satisfied; the headline is the over-claim, carried here. Same posture rounds 1–3 took with AC-11 and
AC-17. The follow-up is either the same preference in the sibling, or a `lockstep-manifest.tsv`
**DROPPED** row recording a real coupling that is not byte-anchorable — the repo's own prescription
for exactly this case.

### W-4 — a surviving mutant in new code

`grep -qF "$KEY_BRANCH"` (the `-x` dropped) → `bash -n` clean, suite `rc=0`, **0 failures**. The
mutant makes a short branch key match any body key containing it as a substring, flipping which key
4b compares. Shipped behavior is correct; the assertion is missing. The fixtures use 42/303 as
branch keys and 42/99/303 as body keys, so no pair collides. A case with a branch key that is a
proper substring of an unrelated body-cited key closes it (and, per the tier map, a
`tools/mutation-catalog.tsv` row if the mutant is worth pinning by name).

Credit: `unit-test-mutation-reviewer` (conf 82). Probed to confirm the survival.

## Verification at this head

Run from the checkout of `43b8428`:

- `shellcheck -e SC1091,SC2015,SC2181` over all shell — `rc=0`.
- `jq empty` over all JSON — `rc=0`.
- Full `*-selftest.sh` sweep, `-P 4`, **without** `SKIP_STRESS`, under `env -u CLAUDE_CODE_SESSION_ID`
  — `rc=0`, **0** `FAIL:` lines. The one reported failure is `doctor-selftest.sh` inside
  `install-topology-selftest.sh`, declared `known:` by that suite.
- `scripts/check-lockstep-pairs.sh` — 21 pairs, 0 failed.
- Mutation ordinals: all six operators enumerated per-line at `d7de926` and at head. Only
  **`detector`** re-keys (ordinal 2 moves `:372` → `:400`); `cmp-eq`, `cmp-z`, `logic`, `default`
  and `fail-open` keep their first-two sites byte-for-byte, so the five existing baseline rows for
  this guard still name what their notes claim and none is owed a re-key. `detector::1` and
  `detector::2` were both applied with the verbatim operator flip and both **KILLED** (suite rc=5
  and rc=61), so no row is added either. Matches the commit's claim exactly.

**CI has not run at this head.** `43b8428` has **zero** check-runs and the PR's status rollup is
empty; the newest run on the branch is at `d7de926`. This is a dispatch miss, not a red — the repo
dispatched four runs on other branches in the 20 minutes after this push. Pushing this record
retriggers CI, which is what the merge boundary will read. The local evidence above stands in for it
in the meantime.

## Reviewer panel

All six selected reviewers returned — the first round on this PR with no dark reviewer.

| Reviewer | Verdict | Findings |
| --- | --- | --- |
| Security | Pass | 0; 2 suppressed (conf 40/35), both correctly triaged as non-findings. |
| Complexity | Pass | 0 |
| Maintainability | Pass | 0 |
| Test coverage | Pass | 0 |
| Unit-test mutation | **Request-changes** | 3. Two are W-2 and W-4 above, both reproduced by me before adoption. The third (no case carries both `Closes` and `Part of`, so the precedence swap is unpinned) is a pre-existing gap the refactor now routes through one helper — real, and folded into W-2's remedy. |
| Scope completeness | Pass | 0; 2 suppressed. It caught that the dispatch base was an intermediate merge commit and re-anchored on `merge-base(origin/main, HEAD)` itself rather than emitting a false FAIL — the round-1/2/3 `stages/2-worktree.md` item did not recur under that anchor. |

`a11y-reviewer` and the design-fidelity dimension were **not routed**: no changed path matches
`stageParams.webComponentGlobs` (unset, so the shipped default `apps/web/**/*.{tsx,jsx}`). Not a
coverage gap. `db-reviewer`, `pipeline-reviewer` and `performance-reviewer` were not selected — no DB
layer, no queue/worker files, and no performance surface in a five-file shell/docs delta.

W-1 and W-3 are in-session findings, each established by execution. The panel found neither.

## Per-AC scoring (19 ACs, at `43b8428`)

Scored by the letter of what each AC requires the implementation to do, against the whole spec.
AC-1 through AC-13, AC-15, AC-16 and AC-18 are inherited from round 3's coverage of
`4b8fcb842c99`, with the ones the delta could disturb re-confirmed here rather than asserted.

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | `lean_branch_prefix` absent from both consumers (0 occurrences, re-checked). |
| AC-2 | satisfied | inherited; `(n0b)` unchanged and green in this sweep. |
| AC-3 | satisfied | inherited; the two residual `claude/acme-` strings in `branch-prefix.sh` are both comments. |
| AC-4 | satisfied | inherited; both refusals green in this sweep. |
| AC-5 | satisfied | one resolver, two callers (`lean-gate.sh`, `retro-corpus.sh`), re-checked. |
| AC-6 | satisfied | `LEAN_BRANCH_PREFIX`: 0 in `ci.yml`, 1 in `check-lean-chain.sh` and that one is the deletion-narrative comment at `:303`. Confirmed live — the real-inputs drive classifies via the artifact arm with no such variable in its environment. |
| AC-7 | satisfied | sibling reports not-applicable for this PR; re-driven with `ci.yml`'s real constants. |
| AC-8 | satisfied | `lean-spec-suffix` row present; `check-lockstep-pairs.sh` 21/0 at this head. |
| AC-9 | satisfied | `(A)` drives a legacy `lean/`-prefixed head through the artifact arm; green. |
| AC-10 | satisfied | inherited; `check-pipeline-chain-selftest.sh` green in this sweep. |
| AC-11 | satisfied | re-verified under the new derivation: key-matched applicability on both sides, and the unresolvable-reference refusal still fires (it is evaluated before 4b). |
| AC-12 | satisfied | inherited; both halves green in this sweep. |
| AC-13 | satisfied | `run-lean/SKILL.md` 42 lines (cap 60), no "lean prefix"; manifesto section extended, not replaced. |
| AC-14 | satisfied | including the round-3 amendment: `(e5)` reaches milestone 1's body and is the only red under the `require_branch_name` mutant. |
| AC-15 | satisfied | shellcheck / `jq empty` / full sweep / lockstep all green at this head, and the ordinal re-key obligation discharged by enumeration plus probing rather than assertion. |
| AC-16 | satisfied | the two deferral rows are committed and unchanged; the delta's only guard edit is to `check-lean-chain.sh`, already on the deferred list, and adds no guard to the PR lane. Timing evidence is round 3's CI at `847ea54` (`mutation sweep (PR-scoped)` 17s against `timeout-minutes: 15`); no CI exists at this head — see above. |
| AC-17 | satisfied | the refusal mechanism ships, is scoped by `(D3b)`, and fires on a real disagreement — driven. Its invariant remains non-universal; W-1 widens the residual and is reported as such. |
| AC-18 | satisfied | inherited; `(k2)`/`(k2b)` green in this sweep. |
| AC-19 | satisfied | the specified mechanism ships and is driven by `(D3c)`/`(D3d)`, both probed in both directions from this checkout. The headline's "two chain gates" over-claims — W-3. Its "by construction" is closes-local — W-2. |

19/19 satisfied. The scope gate did not repeat rounds 1–3's `stages/2-worktree.md` item this round;
ledger `D-1` (`user-answered`, pre-implementation) would still override it, and the tracked scope
still diverges from the shipped scope until a follow-up amends one of them.
