# lean review verdict — #710

verdict=approve
run_id: review-710-2
session_id: afae6004-1300-4700-a042-7f32c900d597
rounds: 2
pr: #741
reviewed_head: 11bda2e92b2a223647fd0d0fe562ec7370ed42b1
reviewed_patch_id: e384a5e97eb0c3345e9c4fcfc0d9fda7b3d9030f
inherited_patch_id: c653fba65d61c5986d491a434e07d8afad4a5ec6
inherited_from_verdict: a1fd43e41e18085d2ef550fc913861b9f9f2ec50
fidelity: not-applicable
model: opus
capabilities: pr-marker

Round 2 — delta range `8f572172..HEAD` (2 files, +4/-4), inheriting the coverage of patch
`c653fba65d61` from round 1. Both round-1 blockers were red CI lanes, not unmet ACs; both are
now green on CI at this exact head, and the fixes touch no production logic.

Verdict: **approve**.

## The two round-1 blockers

**B1 — `lint-and-selftests` (shellcheck 0.9.0 SC2119/SC2120). FIXED.**
`af076210` deletes the unused `[verdict]` positional from `lean_dplanrev_sync` rather than
passing `pass` at the call site. Verified three ways:

- The pinned CI binary (`shellcheck 0.9.0`) running the exact CI recipe
  (`find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181`) over the
  whole repo at this head: **0 findings, rc=0**.
- Control, same binary: the pre-fix blob (`a1fd43e4:…/scenario-liveness-selftest.sh`) still
  reproduces both SC2119 and SC2120 — so the clean result is the fix, not a binary that cannot
  raise the codes.
- CI itself: `lint-and-selftests` **success**, and every one of its 16 steps reports `success` at
  `head_sha 11bda2e9`. Round 1's finding was that this job's shellcheck step is step 1 and had
  skipped all 9 later steps; this round they all ran. That includes
  `gate bucket register (scripts/gate-buckets.tsv)`, which is **AC-7's own oracle** and had no CI
  evidence at all in round 1.

The fix loses no coverage: the call site was the only one, and it never passed a verdict. The
sibling `dplanrev_sync` in `lean-gate-selftest.sh` correctly keeps its parameter, because
`(dpr3)`/`(dpr4)` genuinely pass one.

**B2 — `selftests (macos, bash 3.2)` (`tools/prose-blockers-selftest.sh`). FIXED.**
`11bda2e9` re-keys `pb-0c42ee3f` → `pb-cbe0e255` and adds `pb-1c5740d4`.
`bash tools/prose-blockers.sh check` at this head: `✓ zero undispositioned constructs`
(census 26, record 48 rows). CI: `run all selftests under stock bash 3.2` **success**.

Both rows were checked for substance, not just for making the census balance:

- `pb-cbe0e255` anchors `build-lean/SKILL.md:27`, which is the step-6 line that now names the
  plan-review dispatch and `bash G plan-review`. The `gate-backed` disposition against
  `lean-gate.sh::milestone-3` is true — `design_plan_review_gate` is the refusal it restates.
- `pb-1c5740d4` anchors `figma-faithful/SKILL.md:207`, the step-7 dispatch paragraph, which
  gained "milestone 3 refuses to render until the reviewer's output is committed". Also a genuine
  restatement of the same gate. The census growing 25 → 26 is consistent with exactly one re-key
  plus exactly one new construct.

## Inheritance is sound — the base merge changed none of the reviewed lines

Round 1 reviewed up to `8a597d10`; `8f572172` then merged `origin/main`. I compared the branch's
**added** lines per file between round 1's range and this head's range against the true
merge-base:

| File | r1 added | r2 added | |
| --- | --- | --- | --- |
| `lean-gate.sh` | 282 | 282 | identical |
| `lean-gate-selftest.sh` | 217 | 217 | identical |
| `scripts/gate-buckets.tsv` | 4 | 4 | identical |
| `tools/mutation-catalog.tsv` | 8 | 8 | identical |
| `docs/live-render.md` | 18 | 18 | identical |

