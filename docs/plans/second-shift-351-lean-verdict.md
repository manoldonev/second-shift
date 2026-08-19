# lean review verdict — #351

verdict=approve
run_id: review-351-2
session_id: 6318d547-c0c2-4b09-8cf8-011f50a36c28
rounds: 2
pr: #596
reviewed_head: 4d21ccb4803cf32b8460d539ce5fc2de95720968
reviewed_patch_id: eca4c6a756e232335747b9624e5c27b1315b8e76
inherited_patch_id: 2c664a9aac8699b33aeafa54dd6aa86d29fc7ea0
inherited_from_verdict: e9467ab39680bd2bd300b072754f6a2b25b5bb99
fidelity: not-applicable
model: unknown
capabilities: pr-marker

## Review Summary

Round 2, delta range `e9467ab..HEAD` (3 files, 114 insertions), inheriting the coverage of patch
`2c664a9aac86`. Round 1's single blocker is **closed, and closed by measurement rather than by
argument**. I re-ran round 1's two surviving mutations at this head plus three more, in an
isolated worktree, and every one of them now dies on the cases that target it:

| Mutation of `intake-review.mjs` | Round 1 | This head |
| --- | --- | --- |
| `const tierMap = { ...DEFAULT_TIER_MAP }` — consumer map never read | 76/76 GREEN | **82/2** — TI2, TI8 |
| `modelFor` returns `declared` — no resolution at all, dispatches the literal `'reasoning'` | 76/76 GREEN | **78/6** — TI1, TI2, TI4, TI5, TI6, TI8 |
| `declared = INTAKE_MODEL[agentType] \|\| 'code'` — `modelOverrides` stops winning | — | **81/3** — TI3, TI5, TI7 |
| emit leg restored to a hardcoded `model: 'haiku'` | — | **82/2** — TI7, TI8 |
| *(mine)* replace-instead-of-merge tierMap semantics | — | **83/1** — TI4 |

The first four reproduce the PR body's table exactly. The fifth is mine: TI4 states merge-not-replace
(D-17) as its purpose, and it is the only case that enforces it. **Every one of the eight TI cases is
killed by at least one mutation** — there is no vacuous case in the block.

The two smaller round-1 items are closed too, both verified against the tree rather than taken:
`config-lint.sh`'s dead `SHIPPED_TIERS_JSON` fallback is gone and its removal is behavior-preserving
in the states the new comment names (missing TIER_DOC and table-less TIER_DOC both still reject a
tier-named `modelOverrides` value, byte-identical to the pre-fix commit), and the corrected
governed-set counts in `check-model-tiers.sh` are factually right — the scan's own regex returns
**13 matches in `code-review.mjs` and 3 in `intake-review.mjs`**, all genuine table entries.

**Panel: 5 selected, 5 alive, none dark.** test-coverage — the reviewer that died in round 1 and
whose domain held the blocker — ran this round and approved with no findings.

## Strengths

- **The fix is the right shape.** Case TI executes the *real* `intake-review.mjs` through the shim
  rather than re-declaring its resolution logic — which the mutation kills prove directly: a
  hand-maintained copy could not have gone red on an edit to production.
- **The round-1 control is preserved in the artifact.** The comment block records the three-run
  proof (kills on the covered file, does not kill on the uncovered one) that made this a gap rather
  than a guess, so the next reader inherits the reasoning and not just the cases.
- **The dead fallback was deleted, not re-commented.** The replacement comment states the real
  mechanism (`jq -s .` emits `[]`) *and* the safety direction — a missing authority rejects rather
  than waving through — which I confirmed holds.
- **The comment counts now carry their own decay warning.** "The count moves whenever a table gains
  an agent; it is documentation of the scan's current precision, never an assertion the script
  checks" is exactly the annotation that stops this line rotting a third time.

## Critical (must fix before merge)

_None._

## Warnings (should fix)

