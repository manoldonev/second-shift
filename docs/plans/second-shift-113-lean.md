# Lean spec — #113: verify: execute `commands.<id>.build` as an opt-in verify lane

## Context

`commands.<id>.build` is detected by onboarding (`detect.sh`'s `scripts.build`
lookup), written into consumer configs, and accepted by `config-lint.sh` — but
`verifyctl.sh`'s `load_config` never reads a `CMD_BUILD`. The field is dead: a
consumer can set it and nothing runs. #104 reported the concrete fallout from the
Angular angle — an AOT template-only break (`{{ nonexistentProp }}`) escapes verify
entirely unless a spec happens to transitively import the broken component (in which
case `ng test`'s AOT compile catches it incidentally, misclassified `TEST_FAILURE`).

The issue as filed proposed wiring `commands.<id>.build` into `verifyctl.sh`'s
built-in SUITE lanes as a new first-class field, with open design questions on
ordering relative to the lint/typecheck/test trio and a new failure class.

**Maintainer redirect (issue comment, 2026-07-20)** overrides that shape: do NOT
wire `commands.build` into verifyctl's trio and do NOT add a new failure class.
`commands.<repo>.extraLanes` (EP-2) already runs arbitrary blocking commands
sequentially after the SUITE trio, charged against the existing closed failure
taxonomy — a build step is exactly that, not a fourth trio member. Scope becomes
onboarding (detect + draft an `ext:build` extraLane) and retiring the now-formally-dead
`commands.<repo>.build` key, not a verifyctl core change.

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Mechanism | `commands.<repo>.build` is retired; onboarding instead drafts a `commands.<repo>.extraLanes` entry `{name: "build", commands: [<detected build command>], failureClass: "TYPE_ERROR"}` whenever `detect.sh` finds a build command. No new verifyctl code path — `ext:build` runs through the extraLanes machinery that already exists and is already tested. | issue comment (maintainer redirect) |
| D-2 | `failureClass` choice | `TYPE_ERROR` — of the closed six (`FORMAT`, `LINT_AUTOFIX`, `TYPE_ERROR`, `TEST_FAILURE`, `PLAN_CMD_FAILURE`, `INFRA`), a build/compile break (the #104 AOT template case is literally a compile-time type error the typecheck lane didn't catch) is the closest semantic fit; charging it against `TEST_FAILURE` would consume a real test-suite's fix budget for an unrelated failure mode. | codebase-derived (docs/extending.md §3.2's closed taxonomy; #104's AOT evidence) |
| D-3 | Dead-key retirement | `commands.<repo>.build` is removed from `schema/second-shift.config.schema.json` and from `config-lint.sh`'s accepted-key list, rejected the same way the v2.1.6 `integrationTest`/`apiTest` removal was: a generic "unknown keys" violation whose message names the dead key and points at `extraLanes` + `docs/migrations`. No `configVersion` bump — the prior dead-key removal (integrationTest/apiTest, gates.costTracking) didn't bump it either; it's a fail-closed lint rejection, not a version boundary. | codebase-derived (docs/migrations/v1-to-v2.md's existing "Dead-key removals" section; config-lint.sh:83's existing note pattern) |
| D-4 | Detection stays as-is | `detect.sh` keeps emitting the raw `commands.build` value + provenance unchanged — it is still correct evidence; only what onboarding *does* with that evidence changes (draft an extraLanes entry instead of a `commands.<repo>.build` key). No new Angular-specific (`@angular/core`) detection signal: any repo with an Angular build already has a `package.json` `scripts.build`, so the existing script-detection already covers the #104 motivating case. | codebase-derived (detect.sh already detects `scripts.build` generically) |
| D-5 | Draft, not elicited | The `ext:build` extraLane is auto-drafted onto the accept-or-edit review screen the same way lint/typecheck/test are (not a new `AskUserQuestion` item) — consistent with onboard's existing pattern, and the human can remove it on the screen if they don't want a build lane (satisfies the original issue's "opt-in" framing: visible and removable, never silently forced). | codebase-derived (onboard SKILL.md Step 3's existing draft-then-review pattern) |
| D-6 | Migrating already-onboarded repos | Out of scope for this issue — a consumer repo with a committed `commands.<repo>.build` starts failing `config-lint` after this ships, same posture as the integrationTest/apiTest precedent; fixing that repo's own config is that repo's own PR. | issue comment (scope: "onboard + docs") |

## Acceptance Criteria

- AC-1: `plugins/second-shift/skills/onboard/SKILL.md` Step 3's fixed `commands.<repo>`
  key list drops `build` (stays `lint`, `lintAutofixes`, `typecheck`, `test`, `format`,
  plus the always-null `testFile`/`unitTestScope`). A new paragraph directs onboard to
  draft an `extraLanes: [{name: "build", commands: [<detected build command>],
  failureClass: "TYPE_ERROR"}]` entry on the review screen (with a provenance comment,
  same as every other drafted field) whenever detection's `commands.build.value` is
  non-null, editable/removable like any other drafted item.
- AC-2: `schema/second-shift.config.schema.json` — the `commands.<repo>.build` property
  is removed.
- AC-3: `plugins/dev-pipeline/skills/run/tools/config-lint.sh` — `build` is removed from
  the accepted-keys diff list and from the string/null type-check list; the existing
  unknown-keys note is extended to also name `commands.<repo>.build` as removed
  (never executed by any verify lane — ship it via `extraLanes`), pointing at
  `docs/migrations`.
- AC-4: `plugins/dev-pipeline/skills/run/tools/config-lint-fixtures/`:
  - `valid-monorepo-github.json` and `valid-be-fe-pair-jira.json` drop their
    `"build": "yarn build"` lines (both `be`/`fe` occurrences in the latter) — they
    must stay lint-clean.
  - A new `invalid-removed-commands-build.json` fixture sets
    `commands.host.build` and is asserted to fail config-lint naming the removal, via
    a new `expect_violation` line in `config-lint-selftest.sh`.
- AC-5: The other fixtures carrying a now-invalid `"build"` key in a `commands.<repo>`
  block (`plugins/dev-pipeline/skills/run/tools/preflight-selftest.sh` ×2,
  `plugins/dev-pipeline/skills/run/scenario-liveness-selftest.sh` ×1,
  `plugins/dev-pipeline/skills/run-lean/lean-gate-selftest.sh` ×1) drop that key so they
  stay representative of a real (lint-clean) config.
- AC-5b (discovered during implementation): `preflight.sh` itself probed a `build` lane
  as a fifth entry in its Section-5 trio loop (`for lane in lint typecheck test build`)
  — dead code once the key no longer exists in any valid config. Removed, along with the
  matching comments ("+build", "build/format never verify"). Its selftest's
  `lane 'build': null/absent` assertion (the only coverage of that dead probe) is
  dropped rather than reassigned — nothing else in that fixture has a null lane to
  exercise the generic message against, and the message is exercised structurally by
  the AC-1/AC-3 zero/single-verifying-lane cases already in the file.
- AC-6: `docs/migrations/v1-to-v2.md`'s "Dead-key removals" section gets a new entry for
  `commands.<repo>.build`, phrased like the existing `integrationTest`/`apiTest` entry:
  never executed by any verify lane, ship a build tier via `extraLanes`.
- AC-7: `docs/config-schema.md`'s `commands` row description drops `build` from its
  listed sub-fields.
- AC-8: `docs/extending.md` §3.2 (`extraLanes` worked example) gets one added sentence
  noting a build/compile step (e.g. `ng build`, `tsc --noEmit --project ...`) is a valid
  extraLane, citing the AOT-template-escape motivation.
- AC-9: No change to `plugins/dev-pipeline/skills/run/verifyctl.sh` — `ext:build`
  executes via the extraLanes loop that already exists and is already covered by
  `verifyctl-selftest.sh`'s extraLanes cases (a failing extraLane command already turns
  the run red). Explicitly confirmed by re-running `verifyctl-selftest.sh` unmodified
  and green.
- AC-10: Mutation obligations: `config-lint.sh`'s existing generic
  `mutation-baseline.tsv` ordinals (`plugins/dev-pipeline/skills/run/tools/config-lint.sh::fail-open::1`
  and `catalog::config-lint-lanes-name`) are re-anchored if the edit shifted their line
  addresses; `bash tools/mutation-sweep.sh --mode pr --base origin/main` clean against
  the diff (no new uncaught survivor).
- AC-11: `find . -name '*.sh' | xargs shellcheck`, `find . -name '*.json' | xargs -n1 jq
  empty`, and the full `*-selftest.sh` sweep (`-P 4`, `SKIP_STRESS=1`) stay green.

## Out of scope

- Any change to `verifyctl.sh`'s execution logic, failure taxonomy enum, or
  attempt-budget accounting (D-1).
- `@angular/core`-specific detection in `detect.sh` (D-4).
- A `configVersion` bump (D-3).
- Migrating already-onboarded consumer repos off a committed `commands.<repo>.build`
  (D-6) — each repo's own follow-up.
