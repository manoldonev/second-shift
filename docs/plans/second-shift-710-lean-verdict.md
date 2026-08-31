# lean review verdict — #710

verdict=needs-work
run_id: review-710-1
session_id: 0a5cbd89-76d8-4b66-8fca-a7928c0f263c
rounds: 1
pr: #741
reviewed_head: 8a597d104bea73be635e5d70cdd0e7d5865a9288
reviewed_patch_id: c653fba65d61c5986d491a434e07d8afad4a5ec6
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: opus
capabilities: pr-marker

Round 1 — full branch range `7e82408f..8a597d10` (12 files, +686/-27). No prior round to inherit
from; `bash G delta 710` printed the whole branch diff.

The design of this slice is right and the tests are the good kind — every `(dpr*)` case drives a
real fixture tree through production's own writer and reader, and none of them mirrors the
gate's arithmetic. Two CI lanes are nevertheless red at this head, both branch-caused, both
correctness lanes, and neither is mentioned by the PR body's Verification section.

## Blockers

**B1 — `lint-and-selftests` is RED, and it took the whole job's later coverage down with it.**
`plugins/dev-pipeline/skills/build-lean/scenario-liveness-selftest.sh:1235`. CI's Ubuntu package
is **shellcheck 0.9.0** and emits, on the new fixture helper:

```
line 1229:  lean_dplanrev_sync
            ^--- SC2119 (info): Use lean_dplanrev_sync "$@" if function's $1 should mean script's $1.
line 1235:  lean_dplanrev_sync() { # lean_dplanrev_sync [verdict]
            ^-- SC2120 (warning): lean_dplanrev_sync references arguments, but none are ever passed.
```

Neither code is in the job's `-e SC1091,SC2015,SC2181` exclusion list. `lean_dplanrev_sync` takes
an optional `[verdict]` that its single call site (inside `lean_dplan_sync`) never passes — the
sibling `dplanrev_sync` in `lean-gate-selftest.sh` escapes the warning only because `(dpr3)` and
`(dpr4)` do pass one.

The PR body's "shellcheck … green" is honestly held and still wrong for CI: **local shellcheck
0.11.0 is clean on the same recipe** (re-measured here), so this is the known local/CI version
skew, not a mistake in reading the output.

The reason this is not a cosmetic lint red: shellcheck is the **first** step of
`lint-and-selftests`, so every later step reported `skipped` at this head — the full Linux
selftest sweep, JSON validation, actionlint, contract lockstep blocks, the reserved exit-3 lane
set, eval-harness model identity, capability parity, the namespace direction check, **and
`check-gate-buckets.sh`, which is AC-7's own oracle**. CI has verified essentially nothing about
this branch. I ran those locally instead (see Verified here), but a green local run is not the
lane the merge boundary reads.

Fix: `lean_dplanrev_sync pass` at the call site, or drop the unused parameter.

**B2 — `selftests (macos, bash 3.2)` is RED: `tools/prose-blockers-selftest.sh` (rc=1).**
The failing case is `this repo's own tree is fully dispositioned`. Reproduced at this head:

```
$ bash tools/prose-blockers.sh check
[prose-blockers] census: 26 construct(s) over 51 file(s); record: 47 row(s).
[prose-blockers] UNDISPOSITIONED — in the tree, absent from docs/prose-blocker-triage.tsv:
  pb-1c5740d4  plugins/design-toolkit/skills/figma-faithful/SKILL.md:207
  pb-cbe0e255  plugins/dev-pipeline/skills/build-lean/SKILL.md:27
[prose-blockers] STALE — the row expects a surviving construct, the tree has none:
  pb-0c42ee3f  (pointer-kept)
```

The same command on the base `7e82408f` reports `✓ zero undispositioned constructs` over a
25-construct census, so this is the branch's: prose-blocker ids are content-derived, and the
AC-8 edits to `figma-faithful/SKILL.md` step 7 and `build-lean/SKILL.md` step 6 re-keyed two
blocking constructs and orphaned `pb-0c42ee3f`. `docs/prose-blocker-triage.tsv` needs the re-key
(and the census grew 25 → 26, so one of the two is a genuinely new construct, not only a move).

