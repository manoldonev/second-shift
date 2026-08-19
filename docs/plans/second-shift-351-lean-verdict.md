# lean review verdict — #351

verdict=needs-work
run_id: review-351-1
session_id: 949790fb-0f8c-4e2d-99fb-12a9c2a1d899
rounds: 1
pr: #596
reviewed_head: 1085cd9b48e947528b26978c303025f6d2ca28b7
reviewed_patch_id: 2c664a9aac8699b33aeafa54dd6aa86d29fc7ea0
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown
capabilities: pr-marker

## Review Summary

Round 1, full branch range `eb3046e..HEAD` (chain root — nothing to inherit). The indirection
itself is well built: one resolution path per engine, merge-not-replace tierMap semantics, the
lockstep held against the SHIPPED default so a consumer `tierMap` can never red the commit hook,
and the two-layer alphabet design (enum-anchored extraction takes the variable; the counter-scans
stay unrestricted) preserved deliberately. Consumer-visible defaults are bit-for-bit unchanged, and
I verified that directly rather than taking the claim: `check-model-tiers.sh` exits 0 against the
real tree, and `structured-emitter.md:5` is `haiku`, which is what `emit` resolves to.

**One blocker, and it is a coverage blocker, not a design one.** The governed set the spec itself
declares is TWO files / THREE dispatch shapes. `runtime-shim-selftest.mjs`'s new Case T executes
only ONE of the two ladders. `intake-review.mjs` carries a byte-for-byte copy of the same
`tierMap` merge and the same `modelFor`, and nothing anywhere executes it.

`[Coverage gap]` `review-toolkit:test-coverage-reviewer` went dark (`died-after-retry` —
turn-budget, no text on either attempt), so test adequacy was not covered by the panel. That is the
exact domain the blocker below sits in; it was found by direct probe in this session instead.

## Strengths

- **The T1/T2 pairing is the right instinct, and the PR body names why.** Dropping the `tierMap`
  read leaves T1 green because the shipped default and the old hardcoded token are the same string
  by design; only T2's retarget separates them. That is a real non-vacuity argument, not a count.
- **`check_inline_default_map` checks BOTH directions.** A tier the authority declares and an
  engine omits would silently fall through to the engine's own default at dispatch, and the reverse
  scan catches it. Two of the 18 guard cases pin exactly that.
- **The duplication is pinned rather than regretted.** The awk parse now lives in two scripts and is
  anchored as `tier-alphabet-parse` in `scripts/lockstep-manifest.tsv`; `check-lockstep-pairs.sh`
  reports 23 pairs / 0 failed with the new row live. The unanchorable half was *extended in place*
  on the existing `reviewers` DROPPED entry instead of a second entry being invented.
- **Schema honesty.** The `additionalProperties` enum moved to `tierMap` (where the closed set is
  genuinely expressible) and `modelOverrides` degraded to `string`, with the selftest's enum-mirror
  check re-pointed at the surviving enum so the mirror is still driven from both sides.

## Critical (must fix before merge)

