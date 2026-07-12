# Plan — #1: persist Stage-1 pre-flight attestation and gate Stage-1 completion on it

## Context / problem framing

Eval criterion 1 (correct target / base / clean-tree pre-flight) is **self-asserted** by the
executor: nothing in the state machine proves the checks ran. The Stage-1 completion gate today
(`stage_completion_preconditions` case `1)` in `statectl.sh:319-321`) only asserts
`stageCheckpoint["1"]` is *an object of any shape*. This change persists a machine-checkable
**pre-flight attestation** into `stageCheckpoint["1"].preflight` and strengthens the completion
gate to require it well-formed — converting the criterion from self-asserted to gate-enforced.

The raw ingredients already exist at Stage 1: Step 1.P (`stages/1-intake.md:104-113`) computes
`BASE_BRANCH_CFG` and the pin outcome, and the dirty-tree check (`git status --porcelain`,
`stages/1-intake.md:98`) is computed for the WARN but never persisted. This change persists them.

## Assumptions

- **"Well-formed" means *shape*, not *truthiness*.** `workingTreeClean: false` is a **valid**
  completed-Stage-1 value — it is the blessed dirty-tree WARN-and-proceed state
  (`stages/1-intake.md:98`, `eval-criteria.md:19`). The gate must assert types, never
  `workingTreeClean == true`.
- **`guardOutcome` is a free-form non-empty string**, not a closed enum. Canonical values that can
  reach a *completed* Stage 1 are `proceed-clean` and `proceed-dirty-warn` (the pin-unestablishable
  and wrong-target outcomes `mark-failed` and never complete Stage 1). Keeping it free-form
  deliberately keeps this change **out of** the `gen-statectl-validators.sh` generated-enum +
  drift-check machinery — honoring the issue's stated scope.
- **`--force` continues to bypass the gate.** `stage_completion_preconditions` is invoked only when
  `force != 1` (`statectl.sh:659-660`), so the new check inherits the crash-recovery escape for
  free — older state files without `preflight` stay force-resumable.
- **Reduced field set is justified.** Repo identity is implicit for a `standalone` topology (this
  repo) and already persisted as `targetRepos` for `be-fe-pair`; the issue number is `ticketKey`
  (already gated). `baseBranch` + `workingTreeClean` are the self-asserted-but-unpersisted values
  the criterion needs.

## Decision Ledger

_Provenance: `codebase-derived` only (autonomous run — no user prompting)._

| # | Decision | Provenance | Basis |
|---|----------|------------|-------|
| 1 | Well-formedness = shape (keys present + correct types), `workingTreeClean:false` accepted | codebase-derived | `stages/1-intake.md:98`, `eval-criteria.md:19` bless dirty-tree WARN-and-proceed |
| 2 | `guardOutcome` free-form string (not a closed enum) → no generator/drift-check edit | codebase-derived | `statectl.sh:59-66` closed-enum drift contract; issue example shows a bare string |
| 3 | Enforce at the completion gate; add write-time validation only *if `preflight` is present* | codebase-derived | issue names `set-stage 1 --completed`; `validate_stage7_payload` (`statectl.sh:443`) is the if-present precedent |
| 4 | `--force` still bypasses (no special-casing) | codebase-derived | `statectl.sh:659-660` gate is force-conditional already |
| 5 | Field set stays `{baseBranch, workingTreeClean, guardOutcome}` | codebase-derived | repo/issue identity already persisted via `targetRepos` / `ticketKey` |

## Affected files/modules

- `plugins/dev-pipeline/skills/run/statectl.sh` — strengthen the case-`1)` completion gate; add a
  shared `preflight_wellformed` jq predicate `[NEW]` and an if-present `validate_stage1_payload` `[NEW]`
  invoked from `cmd_checkpoint` for `n==1`.
- `plugins/dev-pipeline/skills/run/state-schema.md` — document `stageCheckpoint["1"].preflight`
  (fields, types, `workingTreeClean:false` validity, `guardOutcome` canonical values); update the
  Completion-evidence preconditions table row `1` (`state-schema.md:221`); note the
  free-shape→validated-sub-object posture.
- `plugins/dev-pipeline/skills/run/stages/1-intake.md` — Step 1.P persists/carries
  `baseBranch` + `workingTreeClean` + `guardOutcome`; Step 1.D checkpoint write folds them into the
  `preflight` object.
