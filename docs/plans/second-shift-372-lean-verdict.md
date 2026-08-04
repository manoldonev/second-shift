# lean review verdict — #372

verdict=approve
run_id: review-372-2
session_id: f0719e6e-f48b-4ed4-8b4e-4a9e854fe1bd
rounds: 2
pr: #373
reviewed_head: 997d05e6124c8bc868c4597e49886fdbd75e0f64
reviewed_patch_id: 81581dc73999f2150bff78d1d6e68dfe31411476
model: unknown

## Review summary

Round 2 on PR #373 (issue #372), reviewing `997d05e` — seven commits on top of `57b3314`. The
change re-keys the lean verdict record's DECLARED freshness arm from a commit SHA to
`git patch-id --stable` over `merge-base(base, head)..head`, excluding the record path, across
**three** readers. Six reviewers ran (security, performance, complexity, maintainability,
test-coverage, scope-completeness); none went dark. Five returned approve; scope-completeness
returned request-changes on one `minor` finding, which I did not adopt as a blocker — reasoning
under W1, stated rather than silent.

**Verdict: approve.** All ten of the committed spec's ACs are satisfied. Every round-1 blocker
is closed, and each was re-verified by execution in this session rather than read off the PR
body — which is the discipline round 1 died for want of.

The engineering was already right in round 1 and is unchanged: patch identity is the correct
detector for the property being claimed, the exclusion is pinned **behaviorally** on both
currency readers rather than by a copy of the formula, each new block asserts its own premise so
a fixture that quietly grew the key cannot migrate it and leave the fallback uncovered, and the
rebase cases assert the SHA arm *would* have redded on that exact state. What round 2 adds is
that the evidence now matches the artifact.

## Round-1 blockers, re-verified

| # | Round-1 blocker | Status | How I verified it here |
| --- | --- | --- | --- |
| B0 | Suite red on both CI lanes at `2ff7700` — `(v6)` reached its arm only when the operator's ambient `CLAUDE_CODE_SESSION_ID` leaked into the fixture | **closed** | Ran `lean-gate-selftest.sh` twice, with and without the variable: output **byte-identical**, both `rc=0`. The fix has both halves — `seed_build_progress` before `(v6)` so the writer reaches its own arm, and `unset CLAUDE_CODE_SESSION_ID` in `gate`/`gate_cfg` so no future case can be green for this reason |
| B1 | `--help` truncation: `lean-gate.sh`'s header grew to line 86 while the range stayed `2,75p`, dropping the whole `Seams` block | **closed** | Recomputed the range on all three touched guards: `lean-gate.sh` 86/`2,86p`, `lean-reconcile.sh` 56/`2,56p`, `check-lean-chain.sh` 102/`2,102p` — all exact. `(w)` is added two-sided, byte-shaped like the sibling's long-standing `(T)` |
| B2 | AC-6's mutation table was wrong for `check-lean-chain.sh` (claimed 12/5/7 with a `cmp-z::2` survivor) | **closed** | Re-ran `mutation-sweep.sh --mode pr --base origin/main` myself. Reproduces the new table **exactly** — see the AC-6 row below |
| B3 | OR-2, an issue-declared `pause-and-ask` region, resolved as spec D-6 with no operator record | **closed** | Ratified by an operator comment on the issue at 2026-08-04T09:55:40Z, resolving it **as built**. That is the right remedy shape: an authority the build session structurally lacks, supplied from outside it |

## Per-AC scoring