So round 1's coverage genuinely inherits and the delta above is the whole of what is new.

The PR body's census figures moving (buckets 311/167 → 305/161, lockstep 30 → 29, liveness
83 → 80) is main's own deletions, as the body states. Independently confirmed: the true
merge-base is `b3deab1c`, not the stale local `main` at `7e82408f`, and
`scripts/check-reviewer-references.sh` / `scripts/capability-parity-check.sh` — which round 1 ran
at those paths — were already absent at the merge-base. Both guards still exist at
`plugins/review-toolkit/scripts/check-reviewer-references.sh` and
`tools/capability-parity-check.sh`, and both are green at this head.

## The changed fixture still has teeth

The delta edits a test fixture, so the question round 2 owes is whether the edited suite can still
fail. Probed in an isolated worktree at this head: applying the `lean-gate-plan-review-absent-waved`
catalog mutant to `lean-gate.sh` reds `scenario-liveness-selftest.sh` at
**79 passed, 1 failed**, and the one failure is exactly the leg this branch adds —
`(lean-design-plan-review) rcs=100 attempts=1 rendered=yes` against the expected
`rcs=111 attempts=0 rendered=no`. Scored by set-difference of case text against a same-env clean
baseline.

All eight new catalog rows were re-checked for anchor drift at this head under `sed -E`: each
applies and changes **exactly one line**. The base merge moved none of them.

## Per-AC scoring

All nine satisfied. Every AC is re-scored at this head against the whole spec, not inherited.

| AC | Verdict | Evidence at this head |
| --- | --- | --- |
| AC-1 | satisfied | `design_plan_review_gate` runs at the end of the plan pass, before any render. `(dpr1)` and the composed `(lean-design-plan-review)` leg both green; the mutant probe above proves the leg fails when the refusal is removed. Unchanged from round 1 — code lines byte-identical. |
| AC-2 | satisfied | `plan_patch_id` excludes `PLAN_REVIEW_MANIFEST_REL`; `(dpr2)` / `(dpr2-stale)` green in a full `lean-gate-selftest.sh` run (`all green`, all 11 `(dpr*)` cases pass). |
| AC-3 | satisfied | `(dpr3)` (block quoted, heading not quoted) and `(dpr4)` (`fix-and-go` reaches render) green. |
| AC-4 | satisfied | `(dpr8)` green — writer stamps `reviewed_plan_from` from the checkout, refuses an out-of-enum verdict, and writer/reader agree on the stamped value. |
| AC-5 | satisfied | `grep -rn 'autonomous lane' plugins/design-toolkit` → empty at this head. |
| AC-6 | satisfied | 8 catalog rows, all anchoring to exactly one line; liveness scenario extended and proven killing; `feat(dev-pipeline):` on the feature commit with a substantive `Changelog:` trailer; `check-changelog-trailer.sh` green locally and on CI. |
| AC-7 | satisfied | `check-gate-buckets.sh` → `✓ 305 enumerated refusal site(s) across 5 file(s), all bucketed by 161 register row(s)`. **This round it is also CI-verified**: the `gate bucket register` step reports `success` at `head_sha 11bda2e9`. |
| AC-8 | satisfied | `build-lean/SKILL.md` step 6 and `docs/live-render.md` both state the dispatch-and-record lane contract; verified by reading the lines the triage rows anchor. |
| AC-9 | satisfied | #739 cited at `lean-gate.sh:3215` above `design_family_plan_reviewer()` (line moved from 3333 by main's deletions, not the branch's). |

## Merge-boundary state (recorded, not a blocker)

`pr-gates` is red on one step only — `lean chain reconciliation`, because no approve verdict
record exists yet. Its three sibling policy steps (frozen files, changelog trailer, pipeline chain)
are all `success`. This is the expected pre-approve state and is what this record clears.

`mutation-sweep-pr` passes in 13s and grades **nothing** here — `lean-gate.sh` is a slow-suite
guard deferred to nightly. The PR body says exactly this. Its green is not evidence, which is why
the mutants were probed by hand.

