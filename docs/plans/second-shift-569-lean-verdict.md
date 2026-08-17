# lean review verdict — #569

verdict=approve
run_id: review-569-1
session_id: c84a9372-f19a-4c3b-ba1d-9d0209e34215
rounds: 1
pr: #571
reviewed_head: ef2bb8bb631ed77c6e541f6a17dd18fec61e3ba4
reviewed_patch_id: 4c1cbd901cd2471535c10cd4381f81139bf2e70e
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown
capabilities: pr-marker

# Review round 1 — PR #571 / issue #569 (`review-569-1`)

**Verdict: approve.** No blockers. Range read: `dc6021f..ef2bb8b` (root round, whole branch
diff — `lean-gate delta` printed FULL, nothing to inherit). Panel 6/6 returned, none dark.

## Findings

| # | Severity | Where | Finding |
| --- | --- | --- | --- |
| 1 | warning | `docs/extending.md` §5 (`:305-307`) | The case-study config block is introduced with *"This block is valid config; paste it and `config-lint` passes"*. Pasted literally it does **not**: it is a fragment (no `configVersion` / `tracker` / `topology`) with two placeholders, and `config-lint` returns 7 violations including `commands keyed by unknown repo ids: <repo-id>`. Ran the doc's own instruction to confirm. The *shapes* it recommends are correct — merged into `valid-standalone-minimal.json` the same two keys lint `OK` — so this is a framing overclaim introduced by this diff, not a wrong recommendation. Every other snippet in §3 is a fragment too and claims nothing. Suggested: "merge these two keys into your config" (drop the paste-and-pass claim), or make the block a whole config. |
| 2 | nit | `docs/migrations/v1-to-v2.md:48-52` | Missing sentence terminator: `…so failures get the correct fix budget)` runs straight into `See [extending.md](../extending.md) §3.2.` The removed clause carried the full stop. (§3.2 does resolve — it is the `extraLanes` section.) |
| 3 | nit | `docs/extending.md:158-166`, `:188-196`, `:218-226` | The retired-section banner is repeated verbatim three times and carries an awkward mid-sentence line break (`…is an open` / `> product decision, and` / `> this is the record it would start from`). Cosmetic only. |

Nothing here is merge-blocking. The CI red on `pr-gates` is the `check-lean-chain.sh` step
alone (`lean chain reconciliation`) — the verdict record this round writes; every other job on
`ef2bb8b` is green, including `mutation-sweep-pr` and both selftest jobs.