Scored against the committed spec `docs/plans/second-shift-372-lean.md`, which is this lane's
definition of done.

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 — milestone 4 passes after a clean-replay rebase, fails on a post-record commit | satisfied | `(v3)` over a **real** rebase onto a base that moved with content; `(v3a)` asserts the SHA arm would have redded on that exact state, so the case is not vacuous; `(v4)` reds a post-approve commit shaped so the inferred arm stays green and only this arm can fire |
| AC-2 — the same at the merge boundary, including the case the old arm could not express | satisfied | `(U3)` clean replay passes; `(U4)` a rebase whose resolution changed a line is refused, with the inferred arm green so the declared arm alone can fire; `(U3a)` pins non-vacuity |
| AC-3 — a pre-key record still gates on the SHA path, and the pass line names the arm | satisfied | `(u1)`–`(u4)` drive the fallback and `(u5)` asserts the block really is on it; `(R5)`, `(L4)` do the same at the other two readers. D-8 holds in code: `lean-gate.sh:739` prints `patch-id <short>`, `:755` prints `declaring reviewed_head <short>` — distinct, so AC-3 cannot be satisfied by the new arm passing |
| AC-4 — the exclusion holds | satisfied | Pinned **behaviorally**, not by a copy of the formula: `(v2)` and `(U2)` edit the record's own bytes, commit, and require the gate to still pass |
| AC-5 — doc scope | satisfied | `run-lean/SKILL.md:36` and `review-lean/SKILL.md:35-60` rewritten; `check-lean-chain.sh:36-47` states covers / does-not-cover. `run-lean/SKILL.md` is still exactly 60 lines, so `(f)`'s cap holds. The `interviewing-baseline` re-point is evidence-backed and I reproduced it: `grep -ciE 'rebase\|reviewed_head\|verdict'` over that file returns **0** — the issue named a file that cannot carry the prose. See W1 |
| AC-6 — mutation survivor ordinals checked and re-baselined, evidence in the PR body | satisfied | **Reproduced by execution.** `lean-gate.sh` 10/7/3 `cmp-eq::1, default::1, default::2`; `lean-reconcile.sh` 11/5/6; `check-lean-chain.sh` 12/6/6 — every count and every survivor id matches the PR body, and `grep -c` over `tools/mutation-baseline.tsv` returns 3/6/6 for the three guards. Sweep `rc=0`: no baseline-absent survivor. The one moved ordinal is honest and correctly explained — adding `(w)` kills `lean-gate.sh::cmp-z::1` because `sed -n '2,86p'` *is* a `cmp-z` site, so the row is removed |
| AC-7 — `Changelog:` trailer | satisfied | 7 trailers across 7 commits |
| AC-8 — an empty/unresolvable patch id is a refusal, not an unmeasured pass, on each reader | satisfied | `(v5)` reader and `(v6)` writer in `lean-gate.sh`; `(U5)` `PR_BASE_REF` and `(U6)` unresolvable base at the boundary. On the third reader the wording diverges and I am scoring it deliberately, not glossing it — see N1 |
| AC-9 — the third reader is re-keyed | satisfied | `(M1)` coherent record names the patch-id arm, `(M2)` a real rebase reconciles with the ancestry arm asserted to have failed on it, `(M3)` an incoherent id still fails; `(M0)` guards the fixture against comparing nothing |
| AC-10 — the liveness scenario gains a composing leg | satisfied | Leg 7 `(lean-patch-id)` writes through the **real** `verdict` subcommand rather than a printf, composes across a real rebase, asserts `lean_sha_would_red` is non-empty, and re-reds on a later commit. Suite 59/59 |

## Warnings (should fix, not blocking)

**W1 — the issue body's AC-5 still names a file the branch cannot touch.**
`plugins/intake-toolkit/skills/interviewing-baseline/SKILL.md` contains zero occurrences of
`rebase`, `reviewed_head` or `verdict` — I reproduced the grep. The branch re-points that surface
to `review-lean/SKILL.md`, which does carry the prose and is updated.

I am **not** adopting scope-completeness's `request-changes` as a blocker, and the override is
stated rather than silent. Three reasons, in order of weight:

1. This lane's definition of done is the **committed spec**, not the issue body — the review
   skill says so and milestone 5 requires the PR to link it. The spec covers all three surfaces.
2. The re-point lands in the spec's **first commit** (`2cc81f5`), before a line of implementation
   existed. It is therefore not the thing the lane forbids — a spec amended after the fact to
   match the diff. The later spec edit (`621b205`) only *adds* AC-8/9/10, tightening the bar.
3. Nothing is narrowed and no code or behavior is missing — the reviewer says so itself, and
   files the finding as `minor`.

What is genuinely left open is that someone reading #372 alone would see an AC pointing at the
wrong file. The remedy is one operator comment on the issue, in exactly the shape that ratified
OR-2 — it is not a code change, and a further review round could not produce it.