- **[Test coverage / Cross-cutting] `plugins/dev-pipeline/workflows/intake-review.mjs:153-157`
  (confidence: 97) — the intake dispatch ladder's tier resolution has ZERO executing coverage.**
  Every `opts.model` assertion in `runtime-shim-selftest.mjs` (H1, T1–T8, Q1, Q3) runs through
  `runCodeReview`. Not one runs through `runIntake`. Probed in an isolated worktree at this head,
  both directions:

  | Mutation | Suite result |
  | --- | --- |
  | `intake-review.mjs`: `const tierMap = { ...DEFAULT_TIER_MAP }` (consumer `tierMap` never read) | shim **76/76**, tiers **18/18** — SURVIVES |
  | `intake-review.mjs`: `modelFor` returns `declared` (no map resolution at all — dispatches the literal string `reasoning`) | shim **76/76**, tiers **18/18** — SURVIVES |
  | *control:* the identical first mutation on `code-review.mjs` | shim **74 passed, 2 failed** — KILLED |

  The control is what makes this a finding rather than a guess: the technique kills on the file that
  is covered and does not kill on the file that is not. The second mutation is not subtle — it makes
  the intake fan-out dispatch a tier name as if it were a model, i.e. the feature is completely
  inert on half the governed set — and the whole suite stays green.

  `check-model-tiers.sh` does not close this: it holds the inlined `DEFAULT_TIER_MAP` literal and
  the table's tiers against the authority statically. It never executes the runtime read of
  `config.reviewers.tierMap`, which is where both mutations live.

  **AC-1 scoring.** Its named oracle is `runtime-shim-selftest.mjs`, "cases per surviving dispatch
  ladder" — plural, and the spec's own edit-surface table lists `intake-review.mjs:15` and its
  `:243` emit leg as two of the three governed shapes. One ladder covered is not that.

  **Remedy is small.** `runIntake(behaviors, argsOverride)` already takes a `config` override
  (`runtime-shim-selftest.mjs:408-415`), so the T2 / T3 / T4 / T8 shapes port over roughly as-is
  against `review-toolkit:spec-reviewer` (`reasoning`) and the intake emit leg. Please keep a
  retargeting case among them — a default-only case is the one that stays green under both
  mutations above.

## Warnings (should fix)

_None._

## Suggestions (consider)

- **[Maintainability] `plugins/dev-pipeline/tools/config-lint.sh:44` (confidence: 82) — the
  `SHIPPED_TIERS_JSON` fallback is unreachable.** `jq -s .` on empty stdin emits `[]`, which is a
  non-empty string, so `[[ -n "$SHIPPED_TIERS_JSON" ]]` is always true and the
  `|| SHIPPED_TIERS_JSON='[]'` arm never runs. Verified: `printf '' | jq -R . | jq -s .` → `[]`.
  Harmless — the value it would assign is the value already there — but it reads as the
  empty-alphabet guard and is not one. Either drop it or re-comment it as belt-and-braces.

## Plan Compliance

Implementation matches the committed spec's design. All nine bound receipt rows are carried
verbatim, zero departures, and I spot-checked D-1 against the receipt at
`.claude/pipeline-state/351-ledger.md:25` — it is `user-answered` and amends the ticket in the
terms the spec restates. Scope creep: none. The one gap is oracle coverage, scored under AC-1.

## Per-AC scoring

| AC | Verdict | Basis |
| --- | --- | --- |
| **AC-1** | **unsatisfied** | Oracle covers one of two surviving dispatch ladders. Two total-failure mutations of `intake-review.mjs` survive the full suite; the same mutation on `code-review.mjs` kills 2 cases. See Critical. |
| **AC-2** | satisfied | `config-lint-selftest.sh` green. `valid-tier-named-override.json` (tier-named override accepted), `invalid-override-unknown-tier.json` (`"reasonin"` typo still rejected against a live tierMap — typo detection survives the schema weakening), `invalid-bad-tiermap-value.json` (`"gpt-4"` rejected), and the enum mirror re-pointed at `tierMap` so both sides of the surviving enum are driven. |
| **AC-3** | satisfied | `check-model-tiers-selftest.sh` **18/18**, including custom-alphabet lockstep, `fable`-in-a-shipped-MAP → UNKNOWN-MODEL, the counter-scan judging against the PARSED alphabet rather than a constant (non-vacuity of the unrestricted layer), and consumer-`tierMap`-retargeting → exit 0. |
| **AC-4** | satisfied | Settled by CI, not by the advisory local run: `mutation-sweep-pr` is **green on this head** — 21 mutants, 23 verdicts computed, `config-lint.sh` 9/7/2 and `check-model-tiers.sh` 12/7/5, every survivor already baselined and catalog anchors intact (drift would have red the lane). `check-lockstep-pairs.sh` 23 pairs / 0 failed; `:58`'s DROPPED entry was extended in place rather than duplicated, and the newly anchorable half got its own `tier-alphabet-parse` row. |
| **AC-5** | satisfied | `Changelog:` trailer present on the code commit. Defaults unchanged, verified against the tree rather than the claim: `check-model-tiers.sh` exits 0 with `structured-emitter.md:5 = haiku` ⇔ `emit → haiku`, and T1/T6 pin `code → sonnet` / `emit → haiku`. `check-frozen-files.sh` clean. |
| **AC-6** | satisfied | `model-tiering.md` carries the `Dispatch token` column and the `emit` row and is genuinely parsed (an UNPARSEABLE-ALPHABET case proves the dependency). The stale "five `.mjs` dispatch tables" prose is corrected. `docs/extension-points.md` EP-4 and `onboard/SKILL.md` state the D-2 union. The clause about `stall-probe.mjs`'s "six named tables" comment was **already true at `eb3046e`** — it reads "two named map tables" at base — so that half is vacuous, not violated. |