- `plugins/dev-pipeline/skills/run/statectl-selftest.sh` — update **every** site that completes
  Stage 1 with a bare checkpoint (the strengthened gate would otherwise refuse the completion and
  cascade the suite): the `complete_stage` helper (`:72`, covers the six `complete_stage <k> 1`
  callers at `:171/:218/:235/:260/:1728/:2307`); `sc1` (`:1563`, rewritten with preflight-missing /
  malformed negatives + a `workingTreeClean:false` positive); `sc4c` designDriven checkpoint
  (`:1635`); the **`(r4)` drift-check round-trip** (`:2281` — the bare checkpoint before
  `set-stage 1 --completed` at `:2282`, inside the must-pass drift-check); the **`(u)` kill-mid-rename
  stress** (`:2324` — otherwise the completion is refused before reaching the `mv` pause, making the
  test vacuous). Add one write-time if-present-malformed case. **`(sc7)` (`:1677`) needs NO change** —
  it uses `--force` with no checkpoint, so it already proves the force-bypass works against the
  strengthened gate (Decision 4 coverage).
- `plugins/dev-pipeline/skills/run/stage8-perrepo-review-selftest.sh` — its inline setup loop
  (`:55-58`) completes Stage 1 with a bare `{"verdict":"no-split"}` checkpoint (`:58`); add a
  well-formed `preflight` there or the strengthened gate refuses the completion and cascades the
  entire stage-8 per-repo suite. (This file is a separate selftest the first plan draft missed.)
- `plugins/dev-pipeline/skills/run/statectl-selftest-fixtures/jira-completed-run.json` and
  `.../jira-in-progress-mid-pipeline.json` — add a well-formed `preflight` (fixture fidelity: a
  completed Stage-1 should carry a valid attestation; neither fixture re-runs Stage-1 completion so
  this is additive, not break-fixing).

Unverified references: none.

## Reuse inventory

- `validate_stage7_payload` (`statectl.sh:443`) — the existing checkpoint-payload validator; the new
  `validate_stage1_payload` mirrors its shape (JSON parse already done by caller, `jq -e` field
  assertions, `die` on failure).
- `stage_completion_preconditions` (`statectl.sh:315`) — the existing per-stage `jq -e` gate block;
  case `1)` is extended in place, following the sibling cases' `die`-message + `--force`-escape idiom.
- `die` / `EXIT_CODE` convention (`statectl.sh` throughout) — reused for the new refusal messages.
- `complete_stage` selftest helper (`statectl-selftest.sh:68`) — reused (its stage-1 arm updated).
- `sct` / `sct_rc` / `sct_err` selftest helpers — reused for the new assertions.
- `none — no new helpers introduced` beyond the two `[NEW]` jq/validator functions named above.

## Implementation steps

1. **`statectl.sh` — shared predicate.** Add a `preflight_wellformed()` `[NEW]` that takes a JSON blob
   (a `stageCheckpoint["1"]` object) and returns 0 iff `.preflight` is an object with
   `baseBranch` (string, `length>0`), `workingTreeClean` (boolean — `type=="boolean"`), and
   `guardOutcome` (string, `length>0`). Single `jq -e` expression; the boolean check must accept
   both `true` and `false`.
2. **`statectl.sh` — completion gate.** In `stage_completion_preconditions` case `1)`, keep the
   existing "stageCheckpoint[\"1\"] is missing" refusal (object check), then add a second refusal:
   if `preflight_wellformed` fails, `die` with a message naming the required shape and that
   `workingTreeClean:false` is accepted + `--force` for crash-recovery.
3. **`statectl.sh` — write-time defense.** Add `validate_stage1_payload()` `[NEW]` that runs
   `preflight_wellformed` **only when a `.preflight` key is present** (a checkpoint may legitimately
   omit it — the completion gate is the mandatory enforcement point). Invoke it from `cmd_checkpoint`
   (`:687-692`) in a new `if [[ "$n" == "1" ]]` branch, mirroring the `n==7` branch.
4. **`state-schema.md`.** Document the `preflight` field in the `stageCheckpoint["1"]` section
   (fields/types, `workingTreeClean:false` validity, `guardOutcome` canonical `proceed-clean` /
   `proceed-dirty-warn` free-form values). Change the preconditions table row `1` (`:221`) from
   "is an object" to "is an object carrying a well-formed `preflight` `{baseBranch, workingTreeClean:bool, guardOutcome}`".
   Add one sentence noting the `.preflight` sub-object is the first validated slice of the otherwise
   free-shape Stage-1 checkpoint.
5. **`stages/1-intake.md`.** In Step 1.P record `WORKING_TREE_CLEAN` (from `git status --porcelain`
   emptiness) and `GUARD_OUTCOME` (`proceed-clean` / `proceed-dirty-warn`) alongside the existing
   `BASE_BRANCH_CFG`. The `stageCheckpoint["1"]` payload is assembled compositionally across the
   Stage-1-close steps (Step 1.C folds in design fields, Step 1.D the intent-snapshot/AC count via
   `intake-brief`, and the actual `statectl checkpoint 1` write is the last Stage-1 step) — add
   `preflight: {baseBranch, workingTreeClean, guardOutcome}` to that documented payload, and state
   the completion gate now requires it. (Step 1.D itself writes via `intake-brief`, not the
   checkpoint; the preflight rides the `checkpoint 1` payload assembled at stage close.)