**W2 — `lean-reconcile.sh`'s empty-patch-id arm has no selftest case.** The `(M)` block covers
coherent, rebased and incoherent, but not the "cannot measure" note at `lean-reconcile.sh:247`.
Cheap to add; see N1 for why it is not an AC-8 failure.

**W3 — a second spelling of an existing selector.** `RECONCILE_BASE`
(`lean-reconcile.sh:238`) resolves the host repo with an inline
`select(.value.path==".") | .value.baseBranch`, while `HOST_Q` is already in scope four lines
into the same file and is how `lean-gate.sh:169` spells the identical resolution. Behaviorally
equivalent — a nit, and only worth folding into the next edit of that file.

## Notes

**N1 — how I scored AC-8's third reader, deliberately.** `check-lean-chain.sh` and
`lean-gate.sh` refuse (rc=2 / rc=1). `lean-reconcile.sh` emits a `say` note at rc=0. Read
literally, "a refusal" is not what that arm does. I score it satisfied anyway, and the test is
the deletion direction rather than the wording: that arm is entered only when
`REVIEWED_PATCH_ID` is non-empty, so deleting the guard makes an empty recompute compare
**unequal** and emit `bad` — fail-closed. The fail-open hazard D-5 names ("two failed
computations compare equal") is structurally unreachable there, which is precisely the rationale
AC-8's own clause gives for demanding per-reader coverage. The note is also the established
in-file idiom for every other uncheckable condition in that script. Recording the reading so the
next round inherits the argument, not just the score.

**N2 — round 1's rulings I did not reopen.** AC-5's re-point and AC-8's third reader were both
examined and scored satisfied in round 1 on unchanged content. I re-derived the crux of each
myself rather than inheriting it, and reached the same place. Reversing a round-1 ruling with no
new evidence is the escalation this lane forbids.

## Suppressed (below the confidence threshold)

- `check-lean-chain.sh` / `lean-gate.sh` — confidence 45 — `:(exclude)$VERDICT` interpolates a
  filename into a git pathspec where `*`/`?` are fnmatch wildcards. The name is suffix-
  constrained, an emptied diff hits the guarded empty-id refusal rather than a pass, and the
  actor already has branch write access. Speculative.
- `lean-reconcile.sh` / `check-lean-chain.sh` — confidence 40 — the nested `$(git merge-base …)`
  can expand empty, yielding `git diff "" <sha>`. Guarded by the following empty-id branch;
  robustness, not security.
- `lean-reconcile.sh:247` — confidence 75 — no selftest case for the vacuity note. Carried up as
  W2.
- `docs/plans/second-shift-372-lean.md` — confidence 60 — the spec adds AC-8/9/10 beyond the
  issue body. A superset of filed scope, not a gap.

## Verdicts

| Reviewer | Verdict | Findings | Confidence |
| --- | --- | --- | --- |
| Scope Completeness | Request-changes (not adopted — W1) | 1 minor | 92 |
| Security | Pass | 0 | — |
| Performance | Pass | 0 | — |
| Complexity | Pass | 0 | — |
| Maintainability | Pass | 0 | — |
| Test Coverage | Pass | 0 | — |

## Verification run in this session

Run from a checkout of `997d05e`, **without** `SKIP_STRESS` and **with**
`env -u CLAUDE_CODE_SESSION_ID` — a bare local sweep is what missed the leak in round 1.

- `shellcheck -e SC1091,SC2015,SC2181` across the repo: exit 0
- `jq empty` across the repo: exit 0
- full `*-selftest.sh` sweep (`-P 4`): exit 0, zero failures
- `check-lockstep-pairs.sh`: 13 pairs, 0 failed
- `scenario-liveness-selftest.sh`: 59 passed, 0 failed — including the `(lean-patch-id)` leg
- `lean-gate-selftest.sh` with and without `CLAUDE_CODE_SESSION_ID`: byte-identical, both rc=0
- `mutation-sweep.sh --mode pr --base origin/main`: rc=0, table reproduced as above (advisory
  run — macOS, `GITHUB_ACTIONS` unset — so its kill verdicts are not comparable to CI's; the
  survivor **id set**, which is what AC-6 asks for, is)