## Panel

Five reviewers selected, five alive, none dark: security, performance, maintainability,
test-coverage, scope-completeness. **All five approve with zero findings.** Routing: the delta is
2 files / 8 lines (Small, and at least Small because it touches a `*.sh`); test-coverage was
spawned because the change touches a test file; scope-completeness spawned unconditionally on
`Closes #710`. a11y and the design-fidelity dimension were not routed — no changed path matches
`stageParams.webComponentGlobs` (unset, so the shipped default `apps/web/**/*.{tsx,jsx}` applies).

Two of scope-completeness's suppressed notes were checked rather than taken at face value:

- It flagged that the branch "also carries #720's work … and commit `b3deab1c`". That is the base
  merge, not scope creep: `b3deab1c` is an ancestor of `origin/main`. Dismissed.
- It noted the toolkit-absent `envfail` arm (D-35) has no selftest case and no catalog row, and
  declined to score it a scope miss. Agreed, and carried below as non-blocking — AC-6 scopes
  catalog rows to milestone reds and this arm is deliberately not one.

## Non-blocking (carried forward from round 1, unchanged and still not blockers)

- **The `block` primitive vs its gloss.** The ticket's guess-point 7 glosses `block_milestone` as
  "spends an attempt"; here it spends none. The spec adjudicates in writing that the named
  primitive wins, and `(dpr3)` pins `attempts == 0`. Flagged so the human confirms the primitive
  was the intent.
- **An unresolvable design family passes quietly.** `design_plan_review_gate` takes the
  declined-mandate branch on an empty family and returns 0, emitting `the '' design family ships
  no plan-stage reviewer`. Only reachable from an armed spec whose handoff names no known host,
  which milestone 4 refuses separately.
- **Writer-side arms are thinly covered.** `cmd_plan_review` has seven `envfail` branches;
  `(dpr8)` drives two plus the happy path. The D-35 toolkit-absent arm is among the untested five.
  All are usage errors, none merge-blocking, and the reader-side gate is thoroughly covered. A
  future test of the `--model` arm needs a scrubbed env — it falls back to `LEAN_RUN_MODEL`, which
  is known to leak into suites.
- **`build-lean/SKILL.md` step 6 templates `design-toolkit:<provider>-faithful-plan-reviewer`.**
  For `claude-design` that expands to an agent that does not exist, and is not the name #739
  discusses. The gate's own refusal names the exact agent, so a build session is not misled.

## Strengths

- The fixes are the minimal correct ones. B1 could have been silenced by passing `pass` at the
  call site; deleting the dead parameter instead removes the shape that caused it, and the
  sibling helper that legitimately takes a parameter was correctly left alone.
- The prose-blocker re-key is honest work rather than census arithmetic: both rows name the real
  enforcer, and the one genuinely new construct is distinguished from the one that merely moved.
- The PR body states the base-merge cause of every moved census figure instead of letting the
  numbers stand bare, and states plainly that `mutation-sweep-pr`'s green covers nothing here.

## Verified here

`lean-gate-selftest.sh` (`all green`, 11/11 `(dpr*)`), `scenario-liveness-selftest.sh`
(80 passed, 0 failed), `prose-blockers-selftest.sh` (60 passed, 0 failed) — the three suites
milestone 3's sweep defers as slow. Plus `check-gate-buckets.sh`, `check-lockstep-pairs.sh`
(29 anchors, 0 failed), `check-lane-class-doc.sh`, `check-eval-model-identity.sh`,
`tools/capability-parity-check.sh` (37 rows), `plugins/review-toolkit/scripts/check-reviewer-references.sh`,
`check-frozen-files.sh`, `check-changelog-trailer.sh`, and `jq empty` over every JSON: all green.
All runs with `LEAN_RUN_MODEL` and `LEAN_ATTEND_MODE` scrubbed from the environment.

## Design fidelity

`not-applicable` — the spec declares no `## Design` section. This is a gate-mechanics ticket about
the design lane, not a design-armed ticket.