- **[Maintainability] `plugins/dev-pipeline/workflows/runtime-shim-selftest.mjs:503` (confidence: 95)
  — the Case TI header's non-vacuity claim is measurably false, and the PR body contradicts it.**
  The comment reads "TI1 alone survives BOTH mutations above". It survives the first (drop the
  consumer `tierMap` read) and is **killed by the second** — I measured `78 passed, 6 failed` with
  `FAIL TI1` in the list, and the PR body's own round-2 table puts TI1 in that mutation's 6-killed
  set. The true statement is narrower: TI1 survives the *dead-map-read* mutation only, which is
  still a complete argument for TI2 existing. As written it also overstates the conclusion — a
  default-only case here would not be vacuous, it would catch total resolution failure and miss the
  dead read. This is the comment that tells the next reader why TI2 is not redundant, so it is worth
  a one-line correction; it does not touch the coverage, which is correct.

## Suggestions (consider)

- **[Test coverage] `plugins/dev-pipeline/tools/config-lint.sh:43-47` (confidence: 82) — the
  empty-alphabet path now states a contract that nothing asserts.** The new comment promises that an
  unreadable or table-less `TIER_DOC` "fails a modelOverrides value naming a shipped tier … a
  missing authority rejects, it does not wave through". True today — I drove both states through
  `SECOND_SHIFT_TIER_DOC` and got the rejection — but `config-lint-selftest.sh` has no case for
  either, so a future change that made it fail *open* would be silent. The path predates this PR, so
  this is not a regression; the comment is what newly raises it to a stated guarantee.
- **[Maintainability] the PR body's AC-4 ordinal narrative is superseded, not wrong.** It is derived
  from a local advisory run on a branch that predates #593, so it argues in position-keyed ordinals.
  CI checks out `refs/pull/596/merge`, which *includes* #593 — its survivor ids are content hashes
  (`fail-open::1725a6b8fb0b`, `cmp-eq::83af93e6afa7`, …). The conclusion is identical and CI proves
  it more directly than the table does, so nothing needs redoing; a future round should just read
  the CI job rather than re-deriving ordinals by hand.

## Plan Compliance

Implementation matches the committed spec. The delta contains exactly the three round-1 items and
nothing else — no scope creep, no spec amendment. All nine bound receipt rows remain carried
verbatim, zero departures.

## Per-AC scoring

| AC | Verdict | Basis |
| --- | --- | --- |
| **AC-1** | **satisfied** | Both surviving dispatch ladders now have executing cases. Five mutations of `intake-review.mjs` measured at this head, each killed by the cases targeting it (table above); all eight TI cases non-vacuous. Suite **84 passed, 0 failed** clean. Round-1's blocker does not survive. |
| **AC-2** | satisfied | `config-lint-selftest.sh` green in CI's `lint-and-selftests` at this head. The one production line removed was proven dead in round 1 and its removal probed behavior-identical here across normal / missing / table-less `TIER_DOC`, including under `set -euo pipefail` (a failing parse aborts the script, rc=1 — it cannot yield a vacuous pass). |
| **AC-3** | satisfied | Comment-only edits; `check-model-tiers.sh` exits 0 against the real tree and `check-model-tiers-selftest.sh` is green in CI. The corrected counts are factually right: the scan's own regex yields 13 + 3 = 16, all genuine table entries. |
| **AC-4** | satisfied | Settled by CI at this head, not by the local advisory run: **`mutation-sweep-pr` green** — 21 mutants, **23 verdicts computed** (not a zero-verdict pass), `config-lint.sh` 9/7/2 and `check-model-tiers.sh` 12/7/5, and every survivor id present in `tools/mutation-baseline.tsv`. No baseline row is orphaned and no catalog anchor drifted. |
| **AC-5** | satisfied | `Changelog: none` on `4d21ccb`, and the consumer-visible changelog on the code commit is unchanged. No default moved: the delta touches one dead line and two comments. |
| **AC-6** | satisfied | Inherited by reference to the round-1 record — no doc file is in this round's delta, and round 1 verified each clause against the tree. |

