# lean review verdict — #574

verdict=needs-work
run_id: review-574-1
session_id: 3f7acb75-741d-484c-af17-43d847e54fd7
rounds: 1
pr: #584
reviewed_head: 67d516c7c692842175c8c9eb10845a59131e32fc
reviewed_patch_id: e311e9ed3caf4816c60f6d3ce76f0d3cef91a036
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown
capabilities: pr-marker

# Review round 1 — PR #584 (issue #574), range a30c29b..67d516c (root round, full branch diff)

Verdict: **needs-work** — 1 blocker, 2 warnings. All seven ACs score satisfied; the blocker
is an obligation the diff incurred outside the AC set (#562-r1 class).

Panel: 6/6 spawned, none dark (security, performance, maintainability, complexity,
test-coverage, scope-completeness) — all approve; the one panel finding is pre-existing and
carried below. a11y + design-fidelity not routed: no changed path matched
`stageParams.webComponentGlobs` (default `apps/web/**/*.{tsx,jsx}`); unit-test-mutation not
triggered (no co-located unit-spec surface configured — mutation is repo-carried).

## Findings

| # | Severity | Where | Finding |
| --- | --- | --- | --- |
| B1 | **Blocker** | commit 8e3c6a5 (`Changelog:` trailer) | The branch's only substantive `Changelog:` trailer covers the engine deletions and the cost-block strip but omits the **breaking** `commands.<repo>.unitTestScope`/`testFile` retirement and carries no `Migration:` line. `scripts/derive-release.sh` renders release bullets from `^Changelog:` blocks only (no commit carries a `BREAKING CHANGE:` footer), so the v9.0.0 notes would announce a major bump whose breaking change — the one requiring consumer action — appears nowhere in them. Direct precedent: #571's trailer named all three retired EP-6/7/8 keys, the by-name config-lint rejection, and a full `Migration:` paragraph. Fix costs a commit: add a commit whose `Changelog:` trailer carries the key retirement + migration pointer (trailers are extracted grep-anywhere and each renders as its own bullet), or amend. Same class as #348 r1's release-notes blockers. |
| W1 | Warning | `plugins/dev-pipeline/tools/pipeline-doctor.sh:113` | The CMD_TOOLS jq projection still enumerates `( .lint,.typecheck,.test,.testFile,.build,.format )` — a live read of the retired `testFile` key. Harmless on a lint-valid config (absent → null → filtered), but AC-3 asked advisory surfaces that read the keys to be updated coherently, and this reader survived. |
| W2 | Warning | `plugins/dev-pipeline/workflows/stall-probe.mjs:188-190`, `plugins/dev-pipeline/tools/pipeline-doctor.sh:377` | Stale model-table comments in files this PR edits: stall-probe says "check-model-tiers.sh … validates six named tables" and "A change to PLAN_REVIEWER_MODEL or UNIT_TEST_MODEL must be mirrored here" — UNIT_TEST_MODEL died with unit-tests.mjs and the named-table census is no longer six; doctor's 5g comment still lists UNIT_TEST_MODEL/DESIGN_MODEL among the tables the lint proves. |
| S1 | Suggestion | `tools/mutation-baseline.tsv` (`check-model-tiers.sh::cmp-eq::2`) | The STALE-CANDIDATE annotation is now CI-corroborated: this PR's own `mutation-sweep-pr` swept check-model-tiers on ubuntu and `cmp-eq::2` is absent from its survivor set. The keep-until-nightly posture is fine; drop the row at the promised confirmation so it doesn't fossilize. |
| P1 | Pre-existing (panel: scope-completeness, conf 85) | `docs/native-primitive-audit.md:8` | Dated v1 audit table still lists mutation-gate.mjs (and the pre-#574-deleted plan-review.mjs) as kept native primitives — point-in-time D-14 record, stale independent of this PR. Not a #574 regression. |

## Per-AC scoring (all against the committed spec `docs/plans/second-shift-574-lean.md`, first commit, never amended)

- **AC-1 — satisfied.** All five files deleted (workflows/ dir verified). Shim ladder carries no design-sync/mutation-gate/unit-tests cases; the meta literal-purity lint relocated to runtime-shim-selftest.mjs Case R (line 454, runs over every sibling workflow). workflows-mjs-selftest.sh executes no design-sync suite. pipeline-doctor's node check (code-review.mjs, intake-review.mjs) and workflow-syntax loop (`for wfscript in code-review.mjs intake-review.mjs`) name only survivors. Global reference sweep: every remaining hit is a historical "retired in #574" note, an exempted register/docs-plans/CHANGELOG row, or inert pre-existing fixture data (review-harness fixtures, grandfathered score-review anchors).
- **AC-2 — satisfied.** Every stateful path is gone (839→459); the `$STATELESS` remnant is a fail-loud retirement guard (stateful invocation exits 2 with a migration message — D-10-compliant: the live caller's `--stateless --sessions --start/--end` shape is unchanged, and this PR's own cost block was produced by the new script). Selftest re-hosts the #224 fence, #357 tiers, rotation and #432 four-way oracles onto stateless invocations against real fixture geometry; fixtures pruned to the three stateless ones. cost-tracking-setup.md rewritten stateless-only.
- **AC-3 — satisfied.** Schema carries zero definitions of either key; `config-lint.sh` rejects each **by name** with the migration pointer (run live against `invalid-removed-mutation-keys.json`: rc=1, both messages); `docs/migrations/v1-to-v2.md` has the "Dead-key removal (#574)" section; config-grill's T4 keeps `gates.mutation` as its only declared-intent arm with a retirement probe pinning that the dead key contributes no evidence; diff-guard/shadowing/onboard/doctor updated (residue: W1).
- **AC-4 — satisfied.** Rows 56/61/63 read `dropped` with `CORRECTED (#574, executed)` notes; the "Re-wire or retire is tracked in #574" tracking sentence is gone from all rows; each note names resolvable successors exactly as specified (row 61: advisory unit-test-mutation-reviewer + dropped-by-architecture + #482 left unprejudiced per D-9; rows 56/63: intake→design-faithful-spec / row-62 dispatch / render receipt + fidelity panel per row 76).
- **AC-5 — satisfied.** EXECUTOR_MODEL/UNIT_TEST_MODEL/DESIGN_MODEL-map arms removed from check-model-tiers.sh + selftest ("Each spec was removed from its loop, not made optional"); model-tiering.md's anonymous-executor section rewritten as history; schema's modelOverrides example no longer offers mutation-executor; flagged in the PR body as a deliberate reversible shrink (OR-1 default, D-11).
- **AC-6 — satisfied.** docs/testing.md, extending.md, namespaces.md, config-schema.md, onboarding.md and CLAUDE.md carry the engines/keys only as history; the mirror-harness lesson prose stays; design-toolkit dispatcher prose re-pointed to the row-62 posture (figma-faithful agents now say "its former gate dispatcher … was retired in #574" and keep the schema-free text contract).
- **AC-7 — satisfied.** Lockstep rows re-worded where their subject died (the two-language ladder entry correctly collapses to a single-implementation DROPPED record); catalog row `model-tiers-executor` removed with its anchor; known-red comment resolved; **baseline re-key CI-confirmed**: this PR un-deferred cost-block-selftest (re-measured 0.88s, off the slow-suites list) and the PR-lane sweep swept `pipeline-cost-block.sh` (10 mutants, verdicts computed) — its ubuntu survivor set is exactly the re-keyed rows `default::1`/`default::2`/`logic::2`, old `detector::1` gone with no detector survivor. `config-grill.sh`/`config-diff-guard.sh` deferred to nightly by the PR-lane cap, and neither has any generic baseline row, so no ordinal obligation exists for them.

## CI on the reviewed head (67d516c)

`mutation-sweep-pr` success (62 verdicts, 0 cache); `selftests (macos, bash 3.2)` success;
`lint-and-selftests` **still in progress at verdict time** — not waited on, because this
round is needs-work on B1 regardless of its outcome; the re-entering build session must
check its conclusion (a red there is a blocker in its own right). `pr-gates` failure
confined to the `lean chain reconciliation` arm (missing verdict record — expected
pre-review; frozen-files, changelog-trailer and pipeline-chain arms green);
`release-pr-gates` skipped. Base = origin/main tip (branch cut
from it, main has not moved): no rebase-imported consumers. Link-resolver sweep at head and
at the merge-base is byte-identical (16 pre-existing broken links, zero introduced).

## Design fidelity

not-applicable — the spec declares no `## Design` section and states "No user-facing UI
surface — every surface above is an operator-read artifact"; the repo's config declares no
design provider, so the disarm is justified.
