# lean review verdict — #357

verdict=approve
run_id: review-357-1
session_id: a9964d74-d8e5-4614-b8a7-878add6dd412
rounds: 1
pr: #429
reviewed_head: bdba892bf0551d634191e5de579f4bc7fd8de702
reviewed_patch_id: 9dd2656d92317c7307e74b141e05e969d5174070
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown

Round 1 — full branch diff (`a2b158f..HEAD`, 9 files, +505/-14), nothing inherited.
Panel: 7 reviewers dispatched via `code-review.mjs`, 7 returned, **none dark**. Verdict: **approve**.

No blockers. Every `AC-n` in `docs/plans/second-shift-357-lean.md` is satisfied; the three warnings
and suggestions below are coverage/accuracy observations, none of which withhold merge readiness.

## Per-AC scoring

| AC | Score | Evidence (verified in this checkout) |
| --- | --- | --- |
| AC-1 tier map | satisfied | `TIER_FAMILY_MAP` is a script constant; alphabet is `reasoning`/`code`/`emit`; no schema, config-lint or `configVersion` file is in the diff at all. `tier_of` is total by construction: non-string ⇒ `unknown`, no family match ⇒ `unknown`. |
| AC-2 tier as bucket key | satisfied | `group_by([.label, .tier])`, each row keeps `models`. Rollup stays total — `XV_SUM == XV_TOT == 80` cents and the zero-cost model-less group is still a row (`XV_CR == 1`). Ordering: see W-1 for the half with no kill criterion. |
| AC-3 Tier column + render filter | satisfied | Both layouts carry it; the zero-cost/named-model row is kept and the zero-cost/model-less row omitted, each with its own assertion. Rendered rows sum to the rendered total *structurally*, not just on this fixture: the filter's own predicate means a dropped row has `cost_usd == 0`. |
| AC-4 `tiers` on the log row | satisfied | Top-level `tiers` beside an unchanged `models`. Downstream-compat claim checked at the source: `stage-envelopes.sh:256-266` maps each row to `{label, usd}` then `group_by(.label) \| map(add)`, so the extra (label, tier) rows fold and never reach `.models`/`.tier`. It is the only reader in the tree. |
| AC-5 cross-vendor fixture | satisfied | `cross-vendor.jsonl` + `state-cross-vendor.json`: three covered families, one uncovered id, one cost datapoint with no `model` attribute, plus the two zero-cost rows the render filter needs. README lists both and what they pin. |
| AC-6 the assertions | satisfied | `cost-block-selftest.sh` 54/54 green, run here. Each clause of AC-6 has a named case. |
| AC-7 existing fixtures as oracle | satisfied | `A_REASONING == 100` (opus) and `B_CODE == 45` (sonnet, across three stage labels), plus the state-less block's tier cell pinned to exactly `reasoning`. |
| AC-8 header + `--help` range | satisfied | Header ends at line 55, first code at 57, `sed -n '2,55p'`. The oracle is derived by `awk` from the file, so it cannot rot. Off-by-one repaired. See S-2 for one trivial equivalent mutant. |
| AC-9 mutation obligations | satisfied | Re-derived independently, by site rather than by survivor id. All six operators' site counts are unchanged base→head (`fail-open` 0, `cmp-eq` 14, `cmp-z` 26, `logic` 35, `detector` 1, `default` 10) and the matched-line lists are byte-identical for `cmp-eq`/`logic`/`detector`/`default`. All four baselined rows probed with the flip applied verbatim from `mutation-operators.tsv`: `cmp-z::1` **killed** (correctly removed), `default::2` / `detector::1` / `logic::2` **survived** (correctly kept). See S-1 on the PR body's wording. |
| AC-10 scope boundary | satisfied | The 9 changed paths are exactly the declared set. See W-2 on how that set was arrived at. |
| AC-11 named fallback guard | satisfied | `cost-block-tier-unknown-fallback` applied verbatim → suite `rc=1`, 4 failing assertions. The row dies. |
| AC-12 milestone-3 false red | satisfied | The premise reproduces: the **base** suite reds on exactly `(m1b)` and `(p5)` with `LEAN_RUN_MODEL` exported (`rc=2`) and is green without it (`rc=0`). With the fix it is `rc=0` **both** ways. `lean-gate.sh` is untouched, so no ordinal moves. The "only `(m1c)` reds under a hardcoded stamp" clause is verified by inspection, not execution — see S-3. |

## Findings