## Per-AC scoring (against the committed spec, `docs/plans/second-shift-569-lean.md`)

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | **satisfied** | All three properties gone from `schema/second-shift.config.schema.json`; root `additionalProperties: false`, so the schema rejects them independently of the lint. `config-lint.sh:43-45` rejects each by name — probed live against a hand-built config carrying `planGates`, which produced the named message and no generic one. No `configVersion` bump: `check-configversion-migration-doc.sh` → `unchanged (2) — no migration doc required. PASS`. Four fixtures repurposed (not renamed, per the `visualCapture` precedent) and `config-lint-selftest.sh` re-pointed, including a new `expect_no_violation` negative form. **Probed that negative assertion for teeth:** dropping `"stageWorkflows"` from both allowlist copies in an isolated scratch copy reds exactly one assertion — `invalid-bad-stageworkflow.json does NOT also say 'unknown top-level keys'` — and nothing else. Non-vacuous, and it empirically confirms the spec's `err()`-accumulates claim. See the AC-1 ruling below. |
| AC-2 | **satisfied** | Arm (2), the three resolution loops, the `CONFIG=` assignment and the `SECOND_SHIFT_CONFIG` override are all gone (`grep 'SECOND_SHIFT_CONFIG\|CONFIG=' check-extensions.sh` → nothing). Header rewritten to EP-3 only, with the *why* recorded. `preflight.sh:126` success line and `check-doc-routing.sh:7`'s cross-reference both re-scoped to EP-3. Selftest case (6) inverted, and strengthened past the AC: it asserts the removal's consequence (unresolvable refs ignored), that no `UNRESOLVED-*` diagnostic survives (a downgrade-to-warning would pass the first case alone), and adds a positive control that the EP-3 lint still fail-closes **with a config present** — the check that proves the deletion took the config arm and not the manifest lint. `check-extensions-selftest.sh` green locally. |
| AC-3 | **satisfied** | `mutation-catalog.tsv`'s `check-extensions-plangates` row and `mutation-baseline.tsv`'s `catalog::check-extensions-plangates` row deleted in the same diff — no `catalog::` orphan, which is the class that cost PR #568 a round. `check-extensions.sh::logic::2` **deleted, not re-pointed**, and I re-derived both matched-line sequences independently with the operator's own ERE (`grep -nE -- '&&\|\|\|'`) rather than taking the spec's: before 9 sites, after 5, mapping new1←old1, new2←**old6**, new3←old7, new4←old8, new5←old9. Old ordinal 2 was the deleted `[[ -f "$CONFIG" ]] &&` guard and was the only baselined one; every inheriting site was absent from the baseline, i.e. already killed — so re-pointing would newly accept a survivor at a killed site. Deletion is the correct disposition. **The round's own obligation, discharged:** I looped all six operators base-vs-head on every guard in the delta. `preflight.sh` (graded `deferred-to-nightly` on the PR lane, so its ordinals are this round's) is byte-identical on all six with exactly the counts the spec claims — fail-open 0, cmp-eq 5, cmp-z 18, logic 43, detector 3, default 7 — so its five baseline rows stand. `config-lint.sh` likewise byte-identical on all six (fail-open 2, cmp-z 2, logic 4, detector 1, others 0), so `::fail-open::1` and the `catalog::config-lint-lanes-name` anchor keep their meaning. `config-grill.sh` and `check-doc-routing.sh` carry no baseline or catalog row at base or head, so their edits re-key nothing. `mutation-sweep-pr` is green on `ef2bb8b`. |
| AC-4 | **satisfied** | §3.6–3.8 survive as past-tense design record under a `Historical record — retired in #569` banner, with the jsonc blocks marked `NOT VALID CONFIG`; the `INERT since #348` banners are gone. The three decision-guide rows are removed and — the trap — the surviving `extraLanes` row is **merged** to absorb their use cases rather than a fourth row being stacked into a table whose contract is "the first row that fits is your answer". §4 re-titled EP-5, §4.2 and the §5 case study re-pointed and split into a live block and a design-record block. New `docs/migrations/v1-to-v2.md` entry alongside `visualCapture`'s, plus three stale in-doc remedies rewritten. `docs/config-schema.md`, onboard `SKILL.md` and `tools/capability-parity.tsv` updated (`capability-parity-check.sh` → OK, 37 rows). Whole-tree orphan grep on the three key names, `EP-6\|EP-7\|EP-8` and `T1.extension-points`: the only survivors are `CHANGELOG.md`, `docs/plans/**` and `state-schema.md:189,228` — all three explicitly out of scope, and I confirmed `state-schema.md:3` carries the `Historical record — the pre-#348 staged-lane format` banner whose stated contract is that its dead references are not to be fixed. `docs/extension-points.md`, named in the *issue's* AC-4, carries no reference to these keys at base **or** head — nothing to re-point, so its absence from the diff is correct rather than a miss. |
| AC-5 | **satisfied** | PR **title** is `feat(dev-pipeline)!: retire the EP-6/EP-7/EP-8 config keys — a kept dead key silently disarms a consumer's blocking gate` — the breaking verb is on the squash subject, which is what `derive-release.sh` reads. Commit `54d89c4` carries the same subject plus a `Changelog:` trailer whose `Migration:` line names all three keys, the remedy (delete them from the config), the no-`configVersion`-bump fact, and the honest "no drop-in replacement". No release artifact touched: `check-configversion-migration-doc.sh` PASS, and `plugin.json` / `CHANGELOG.md` / `marketplace.json` are absent from the diff. |
| AC-6 | **satisfied** | `config-grill.sh`'s `T1.extension-points` block deleted (row, adoption loop, proposal text) with the *why* recorded in place; its `config-grill-selftest.sh` block replaced by three negative assertions including present-but-empty arrays; both `doctor-selftest.sh` scenarios re-keyed to the surviving `T1.mutation-sweep.app`, which keeps the `unadopted` severity exercised end to end on durable config (`commands.<repo>.test`); the `doctor-fixtures/config-t1-waived.json` waiver swapped; the `docs/config-schema.md` `grillWaivers` prose no longer names the retired id. A new assertion pins that the retired id cannot come back through either fixture. Both selftests green locally. |