6. **Selftests — fix every Stage-1-completion site so the strengthened gate does not cascade the
   suite** (grep-enumerated, see Affected files):
   - `statectl-selftest.sh:72` (`complete_stage`) → seed
     `{"verdict":"no-split","preflight":{"baseBranch":"main","workingTreeClean":true,"guardOutcome":"proceed-clean"}}`
     (fixes the six `complete_stage <k> 1` callers centrally).
   - `statectl-selftest.sh` `sc1` → keep the no-checkpoint refusal; add: checkpoint-with-no-preflight
     → refused; malformed preflight (e.g. `workingTreeClean:"yes"`) → refused; well-formed with
     `workingTreeClean:false` → **allowed**.
   - `statectl-selftest.sh:1635` (`sc4c`) → add a well-formed preflight to the designDriven checkpoint.
   - `statectl-selftest.sh:2281` (`(r4)` drift-check) → add preflight to the bare checkpoint so
     `set-stage 1 --completed` at `:2282` still completes and the drift round-trip stays green.
   - `statectl-selftest.sh:2324` (`(u)` stress) → add preflight so the completion write actually
     reaches the `mv` pause the test exercises.
   - `statectl-selftest.sh` → add one write-time case: `checkpoint 1` with a malformed `preflight`
     present → refused by `validate_stage1_payload`.
   - `stage8-perrepo-review-selftest.sh:58` → add preflight to the inline setup-loop checkpoint.
7. **fixtures.** Add `"preflight":{"baseBranch":"main","workingTreeClean":true,"guardOutcome":"proceed-clean"}`
   to `stageCheckpoint["1"]` in both jira fixtures.
8. **Version bump** (per issue "Ship in a version-bumped release"): bump the dev-pipeline plugin
   version + CHANGELOG per repo release discipline — deferred to the maintainer's `/release`
   flow; this PR carries the CHANGELOG entry and the plugin `plugin.json` version bump if that is
   the repo convention (verify against recent merges before bumping).

## Test strategy

Verify-after (infra/shell + docs change — no TypeScript behavior surface; `unitTestScope` is
unconfigured for this repo, so the mutation-review gate is `skip`). The `statectl-selftest.sh` suite
is the mutation-resistant safety net here: the new `sc1` sub-cases are the behavior proof
(negative-and-positive around the strengthened gate), and the drift-check `(r)` must still pass
unchanged (the gate is hand-written, above the `# >>> generated` region). **The whole-repo green
gate (`find . -name '*-selftest.sh' … bash {}`) is the cross-file cascade guard** — it runs
`stage8-perrepo-review-selftest.sh` too, so a missed Stage-1-completion site surfaces as a red suite,
not a silent pass.

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| ----- | ----------------- | ------- | ------- |
| AC-1 | preflight `{baseBranch, workingTreeClean, guardOutcome}` persisted into `stageCheckpoint["1"]` | 4, 5, 6, 7 | `complete_stage` helper + jira fixtures exercise the persisted shape — covered-by-selftest |
| AC-2 | `set-stage 1 --completed` fails unless preflight present & well-formed (shape-checked, `false` accepted) | 1, 2, 3, 6 | `sc1` negative (missing/malformed → refused) + positive (`workingTreeClean:false` → allowed); write-time malformed case `(AC-2)` |

## Verification commands

```bash
cd plugins/dev-pipeline/skills/run
SKIP_STRESS=1 bash statectl-selftest.sh            # gate behavior + drift-check
shellcheck -e SC1091,SC2015,SC2181 statectl.sh statectl-selftest.sh
# repo-wide green gate:
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -n1 -I{} env SKIP_STRESS=1 bash {}
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
```

## Risks / rollback notes

- **Risk: regressing the dirty-tree WARN-and-proceed path** if the gate asserts truthiness. Mitigated
  by Decision 1 + the explicit `sc1` `workingTreeClean:false → allowed` positive case.
- **Risk: trapping crash-recovery resumes** of pre-change state files (no `preflight`). Mitigated by
  Decision 4 — `--force` bypasses; `sc7` (existing) proves `--force` skips a completion precondition.
- **Risk: drift-check breakage.** Avoided by keeping `guardOutcome` free-form (Decision 2) — no
  generated-enum edit; the gate lives in the hand-written region above `# >>> generated`.
- **Rollback:** revert the commit; the `preflight` field is additive and ignored by the prior gate.

## Out-of-scope

- Extending the attestation to `repo` / `targetRepos` / issue number (justified as already persisted
  — Decision 5).
- Making `guardOutcome` a closed enum + the `gen-statectl-validators.sh` / drift-check wiring
  (Decision 2).
- Editing `eval-criteria.md` (LOCKED during optimization runs — `eval-criteria.md:3`).
- Any change to Stages 2–10 or other trackers' adapters (the attestation is tracker-agnostic and
  written by the shared Stage-1 path).