**Fidelity:** `not-applicable` — the spec carries no `## Design` section, the repo configures no
`design.provider`, and the diff has no rendered surface. Step 5b does not arm.

## Pre-existing gaps (not blocking this PR)

- `plugins/review-toolkit/scripts/check-model-tiers.sh:428` still says the MAP scan matches "genuine
  table entries across all three MAP files today (18/18)", and `:442` says the inline-literal scan
  "Runs over ALL FIVE parsed workflow files". Both are wrong post-#574/#584 (two files remain) and
  both were **already wrong at `eb3046e`** — neither line is in this diff, so this is not a
  regression. Flagged because this PR corrected the same class of stale count in the file header,
  which makes these two the natural sweep-up; comment-only, so fixing them re-keys nothing.

## Suppressed (below confidence threshold)

- `check-model-tiers.sh:~250` (40) — a tab/newline inside a `reviewers.tierMap` value could inject a
  row into the TAB-separated effective map. Operator-authored local file, no untrusted writer.
- `config-lint.sh:21` (35) — `SECOND_SHIFT_TIER_DOC` lets the environment redirect the parsed doc.
  Read-only parse of a local path, matching the repo's existing env-override idioms.

## Verdicts

| Reviewer | Verdict | Findings | Confidence Range |
|---|---|---|---|
| Scope Completeness | Pass (gate finding overridden — see below) | 2 | 88–92 |
| Security | Pass | 0 | — |
| Performance | Pass | 0 | — |
| Complexity | Pass | 0 | — |
| Maintainability | Pass | 1 | 82 |
| Test Coverage | **Dark (no output)** | — | — |

`a11y` + design-fidelity not routed: no changed path matched `stageParams.webComponentGlobs`
(unset → `apps/web/**/*.{tsx,jsx}`).

**Scope gate disposition.** `scope-completeness-reviewer` returned FAIL on issue #351's scope bullet
1 ("promote abstract tiers to first-class tokens in agent frontmatter"), correctly observing that no
`agents/*.md` is in the diff and the deferral lives only in the committed plan. That finding is
**overridden, not dismissed**: receipt row **D-1 is `user-answered`** and states in terms that it
AMENDS that bullet — `model:` in `agents/*.md` is a harness-owned key, so an abstract token there is
an unrecognized value in someone else's key. A user-answered pre-flight ledger row is binding input
that supersedes the issue body, and the committed spec is the definition of done. The gate could not
see the receipt (it is gitignored and host-local), which is why it read the deferral as
plan-only. Its second finding is the pre-existing comment staleness recorded above.

**Ready to merge?** No.

**Reasoning:** One blocker, on AC-1: half the governed set — `intake-review.mjs`'s dispatch ladder —
has no executing oracle, and a mutation that makes the feature entirely inert there passes the full
suite. The design, the guards, the docs and the re-baseline are sound and need no rework; the fix is
additional shim cases against `runIntake`, not a change to the implementation.