Neither blocker is a merge-boundary POLICY refusal — `lint-and-selftests` and `selftests` are the
lanes the review contract names as evidence about the code.

## Per-AC scoring

| AC | Verdict | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | `design_plan_gate` → `design_plan_review_gate` runs at `cmd_3_render:4448`, ahead of the `LR_COMMAND` check and every render. `(dpr1)` pins `rc=1`, `renders=0`, `attempts=0`; the composed `(lean-design-plan-review)` leg pins `rcs=111`, `attempts=0`, no renders dir. |
| AC-2 | satisfied | `plan_patch_id` gains `":(exclude)$PLAN_REVIEW_MANIFEST_REL"` (`lean-gate.sh:1011`). `(dpr2)` first half proves committing the record does not stale it; second half proves a moved tree does. |
| AC-3 | satisfied | `(dpr3)` reds on `block`, quotes `B1: the 16px sibling gap`, and asserts the `## Findings` heading is **not** quoted; `(dpr4)` proves `fix-and-go` reaches the render pass. |
| AC-4 | satisfied | `cmd_plan_review` stamps `reviewed_plan_from` from `plan_patch_id HEAD`, never from a flag. `(dpr8)` covers the enum refusal, the required `--summary-file`, and writer/reader agreement on the stamped value. |
| AC-5 | satisfied | `grep -rn 'autonomous lane' plugins/design-toolkit` → empty at this head. |
| AC-6 | satisfied | 8 catalog rows; all 8 sed programs verified to apply cleanly at this head under `sed -E`, each changing exactly one line (no anchor drift). Liveness scenario extended. Commit verb `feat(dev-pipeline):`; `check-changelog-trailer.sh` green. |
| AC-7 | satisfied | `check-gate-buckets.sh` → `✓ 311 enumerated refusal site(s) across 5 file(s), all bucketed by 167 register row(s)`. **Verified locally only** — CI's run of this step was skipped behind B1. |
| AC-8 | satisfied | `build-lean/SKILL.md` step 6 states the dispatch, the `bash G plan-review` recording obligation, and that both refusals land before the render pass. `docs/live-render.md` replaces the operator-only paragraph with the lane contract, including the staleness and `block` arms. |
| AC-9 | satisfied | #739 is OPEN, titled for the claude-design plan-review gap, and cited at `lean-gate.sh:3333` in the comment block directly above `design_family_plan_reviewer()`. |

All nine are satisfied on content. The verdict is `needs-work` on the two red lanes, not on an
unmet AC.

## Verified here (not by CI at this head)

- `lean-gate-selftest.sh` — **all green**, including all 11 `(dpr*)` assertions.
- `scenario-liveness-selftest.sh` — **83 passed, 0 failed**, matching the PR body. (A first run
  showed 3 failures in `(lean-override)` / `(lean-design-override)`; that was `LEAN_ATTEND_MODE`
  leaking from my own shell, not the branch. Re-run with the env scrubbed: clean.)
- Three of the eight new catalog mutants applied into isolated worktrees at this head and scored
  by case id against the same-env clean baseline: `stale-accepted` → adds `(dpr2-stale)`;
  `block-ignored` → adds `(dpr3)`; `malformed-waved` → adds `(dpr5)` **and** `(dpr6)`. All three
  killed, by the cases the PR named. The other five were checked for anchor resolution only —
  `mutation-sweep-pr` grades none of them, as the PR body says.
- `check-lockstep-pairs.sh` (30 anchors, 0 failed), `check-gate-buckets.sh`,
  `check-lane-class-doc.sh`, `check-eval-model-identity.sh`, `check-reviewer-references.sh`,
  `check-frozen-files.sh origin/main`, `check-changelog-trailer.sh origin/main`, `jq empty` over
  every JSON: all green.
