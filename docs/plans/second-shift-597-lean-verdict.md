# lean review verdict — #597

verdict=needs-work
run_id: review-597-2
session_id: 53fd55c8-a5bd-41e1-b316-f66558a30ef2
rounds: 2
pr: #601
reviewed_head: b768db907ea7f3a6591456b11eb1786047d9a7ef
reviewed_patch_id: 56dd73a57dd7a997fda0275ece11ba1466ef1683
inherited_patch_id: 79eb4344d6a86e76a6f74ed85ba4a9c41759db2d
inherited_from_verdict: 170953eea3f9034ec01c5cffcc39bb971321d839
fidelity: not-applicable
model: unknown
capabilities: pr-marker

Round 2 (`review-597-2`), inheriting round 1's coverage of patch `79eb4344d6a8`.
Read range `170953e..HEAD` — the single new commit `b768db9`, a merge of `origin/main`
into the branch. Panel dispatched over the branch's own contribution at the merged head
(`origin/main...HEAD`, 12 files, +964/-14) so the merge composition was re-read, not just
the merge diff: security, performance, maintainability, complexity, test-coverage,
unit-test-mutation, scope-completeness. 6/7 returned; test-coverage went dark.

## Verdict: needs-work — one blocker, outside the AC set

Round 1's blocker is **cleared**. The PR was born unmergeable and had never been graded
by CI; `b768db9` fixes that. `refs/pull/601/merge` now exists, and the two selftest jobs
are green at this head — `lint-and-selftests` (3m50s) and `selftests (macos, bash 3.2)`
(6m57s). That is the stock bash-3.2 lane and CI's shellcheck 0.9.0 actually grading the
branch for the first time, which is what round 1 could only approximate by hand.

The conflict resolution is exactly what round 1 measured in trial: `scripts/lockstep-manifest.tsv`
resolved as a union, main's `tier-alphabet-parse` row (#596) first, this branch's
`contribution-compare` row second, no line of either side altered. `check-lockstep-pairs.sh`
passes 24/24 including `contribution-compare`, and the two copies of the predicate are
byte-identical at this head.

But CI, now that it runs, reds a lane the branch itself caused.

## Blocker

**B-1 — `mutation-sweep-pr` is RED on a baseline-absent survivor this PR introduces.**
`plugins/dev-pipeline/skills/build-lean/lean-evidence.sh::cmp-eq::4480dc581ad4`
(job 96362307413: `applied=11 killed=10 survived=1`).

The site is `lean-evidence.sh:571`, inside this PR's own new `contribution-compare` block:

```sh
if [ "$rc" -eq 0 ] && { [ ! -s "$d/old" ] || [ ! -s "$d/new" ]; }; then rc=2; fi
```

It is PR-introduced, not inherited: `origin/main`'s `lean-evidence.sh` carries exactly one
`cmp-eq` site (`[ "$APPLICABLE" -eq 0 ]`); this PR adds two, and the survivor is one of them.
It is absent from `tools/mutation-baseline.tsv` and from `tools/mutation-catalog.tsv`, so
per CLAUDE.md it reds the lane rather than reading as data.

Not flake. Reproduced locally at this head (`--mode pr --base origin/main`): same id, and the
sweep's own serial re-verify outside the pool agreed — "really does survive its kill set".

**Why no case kills it.** `contribution_delta` reaches `rc=2` by two routes. `(s3)` in
`lean-evidence-selftest.sh` and `(vb3)` in `lean-gate-selftest.sh` both drive the *same* one —
a `reviewed_head` that is not a commit in the checkout, which returns from
`contribution_lines` at line 536 and never reaches 571. The second route — both computations
succeed but one side's contribution is **empty** — has no case at all. That is the route the
block's own header singles out as load-bearing rather than defensive: "two failed computations
compare EQUAL, so an unguarded reader prints its ✓ having compared nothing."

**The mutant is not a log-text difference — it flips the verdict.** Probed against the real
predicate sourced from this head, with `reviewed_head` a commit on the base branch (its own
contribution therefore empty):

| | rc | outcome |
| --- | --- | --- |
| original | 2 | fail-open, verdict **stands** — `freshness: reduced-strength`, names OR-1 |
| mutant | 1 | **violation** — falsely invalidates, enumerating `f.txt 1 +branchline` |

So with the guard mutated away, an empty old-side contribution is compared against a non-empty
new side, they differ, and the arm reds. That is a false invalidation in precisely the case
D-5/OR-1 exists to let stand — the failure class this whole PR is about, reachable through the
PR's own new code, with nothing asserting against it.

**It is cheaply killable, and one fixture closes both copies.** A case whose record names a
`reviewed_head` that is a valid commit with an empty own-contribution (an ancestor of the base
is the natural shape), asserting `rc=0` plus the `freshness: reduced-strength` / OR-1 line the
way `(s3)` already does. Under the mutant that case fails on rc alone.