| # | Severity | Where | Finding |
| --- | --- | --- | --- |
| W-1 | Warning | `pipeline-cost-block.sh:411` | The composite sort key `[labelPriority, tierPriority]` has no killer for its **element order**. Swapping it to `[tierPriority, labelPriority]` survives every assertion in the diff: `XV_TIERS` and `XV_MODELS` both filter to `select(.label=="Implementation")` first, and within one label both key orders produce the same ascending-tier sequence; the rendered-row greps are line-anchored and order-insensitive. The mutant interleaves rows from different stage labels by tier in the PR table (`Implementation/code`, `Doc Update/code`, `Implementation/emit`, …), contradicting the header's "the existing stage-label order, then a deterministic tier order". Confirmed by hand. Impact is cosmetic row order only — no cost or classification effect — and no generic operator in `mutation-operators.tsv` produces this flip, so the sweep would never surface it. Not a blocker: AC-2's asserted property ("rows sharing a label never permute") does hold under the mutant, and the dropped-secondary-key mutant — the likelier regression — **is** killed by `XV_TIERS`. |
| W-2 | Warning | `docs/plans/…-357-lean.md` AC-12, `lean-gate-selftest.sh` | AC-12 entered the spec in `bdba892`, the same commit as the fix it authorizes — it was not in the first spec commit (`47d176c`, AC-1…AC-10). The pre-flight receipt's D-11(b) lists `LEAN_RUN_MODEL` and the progress/verdict `model:` key as out of scope, and the ratified intake comment's file list excludes `lean-gate-selftest.sh`. Scored a warning, not the "spec amended after the fact" blocker, on four grounds: no pre-existing AC was weakened or removed and AC-1…AC-10 are all met; run-lean step 4 explicitly permits amending the AC set before milestone 5 when scope changes; the change is **test-only** (`lean-gate.sh` is untouched, and `(m1c)` strictly adds coverage); and the blockage is real — I reproduced the base suite failing on two cases, so without it milestone 3 cannot go green on any machine where a lean run stamps its model honestly. It is disclosed in three places. What is left is the human's call: D-11(b) is a **ratified** receipt line, and this run resolved a conflict with it rather than routing an intent-gap record. Worth an explicit nod on the issue or at merge. |
| S-1 | Suggestion | PR body §3 | "All four operators' site enumerations are byte-identical to the base branch (26/10/1/35 sites)" is imprecise for `cmp-z`: its ordinal-1 site is the `-h\|--help)` line, whose **content** changed (`sed -n '2,26p'` → `'2,55p'`). The counts and the ordinal→site mapping are unchanged, so the operative conclusion (no ordinal was re-keyed) stands, and the PR states separately and correctly that `cmp-z::1` is now killed. Wording only. |
| S-2 | Suggestion | `cost-block-selftest.sh` (D-8 block) | The derived-oracle `--help` assertions kill `2,54p` and `2,57p`, but **not** `2,56p`: line 56 is the blank separator and `$(…)` strips the trailing newline, so `HELP_LAST` still reads line 55. Equivalent-mutant territory, not a real gap. |
| S-3 | Suggestion | `lean-gate.sh:1959` / `lean-gate-selftest.sh:1127` | The **verdict**-record model stamp has exactly the one-directional coverage `(m1c)` was added to close for the progress stamp: `(p5)` asserts only `model: unknown`, so a hardcoded `unknown` at `:1959` passes every case. Out of AC-12's stated scope (it names `ensure_progress_file()`), and #347 owns that field per D-11(b) — noted for whoever picks that up. Related: I could not execute the "only `(m1c)` reds under a hardcoded stamp" probe (the in-place edit to the plugin file was permission-denied), so that clause is verified by reading all three `model:` assertions instead: `(m1b)` and `(p5)` both assert `model: unknown` and are unaffected by a hardcoded `unknown` at `:631`, leaving `(m1c)` as the only case that reds. |

## Verification run in this checkout

- `cost-block-selftest.sh` — 54 passed, 0 failed.
- Full selftest sweep, **no `SKIP_STRESS`**, `env -u CLAUDE_CODE_SESSION_ID -u RUN_ID -u LEAN_RUN_MODEL -u GH_BOT` — `rc=0`, zero failing assertions across the discovered suites.
- `lean-gate-selftest.sh` — green with `LEAN_RUN_MODEL` exported **and** unset; the same suite at the base commit reds on `(m1b)`/`(p5)` with it exported.
- Mutation probes — 5 applied verbatim from `mutation-operators.tsv` / `mutation-catalog.tsv`, results as tabled under AC-9 and AC-11. Tree restored clean after each.
- Merge-boundary design arm — the spec carries no `## Design` section, so `check-lean-chain.sh`'s `design_armed` reads not-armed and `fidelity: not-applicable` is the correct value, not a default taken by omission. No design provider is configured for this repo.

## Panel verdicts

| Reviewer | Verdict | Findings | Confidence |
| --- | --- | --- | --- |
| Scope Completeness | Pass (approve-with-nits) | 1 | 92 |
| Security | Pass | 0 | — |
| Performance | Pass | 0 | — |
| Complexity | Pass | 0 | — |
| Maintainability | Pass | 0 | — |
| Test Coverage | Pass | 0 | — |
| Unit Test Mutation | Pass (approve-with-nits) | 2 | 80–85 |

`a11y-reviewer` and the design-fidelity dimension were **not routed**: no changed path matched
`stageParams.webComponentGlobs` (unset ⇒ `apps/web/**/*.{tsx,jsx}`). `db-reviewer` and
`pipeline-reviewer` had no trigger. Not-selected, not dark.

## Strengths

- **The defect was re-framed to the right one.** The issue's title points at fixture model
  strings; the run identified the absent kill criterion as the actual debt (`grep -c model`
  returned 0 across 465 lines) and kept the existing Anthropic ids so they become the shipped
  map's oracle. Placeholder-izing them would have matched the title and left the map with no
  oracle at all.
- **Assertion design over assertion count.** The `unknown` bucket's two amounts are deliberately
  10¢ and 5¢, so one number separates three distinct failure modes (both present / attribute-less
  datapoint dropped / unmatched id mis-tiered). Likewise the fixture puts all five cost datapoints
  in one stage window so tier is the only axis that can split them.
- **The easy-and-wrong fix has its own killer.** Moving the render filter into the rollup would be
  the natural shortcut; `XV_CR == 1` and `XV_SUM == XV_TOT` exist precisely to red it, and the PR
  reports that mutant as having a unique killer. The rollup/render split is asserted, not just
  described.
- **The `--help` oracle is derived from the file**, which is what makes the repaired off-by-one
  non-recurring rather than repaired-once.