- `-lean-plan-review.md` does not collide with `check-lean-chain.sh`'s three END-anchored
  suffixes (`-lean.md`, `-lean-verdict.md`, `-lean-renders.md`), so the artifact arm's first-match
  spec scan cannot pick it up. The suffix reasoning in the spec holds.

## Strengths

- The `header_key` trap is correctly paid twice. `reviewer:` is stamped BARE at the writer and
  compared BARE at the reader, both derived from the single `design_family_plan_reviewer()`, and
  `writer-qualifies-reviewer` is a catalog row rather than a comment. Writer and reader cannot
  drift apart because there is one derivation.
- `design_family_plan_reviewer()` is deliberately **outside** the `lean-design-provider-family`
  lockstep block, with the reason stated: nothing at the merge boundary reads the plan or its
  review, so a copy in `check-lean-chain.sh` would read as coverage this repo does not have.
  `check-lockstep-pairs.sh` agrees.
- `(dpr7)` is the case that keeps the family arm from being a formality — it leaves the previous
  record in the tree on purpose, so a gate that mandated the record universally is distinguishable
  from one that scopes it to figma. Most panels would have skipped that case.
- `(dpr6)` exists because `(dpr5)` neuters the verdict enum: without it, a gate that stopped
  checking `reviewer:` entirely would still red at the enum arm and look covered.

## Non-blocking

- **AC-3, primitive vs gloss.** The ticket's guess-point 7 names `block_milestone` and glosses it
  "(spends an attempt)"; in this gate `block_milestone` spends none. The spec adjudicates it in
  writing ("The named PRIMITIVE wins"), the code follows the named primitive, and `(dpr3)` pins
  `attempts == 0` — so AC-3 is satisfied. Flagged only so the human confirms the primitive, not
  the parenthetical, was the intent.
- **An unresolvable design family passes this gate quietly.** `design_plan_review_gate` computes
  `fam="$(design_family < …)"` and, on empty, takes the declined-mandate branch and returns 0 —
  emitting `the '' design family ships no plan-stage reviewer`. Only reachable from an armed spec
  whose handoff link names no known host, which milestone 4 refuses separately, so this is a
  suggestion rather than a hole. Consider distinguishing "family did not resolve" from "family has
  no plan reviewer".
- **Writer-side arms are thinly covered.** `cmd_plan_review` has seven `envfail` branches;
  `(dpr8)` drives two of them plus the happy path. The five untested arms (lane not armed, family
  declined at the writer, plan absent, empty-vs-missing summary file, missing `--model`) are all
  usage errors and none is merge-blocking, and the reader-side gate is thoroughly covered — but
  the `--model` arm in particular falls back to `LEAN_RUN_MODEL`, which is exactly the env var
  known to leak into suites, so a future test of that arm needs a scrubbed env to mean anything.
- **`build-lean/SKILL.md` step 6 templates the agent name** as
  `design-toolkit:<provider>-faithful-plan-reviewer`. For `claude-design` that expands to an agent
  that does not exist, and it is not even the name #739 discusses (`design-faithful-plan-reviewer`).
  The gate's own refusal names the exact agent, so the build session is not misled in practice.
- Two security findings below the confidence threshold, both recorded and both agreed with as
  non-issues: a newline-bearing `--model` could emit an extra header line (the calling session can
  already author the file directly), and `plan_review_first_finding` echoes up to 240 bytes of a
  repo-local committed artifact into a refusal message unescaped.

## Panel

Six reviewers selected, six alive, none dark. security / performance / maintainability /
complexity: approve, no findings. test-coverage: approve-with-nits (1 minor, folded in above).
scope-completeness: approve, no unsatisfied scope item (1 minor, folded in above). a11y and the
design-fidelity dimension were not routed: no changed path matches the web-component surface
(`stageParams.webComponentGlobs` is unset, so the shipped default `apps/web/**/*.{tsx,jsx}`
applies). db, pipeline and unit-test-mutation were not triggered.

## Design fidelity

`not-applicable` — the spec declares no `## Design` section. This is a gate-mechanics ticket about
the design lane, not a design-armed ticket.