**Fidelity: not-applicable.** The spec's `## Design` section reads `Design: none — no UI surface`,
and the reason holds: the diff touches schema, shell validators, docs and mutation registers, and
this repo's `.claude/second-shift.config.json` declares no `design.provider`. Step 5b is skipped
by its own arming condition, not waived.

## The AC-1 allowlist clause — ratified on the record

The scope-completeness reviewer raised (confidence 92, `minor`) that the *issue's* AC-1 ends
with an explicit directive — "Drop all three from the top-level allowlist at
`config-lint.sh:40`" — which the diff does not do. It is correct that the diff does not do it.
It is not a blocker, and the build's resolution stands. Four reasons, checked rather than
accepted:

1. **The clause is unsatisfiable alongside its own neighbour.** The preceding sentence mandates
   that "the key stays in the sibling allowed-keys list so the *specific* rejection fires
   instead of the generic one". For a *top-level* key that sibling list **is** the line-40
   allowlist. Both halves cannot hold.
2. **The chosen half is the one the AC's own purpose clause names.** `err()` accumulates rather
   than short-circuits, so dropping the key emits a bare `unknown top-level keys: stageWorkflows`
   *alongside* the named message — the exact outcome the first sentence exists to prevent. I did
   not take this from the spec: the probe under AC-1 above produced both messages from one run.
3. **The tree has an unbroken precedent and zero counter-examples.** `gates.figma`,
   `gates.apiTests`, `gates.costTracking` (`config-lint.sh:178-183`) and
   `stageParams.visualCapture` each stay in their sibling allowlist behind a `has(...)`
   rejection. Verified in the file, not inferred.
4. **It is consequence-free.** The schema property is gone and the schema root is
   `additionalProperties: false`, so a config carrying any of the three fails schema validation
   *and* config-lint. The allowlist entry is message routing; it grants no legality.

And the resolution is not a spec amended after the fact to match the diff — the check the lean
rules require. `git show a7e1b31` (the branch's **first** commit, before any implementation) already
carries both the "AC-1: an internal contradiction, resolved against the tree" section and the AC-6
amendment. The only later spec edit, `05c484b`, adds the AC-3 evidence section and changes no AC
text. Declared before the work, argued against precedent, flagged in the PR body for exactly this
disagreement. Ratified.

The same reviewer's suppressed note that AC-3 "says re-baseline but the diff deletes the row" is
likewise not a miss: the AC asks for the re-derivation, and the re-derivation's answer is
deletion — independently confirmed above.

## Panel

| Reviewer | Verdict | Findings |
| --- | --- | --- |
| Security | Pass | 0 (2 suppressed <80) |
| Performance | Pass | 0 |
| Maintainability | Pass | 0 |
| Complexity | Pass | 0 |
| Test coverage | Pass | 0 |
| Scope completeness | Fail → ratified | 1 minor (AC-1 allowlist clause, above) |

6 selected, 6 returned, none dark. `a11y` / design-fidelity not routed: no changed path is a
web-component surface (`stageParams.webComponentGlobs` unset in this repo; default
`apps/web/**/*.{tsx,jsx}` matches nothing here). `db-reviewer`, `pipeline-reviewer` and
`unit-test-mutation-reviewer` were not triggered — no DB, queue, or co-located unit-spec surface
in the diff.

## Verification run this round

- `config-lint-selftest.sh`, `check-extensions-selftest.sh`, `config-grill-selftest.sh`,
  `doctor-selftest.sh` — all green locally, `env -u CLAUDE_CODE_SESSION_ID`.
- `check-lockstep-pairs.sh` (22 pairs), `check-fail-open-shapes.sh` (13 sites),
  `check-configversion-migration-doc.sh`, `capability-parity-check.sh`, `check-doc-routing.sh`,
  `check-config-shadowing.sh` — all clean.
- Six-operator matched-line sequence diff, base vs head, over every guard in the delta (AC-3).
- Isolated-copy mutation probe of the new `expect_no_violation` assertion (AC-1).
- The §5 paste instruction executed against `config-lint.sh` (finding 1), and the same keys
  merged into a valid fixture to confirm the recommended shapes lint `OK`.
- CI on `ef2bb8b`: `lint-and-selftests`, `selftests (macos, bash 3.2)` and `mutation-sweep-pr`
  all SUCCESS; `pr-gates` red on the `lean chain reconciliation` step only.
