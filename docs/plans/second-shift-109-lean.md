# Plan: second-shift-109 — harden statectl completion preconditions on the deviations[] ledger

## Context

Two pipeline-retro findings (#78, #81) and two follow-up datapoints (comments on
#109) show the same gap twice: `statectl.sh`'s `deviations[]` ledger is
under-validated at write time.

1. Stage-5 checkpoint payloads (`checkpoint 5 --json <payload>`) never enum-validate
   `deviations[].kind` — only the Stage-7 checkpoint does (`validate_stage7_payload`).
   An out-of-enum value written at Stage 5 is silently accepted.
2. Nothing checks that a committed path is actually accounted for by the plan. A
   `supertest` devDependency and a `plugin.json` version bump both landed mid-run,
   disclosed only in commit/PR prose, absent from both the plan's Affected-files
   section and `deviations[]` — self-scored PASS both times.

The maintainer's decision (issue #109, final comment) generalizes AC-2 from a
dependency-manifest allowlist to the general predicate: **any committed path absent
from the plan's `## Affected files/modules` section must appear in `deviations[]`**,
plus a sharper **AC-2b**: a path that matches the plan's own `## Out-of-scope`
section is a hard contradiction, not just an omission.

Explicitly out of scope (per the maintainer's decision comment): the Decision-Ledger
provenance sub-problem (its own issue), and the `deviations-add` /
`stageCheckpoint["7"]`-must-exist ordering (its own issue — kept as-is here).

## Assumptions

- `statectl.sh` stays a pure JSON/data validator — no new git or markdown I/O added
  to it directly (it currently reads only state JSON, config JSON, and (for the
  ledger-corroboration leg) JSONL files by a fixed path; extending that footprint
  to "read an arbitrary plan file off disk" is a bigger architectural change than
  this issue's scope). Instead, the plan's Affected-files / Out-of-scope path lists
  are computed by a **new caller-side tool** (mirroring how `changedFiles` is
  already computed by the caller via `git diff --name-only` and handed to
  `build-checkpoint-7` as a JSON array) and passed in as two new optional JSON-array
  flags. This keeps every new check inside `validate_stage7_payload` testable with
  plain JSON fixtures — matching how `deviations[].kind` is already tested.
- The two new flags are **opt-in at the payload level**: the AC-2a/AC-2b checks run
  only when the payload explicitly carries an `affectedFiles` key. `build-checkpoint-7`
  only emits that key when `--affected-files` was passed (mirrors the existing
  `plan_set`/`note_set` optional-field pattern). This is load-bearing: defaulting to
  `affectedFiles: []` when the flag is omitted would make every existing/legacy
  caller (anything not yet updated to pass the new flag, including the be-fe-pair
  per-repo path) fail closed on every changed file. Opt-in means the gate is inert
  until a caller supplies real data, never silently strict.
- Scope is the **flat (single-target) Stage-7 checkpoint path only**
  (`stages/7-doc-update.md`'s `else` branch / `build-checkpoint-7`). The be-fe-pair
  dual-target path (`build-checkpoint-7-perrepo`) is not touched — extending it is
  straightforward later (same opt-in flags) but doubles the fixture surface for a
  scope the issue didn't ask to widen.
- Path matching is exact string equality against `git diff --name-only`-style
  repo-relative paths (no glob/prefix matching) — the same precision `changedFiles`
  already uses elsewhere in this schema.

## Affected files/modules

- `plugins/dev-pipeline/skills/run/statectl.sh` — AC-1 (`validate_stage5_payload`,
  wired into `cmd_checkpoint` for `n == "5"`), AC-2a/AC-2b (`validate_stage7_payload`
  extended; `cmd_build_checkpoint_7` gets two new optional flags
  `--affected-files` / `--out-of-scope-files`). Shared enum-loop extracted into
  `validate_deviations_kinds` (used by both the new Stage-5 check and the existing
  Stage-7 check) to keep the two checks provably identical rather than
  hand-copied.
- `plugins/dev-pipeline/skills/run/tools/plan-scope-paths.sh` — **[NEW]** small
  deterministic tool: `plan-scope-paths.sh <plan-file> <section-pattern>` → JSON
  array of backtick-quoted path-like tokens found within that one section (reuses
  the same "path-like" token regex `plan-lint.sh`'s Check 5a already established).
- `plugins/dev-pipeline/skills/run/tools/plan-scope-paths-selftest.sh` — **[NEW]**
  per-tool selftest for the tool above (AC-3).
- `plugins/dev-pipeline/skills/run/tools/plan-scope-paths-fixtures/*.md` — **[NEW]**
  small fixture plans for the selftest above.
- `plugins/dev-pipeline/skills/run/statectl-selftest.sh` — AC-3 coverage for AC-1
  and AC-2a/AC-2b (pass + fail cases).
- `plugins/dev-pipeline/skills/run/stages/7-doc-update.md` — flat-path invocation
  updated to compute and pass `--affected-files` / `--out-of-scope-files` via the
  new tool, so real runs are actually gated (not just the statectl mechanism sitting
  inert).
- `plugins/dev-pipeline/skills/run/state-schema.md` — document the two new
  Stage-7-checkpoint fields (`affectedFiles`, `outOfScopeFiles`) and the AC-1
  Stage-5 enum check, doc-scoped under AC-4.

## Reuse inventory

- `valid_deviation_kind` (existing, `statectl.sh:1184`) — reused as-is by the new
  shared `validate_deviations_kinds` helper; no new enum introduced.
- `plan-lint.sh`'s Check-5a path-token regex — reused verbatim in the new
  `plan-scope-paths.sh` tool for "what looks like a repo path" (kept identical
  rather than re-derived, so the two tools agree on the same definition).
- `validate_stage7_payload`'s existing `parsed`/`die` pattern — new checks follow
  the same plain-`die`, no-`guard_fire` style (this function is a payload-shape
  validator, not a `stage_completion_preconditions` leg — consistent with how the
  existing `deviations[].kind` check is written).

## Implementation steps

1. **`statectl.sh`: extract `validate_deviations_kinds`.** Pull the existing
   `deviations[].kind` enum-loop out of `validate_stage7_payload` into a shared
   function `validate_deviations_kinds <json-array>` that dies on the first
   out-of-enum value (byte-identical message). Call it from `validate_stage7_payload`
   in place of the inline loop.
2. **`statectl.sh`: `validate_stage5_payload` (AC-1).** New function: JSON-parse
   the payload, and if it carries a `.deviations` array, run it through
   `validate_deviations_kinds`. Wire into `cmd_checkpoint`: `if [[ "$n" == "5" ]];
   then validate_stage5_payload "$payload"; fi`, alongside the existing `n == "1"` /
   `n == "7"` branches.
3. **[NEW] `tools/plan-scope-paths.sh` (new tool).** `plan-scope-paths.sh <plan-file>
   <section-grep-pattern>`: locate the section (same `section_present`-style
   case-insensitive heading match `plan-lint.sh` uses), slice from that heading to
   the next `#{1,6}` heading (or EOF), extract backtick-quoted path-like tokens from
   that slice using plan-lint's Check-5a regex, dedupe, emit as a JSON array (`jq -R
   . | jq -s .`). Exit 2 on missing file/args; empty array (not an error) when the
   section is absent or contains no path tokens.
4. **[NEW] `tools/plan-scope-paths-selftest.sh` + fixtures (AC-3).** Fixture plans
   covering: multiple Affected-files paths, an Out-of-scope path, a section with no
   path tokens ("Everything else" prose), and a plan missing the section entirely.
5. **`statectl.sh`: `cmd_build_checkpoint_7` new flags.** Add `--affected-files
   <json>` / `--out-of-scope-files <json>` (optional; `affected_set` /
   `oos_set` flags, mirroring the existing `plan_set` pattern). When
   `affected_set == 1`, validate `--affected-files` is a JSON array and merge
   `affectedFiles` into the payload; when additionally `oos_set == 1`, merge
   `outOfScopeFiles` (defaulting to `[]` when `--affected-files` was given but
   `--out-of-scope-files` was not — the key `affectedFiles` alone is what arms the
   gate).
6. **`statectl.sh`: `validate_stage7_payload` — AC-2a/AC-2b.** After the existing
   deviations-kind check, if `parsed` `has("affectedFiles")`: for every
   `changedFiles[]` entry not disclosed by any `deviations[].file` match — die with
   the AC-2b message if it matches an `outOfScopeFiles` entry (checked first — the
   sharper defect), else die with the AC-2a message if it is absent from
   `affectedFiles`.
7. **`stages/7-doc-update.md`: wire the tool into the flat path.** Compute
   `AFFECTED_FILES_JSON="$(tools/plan-scope-paths.sh "$PLAN_PATH" 'affected files')"`
   and `OUT_OF_SCOPE_JSON="$(tools/plan-scope-paths.sh "$PLAN_PATH" 'out.of.scope')"`
   (resolved against the worktree root, same as `PLAN_PATH` already is), pass both
   as new `build-checkpoint-7` flags. Dual-target `else`-sibling branch
   (`build-checkpoint-7-perrepo`) is untouched — out of scope per Assumptions.
8. **`statectl-selftest.sh` (AC-3).** New cases: Stage-5 checkpoint invalid kind
   rejected / valid kind (or no deviations) accepted; `build-checkpoint-7`/`checkpoint
   7` with `affectedFiles` present and a `changedFiles` entry missing from both
   `affectedFiles` and `deviations[].file` → rejected (AC-2a); same entry present in
   `affectedFiles` → accepted; same entry absent from `affectedFiles` but disclosed
   via `deviations[].file` → accepted; `outOfScopeFiles` containing a `changedFiles`
   entry with no disclosure → rejected with the distinct AC-2b message; same entry
   disclosed → accepted; payload with no `affectedFiles` key at all (legacy shape,
   e.g. `VALID_PAYLOAD`) → unaffected regardless of `changedFiles` content
   (regression case — the whole existing suite is built on `VALID_PAYLOAD`, so this
   is also implicitly exercised by every other passing case).
9. **`state-schema.md` (AC-4).** Document `affectedFiles`/`outOfScopeFiles` as
   optional Stage-7-checkpoint fields (opt-in gate semantics), and add a line to the
   Stage-5-checkpoint description noting `deviations[].kind` is now enum-validated
   there too (same enum, same message shape as Stage 7).

## Test strategy

Fixture-based `*-selftest.sh` coverage only (bash + jq, no model calls) — matches
this repo's `docs/testing.md` tier map: a new tool → per-tool selftest; a statectl
precondition → covered in `statectl-selftest.sh`. No unit-test framework applies
(this is a bash/jq repo).

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| ----- | ------------------ | ------- | ------- |
| AC-1 | Stage-5 checkpoint `deviations[].kind` outside the closed enum is rejected at write | 1, 2 | statectl-selftest.sh new cases (AC-1) |
| AC-2a | `checkpoint 7` refused when a committed path is absent from both the plan's Affected-files section and `deviations[]` | 3, 5, 6, 7 | statectl-selftest.sh + plan-scope-paths-selftest.sh new cases (AC-2a) |
| AC-2b | Same transition refused, distinct message, when a committed path matches the plan's Out-of-scope section and isn't disclosed | 3, 5, 6, 7 | statectl-selftest.sh + plan-scope-paths-selftest.sh new cases (AC-2b) |
| AC-3 | Both preconditions covered in statectl-selftest.sh (pass + fail cases); new tool covered by its own selftest | 4, 8 | the selftests themselves are the evidence |
| AC-4 | state-schema.md documents the two new fields and the Stage-5 enum check | 9 | — no test (non-functional) |

## Verification commands

- `bash plugins/dev-pipeline/skills/run/statectl-selftest.sh`
- `bash plugins/dev-pipeline/skills/run/tools/plan-scope-paths-selftest.sh`
- `find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181`

## Risks / rollback notes

- Opt-in transport (Assumption 2) is the main safety valve: if the new gate turns
  out too strict in practice, the fix is disabling the two new flags at the
  Stage-7 call site, not touching `statectl.sh` — the same "noisy gate is
  recoverable" posture the issue's own follow-up comment argues for.
- Path-token extraction (backtick-quoted, slash-containing, dotted-final-segment)
  is a heuristic, same as `plan-lint.sh`'s existing Check 5a — a plan that
  describes an affected file in prose without backticks would misfire AC-2a as a
  false positive. Accepted: the plan format already conventionally backtick-quotes
  paths (enforced nowhere, but that's the existing convention this reuses, not a
  new one).

## Out-of-scope

- Decision-Ledger provenance validation (split to its own issue per the maintainer's
  decision comment).
- `deviations-add` requiring `stageCheckpoint["7"]` to already exist (kept as-is;
  a pending-bucket redesign is its own issue per the maintainer's decision comment).
- The be-fe-pair dual-target checkpoint path (`build-checkpoint-7-perrepo`) — not
  wired to the new flags in this issue.
- Any change to `plugin.json` / release-mechanics carve-outs — #119 already
  retired plugin-version-in-PR entirely, so there is nothing left for this issue to
  carve out.