**Do the gate side too.** `lean-gate.sh` carries the byte-identical block, so its twin site
keys to the same `cmp-eq::4480dc581ad4`. The PR lane deferred `lean-gate.sh` to nightly
("slow suite, 147s"), so that twin was never scored here — merging as-is moves the red to the
nightly sweep instead of resolving it. A paired case in `lean-gate-selftest.sh` alongside
`(vb3)` closes it.

A `tools/mutation-baseline.tsv` row is the other admissible remedy, but it would be the wrong
one: the site is demonstrably killable, so a row accepting it as unkillable-by-construction
would not be true.

## AC scoring — all 7 satisfied

Every `AC-n` re-scored against the whole spec at this head, per the inheritance rule.

| AC | Score | Basis |
| --- | --- | --- |
| AC-1 | satisfied | Both milestone-4 arms consult `contribution_state`, and the merge boundary's `arm_freshness` consults `contribution_delta`; `(vb1)`, `(s2)`/`(s2a)`, and the `(lean-base-advance)` scenario cover the end-to-end path. |
| AC-2 | satisfied | `orchestrate-lean.sh` routes `verdict_rc` rc=3 and rc=2 ahead of the REVIEW spawn; the dead `3)` case arm is deleted; `(vr1)`–`(vr3)`, non-vacuity by `(vr4)`. |
| AC-3 | satisfied | `contribution_delta` rc=1 emits `path<TAB>count<TAB>first-offending-line`, rendered by `contribution_summary` into every `fail_milestone 4` / `note_violation`; `(vb2)`. |
| AC-4 | satisfied | `contribution_lines` diffs each side against its **own** merge-base and emits only in-hunk `+`/`-` lines; the column-0 state machine excludes context and the `---`/`+++` headers. |
| AC-5 | satisfied | Three tiers present and non-vacuous: `(vb0)` asserts both arms *would* have redded, `(s2a)` asserts the fixture reproduced the #583 state, `(vr4)` likewise. |
| AC-6 | satisfied | The fail-open is asserted, not left to a reading of the code — `(vb3)`, `(s3)`. Note B-1: only one of its two routes is asserted. |
| AC-7 | satisfied | Verified at the merged head — both prose edits survived the merge intact: `build-lean/SKILL.md:36` and `review-lean/SKILL.md:131-136`. |

B-1 sits outside the AC set, exactly as round 1's blocker did. Scope completeness re-scored
all seven issue items as in-diff (PASS).

## Merge composition — checked, sound

Main brought its own `lean-gate.sh` changes (the #141/#599 rc=9 wrong-tree guard) into a file
this PR also edits. Verified independently and by the panel: `require_lane_tree` dispatches in
the `1|2|3|4|5|all|delta|verdict` block strictly before `run_milestone`/`cmd_verdict`, so a
wrong-tree call still evaluates nothing and never reaches `cmd_4`'s new `contribution_state`.
`BASE_BRANCH` and `VERDICT_REL` are both established before any consumer. The `--help` sed
range auto-resolved to `2,317p`, which lands exactly on the line before `set -uo pipefail`.
No conflict markers; `bash -n` clean on all seven touched shell scripts. No frozen file
touched; `Changelog:` trailers present.

## Warnings — carried, not re-litigated

Round 1's **W-1** (the rc=2 fail-open lets a force-push / history rewrite reach
`inapplicable freshness reduced-strength` rather than a violation) and **S-2**
(`contribution_lines` reads only `+`/`-` body lines, so a mode change or pure rename produces
no contribution) both still stand, unchanged by the merge. B-1 is a near sibling of W-1 —
same `rc=2` fail-open, reached by the empty-contribution route rather than the
unreadable-head one — which is part of why a case there is worth having.

## Coverage gap

`test-coverage-reviewer` went dark (empty result after its automatic retry) — its domain was
not reviewed by the panel this round. `unit-test-mutation-reviewer` went dark on first
dispatch and **succeeded on retry**, returning three confirmatory nits. Merge readiness here
is assessed without a test-coverage reviewer opinion; the test-adequacy question that matters
this round is B-1, which was established from CI, a local reproduction and a controlled probe
rather than from a reviewer's judgment.

`a11y` and the design-fidelity dimension were not routed: no changed path matched
`stageParams.webComponentGlobs` (unset → default `apps/web/**/*.{tsx,jsx}`). `db-reviewer`
and `pipeline-reviewer` were not triggered. Not coverage gaps — triggers that did not fire.

## Panel verdicts

| Reviewer | Verdict | Findings | Confidence |
| --- | --- | --- | --- |
| Scope Completeness | Pass | 0 | — |
| Security | Pass | 0 (3 suppressed) | — |
| Performance | Pass | 0 | — |
| Complexity | Pass | 0 | — |
| Maintainability | Pass | 0 | — |
| Unit Test Mutation | Pass | 3 nits | 82–90 |
| Test Coverage | Dark (no output) | — | — |

## What round 3 needs

One build round, no design work: add the empty-contribution case to
`lean-evidence-selftest.sh` and its twin to `lean-gate-selftest.sh`, then confirm
`mutation-sweep-pr` goes green. Nothing else in this PR is asked to change.