**Fidelity:** `not-applicable` — the spec carries no `## Design` section, the repo configures no
`design.provider`, and the delta has no rendered surface. Step 5b does not arm.

## Pre-existing gaps (not blocking this PR)

- The mutation sweep's WARN that `config-lint-selftest.sh` measures 6s against the 5s bar with no
  `tools/mutation-slow-suites.tsv` row is correctly flagged in the PR body rather than taken
  silently — adding that row would drop `config-lint.sh` out of the PR-lane sweep entirely, which is
  a coverage trade, not a cleanup. It did not fire in CI's run at this head. Leaving it for a
  deliberate decision is the right call.

## Suppressed (below confidence threshold)

- `config-lint.sh:44` (45, security-reviewer) — "if the parse pipeline exited non-zero, `--argjson`
  would error and yield an empty `ERRORS` (vacuous pass)". Checked and **unfounded**: `set -euo
  pipefail` aborts on a failing command substitution before the next `jq` runs (probed: rc=1, the
  echo after it never executes), and the deleted line sat *after* that assignment so it could not
  have helped either way.
- `docs/plans/second-shift-351-lean.md` (65, scope gate) — key landed at `reviewers.tierMap` rather
  than the ticket's `models.tierMap`. Not a scope miss: the ticket wrote "or similar" and OR-1 flags
  it as a reversible open region. Closed by D-3.
- `tools/mutation-baseline.tsv` (70, scope gate) — the reviewer did not re-run the sweep to confirm
  the ordinal argument. Settled above by CI's own run at this head.

## Verdicts

| Reviewer | Verdict | Findings | Confidence Range |
|---|---|---|---|
| Scope Completeness | Fail (gate finding overridden — see below) | 1 | 88 |
| Security | Pass | 0 | — |
| Complexity | Pass | 0 | — |
| Maintainability | Pass | 0 | — |
| Test Coverage | Pass | 0 | — |

a11y + design-fidelity not routed: no changed path matched `stageParams.webComponentGlobs`
(unset → `apps/web/**/*.{tsx,jsx}`). Performance not selected — round 2 ran the reduced lineup
(prior-blocker domain + fix-touched scope + the unconditional scope gate).

**Scope gate disposition — overridden for the second round, on re-verified evidence.**
`scope-completeness-reviewer` again returned FAIL (conf 88) on issue #351's scope bullet 1
("promote abstract tiers to first-class tokens in agent frontmatter"), correctly observing that all
25 `model:` frontmatter lines still carry vendor tokens and that the deferral lives only in the
committed plan. It is **overridden, not dismissed.** I read the row in the receipt itself rather
than the spec's restatement of it: `.claude/pipeline-state/351-ledger.md` row **D-1 is
`user-answered` / `intent`** and states in terms that it AMENDS that bullet — `model:` in
`agents/*.md` is a harness-owned key, so an abstract token there is an unrecognized value in someone
else's key. A user-answered pre-flight ledger row is binding input that supersedes the issue body,
and review-lean's contract makes the committed spec the definition of done. The gate structurally
cannot see this: the receipt is gitignored and host-local, so it reads every ledger-carried
amendment as plan-only.

**This will recur on every future round and on any re-review, and the durable fix is a one-line
issue-body edit** — amending #351's scope bullet 1 with D-1's rationale. That is a human-authority
action, so it is named here rather than taken.

**Ready to merge?** Yes.

**Reasoning:** No blockers. Round 1's coverage blocker is closed by construction and verified by
five directed mutations at this head, all six ACs score satisfied, the full panel ran with no dark
reviewer, and CI is green on the substantive lanes — `lint-and-selftests`, `selftests (macos, bash
3.2)`, and a `mutation-sweep-pr` that computed 23 real verdicts with every survivor baselined. The
one warning is an inaccurate sentence in a test-file comment; it misstates a measurement without
weakening the coverage it justifies. The single dissenting verdict is the scope gate, overridden on
a `user-answered` ledger row I verified in the receipt.
