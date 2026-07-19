# Plan — #100: `lanes[]` shape disagreement between config-lint and verifyctl

## Context / problem framing

`commands.<id>.lanes[]` is declared in `schema/second-shift.config.schema.json` as an array of objects (`type: "object"`, `required: ["name"]`, `additionalProperties: false`). Two consumers disagree with that declaration:

- `plugins/dev-pipeline/skills/run/tools/config-lint.sh` validates each lane entry by calling `keys` on it with **no type guard**, so a non-object entry produces **zero findings** and the config lints clean.
- `plugins/dev-pipeline/skills/run/verifyctl.sh` reads each lane as `{name, cwd?, commands[]}`. On a non-object entry the `jq -r` reads fail, `lane_cmds` ends up empty, the inner command loop iterates zero times, and the lane is **silently skipped** — no `setup:` header, no INFRA failure, green verdict.

Net effect: a consumer ships a config that lints OK whose setup lane (dependency install, workspace build) never runs, and verify reports pass having installed nothing.

### Measured behavior (re-verified at intake, base `06be9f1`)

| `lanes[0]` value | config-lint today | verifyctl today |
| --- | --- | --- |
| `{"name":"install","commands":["npm ci"]}` | OK (correct) | lane runs (correct) |
| `"npm ci"` (string) | **OK, rc=0 — silent fail-open** | silently skipped |
| `123` (number) | **OK, rc=0 — silent fail-open** | silently skipped |
| `["a"]` (array) | **OK, rc=0 — silent fail-open** | silently skipped |
| `null` | rc=5, raw jq crash (loud but ugly) | silently skipped |

A malformed **sibling** lane still reports its own violation, so the miss is per-entry, not a whole-block abort.

### Root cause (why string is silent but `null` is loud)

jq evaluates the operands of `+` right-to-left. For a **string** entry, `config-lint.sh:85`'s `.name?` indexes a string — an error that `?` converts to `empty` — and `empty` collapses the entire `+` chain, so the `keys` call at line 84 is **never reached** and the lanes block emits nothing at all. For a **`null`** entry, `.name?` is a legal `null` rather than `empty`, so the chain does not collapse, `keys` *is* reached, and jq aborts with rc=5.

This is load-bearing for the fix: **a per-`err` `and` guard is insufficient.** Guarding only line 84 with `err((type == "object") and ...)` leaves lines 85–88 still collapsing to `empty` on non-object types, re-opening the hole. Only an if/else branch taken **before** any field access is correct.

`extraLanes[]` has the **same** missing type guard. It currently fails loud by accident (`rc=5` raw jq crash on `(.commands // []) | length`) rather than cleanly. The issue text asserts `extraLanes` already carries an object-shape check to mirror — it does not; that assertion is incorrect and is corrected here.

## Assumptions

1. The schema is the contract of record. `config-lint.sh`'s own header states: "Mirrors `schema/second-shift.config.schema.json`; the schema file is the documentation contract, this script is the enforcement the plugins actually run." So enforcing object-only lanes is **closing an enforcement gap**, not narrowing a published contract.
2. Rejecting a string lane breaks no working consumer: a string lane has never executed. Anyone shipping one has a broken setup lane today, and a hard failure surfaces that latent break rather than creating a new one.
3. No schema change is needed — the schema already says what we are enforcing.

## Decision Ledger

| ID | Decision | Basis | Provenance |
| --- | --- | --- | --- |
| D1 | Enforce the schema (reject non-object lanes); do **not** teach verifyctl the string shorthand | Schema declares object-only; accepting the shorthand would widen a published contract and require a schema change | codebase-derived (intake) |
| D2 | `extraLanes[]` is in scope for the same guard | Same latent defect, verified; issue's "mirror extraLanes" pointer is factually wrong | codebase-derived (intake) |
| D3 | Defense-in-depth: config-lint rejects **and** verifyctl records INFRA | verifyctl can run against a config that was never linted; lint-only leaves the runtime fail-open path intact | codebase-derived (intake) |
| D4 | No schema file edit | Schema already correct | codebase-derived (intake) |
| D5 | `preflight.sh` gets the same guard | Third independent consumer of the shape; a non-object entry aborts the whole jq stream so **every** lane is skipped, not just the bad one — and its `2>/dev/null` hides it | plan-review (Stage 4) |
| D6 | verifyctl's `extraLanes` runtime loop gets the INFRA backstop too | D3's "verifyctl can run unlinted" argument applies identically to the extraLanes loop, which is fail-open the same way | plan-review (Stage 4) |

## Affected files/modules

- `plugins/dev-pipeline/skills/run/tools/config-lint.sh` — add per-entry object guard to `lanes[]` and `extraLanes[]` validators
- `plugins/dev-pipeline/skills/run/tools/config-lint-fixtures/invalid-bad-lane-shape.json` **[NEW]** — fixture with non-object `lanes[]` / `extraLanes[]` entries
- `plugins/dev-pipeline/skills/run/tools/config-lint-selftest.sh` — assert the new violations
- `plugins/dev-pipeline/skills/run/verifyctl.sh` — shape-check each lane before consuming it; `record_failure "INFRA"` on a non-object entry, in **both** the setup-lane loop (~453–471) and the extraLanes loop (~613–641)
- `plugins/dev-pipeline/skills/run/verifyctl-selftest.sh` — assert the runtime INFRA classification
- `plugins/dev-pipeline/skills/run/tools/preflight.sh` — guard the lane read at ~210 so one malformed entry cannot silently drop every lane
- `CHANGELOG.md` — entry for the fix

Schema (`schema/second-shift.config.schema.json`) is **not** modified — it already declares the correct shape.

## Reuse inventory

- `err(cond; msg)` — the existing jq accumulator in `config-lint.sh`; the new guard emits through it, no new helper.
- **`config-lint.sh:44`'s `err((type == "object") and ((keys) - [...]) != []; ...)`** is the file's general type-guard habit and shows the intent — but it is **NOT the form to copy here.** Per the root-cause section, an `and` guard on the `keys` operand alone leaves the sibling `.name?`/`.cwd?`/`.commands?` accesses collapsing to `empty`, so a non-object lane would still emit nothing. Use the if/else branch (Step 1), not the `and` form.
- `record_failure "INFRA" "<msg>" "<rc>" "<output>"` — existing verifyctl helper (`verifyctl.sh:367`); already the classification used by the setup-lane loop for lane failures.
- `expect_violation <fixture> <substring>` — existing selftest harness helper (`config-lint-selftest.sh:23`).
- No new helpers introduced.

## Implementation steps

1. **config-lint `lanes[]` guard.** In the `lanes` validator, branch per entry on `type != "object"` **before** any `keys`/field access, emitting `commands.<id>.lanes[N]: must be an object {name, cwd?, commands[]}`. Keep the existing object-path checks unchanged in the `else` branch.
2. **config-lint `extraLanes[]` guard.** Same treatment, message `commands.<id>.extraLanes[N]: must be an object {name, when?, commands[], failureClass?}`. This replaces today's accidental rc=5 crash with a clean violation.
3. **Fixture.** Add `config-lint-fixtures/invalid-bad-lane-shape.json` covering a string `lanes[0]`, a number `lanes[1]`, `null` `lanes[2]`, a boolean `lanes[3]`, and a string `extraLanes[0]`. `null` matters specifically because it is the one input that is *already* loud-but-ugly (rc=5) — it is what AC-1's word "cleanly" is about.
4. **config-lint selftest.** Add `expect_violation` assertions for the three new messages.
5. **verifyctl runtime backstop.** In the setup-lane loop, validate each entry's type before reading `.name`; on a non-object, `record_failure "INFRA" "setup lane [N]: not an object ..."`, set `vs_build="failed"`, and break. Note `verifyctl.sh:75` is `set -uo pipefail` (no `-e`), so the break is explicit — but no extra plumbing is needed beyond it, since the loop's existing `[[ "$overall" == "pass" ]] || break` guard (line ~456) handles the cross-lane abort once `record_failure` sets `overall="fail"`.
6. **verifyctl extraLanes backstop.** Same guard in the extraLanes loop (~613–641), which is fail-open identically (`el_name` errors, `el_cmds` empty, `(( el_ci<el_cmds ))` treats it as 0, lane recorded without running).
7. **preflight.sh guard.** The lane read at ~210 pipes `(.commands[$h].lanes // []) | .[] | (.commands // [])[]` with `2>/dev/null`; a non-object entry aborts the whole jq stream, dropping **every** lane including well-formed ones. Filter to object entries so one bad lane cannot silently disable the rest.
8. **verifyctl selftest.** Add a case asserting a non-object lane yields an INFRA failure and a non-pass verdict.
9. **CHANGELOG.** Add the entry under the dev-pipeline plugin.

## Test strategy

Verify-after (infra/tooling change, no product behavior). Both scripts are covered by fixture-driven selftests already; this extends them.

- config-lint: fixture-driven — new invalid fixture must fail and name each violation.
- verifyctl: selftest case driving a non-object lane through the setup-lane path, asserting INFRA classification rather than a silent pass.
- Regression guard: every existing `valid-*.json` fixture must still pass, and `invalid-type-gaps.json`'s existing lane assertions (well-formed objects with bad field types) must still fire — proving the guard did not swallow the deeper per-field checks.

Mutation targets are not applicable: `commands.second-shift.unitTestScope` is `null`, so this repo has no mutation surface and the unit-test gate skips.

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| --- | --- | --- | --- |
| AC-1 | config-lint rejects non-object `lanes[]` entry cleanly, exit 1 | 1 | Step 3 fixture + Step 4 assertion (string, number, null, boolean entries) |
| AC-2 | config-lint rejects non-object `extraLanes[]` entry cleanly, exit 1 (not rc=5 crash) | 2 | Step 3 fixture + Step 4 assertion (string entry) |
| AC-3 | verifyctl records INFRA for a non-object lane instead of silently skipping to green | 5, 6 | Step 8 selftest case |
| AC-4 | Well-formed lanes/extraLanes unchanged; existing selftests green | 1, 2, 6, 7 | All `valid-*.json` fixtures + existing `invalid-type-gaps.json` lane assertions + full verifyctl selftest |

## Verification commands

```bash
bash plugins/dev-pipeline/skills/run/tools/config-lint-selftest.sh
bash plugins/dev-pipeline/skills/run/verifyctl-selftest.sh
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -n1 -I{} env SKIP_STRESS=1 bash {}
```

## Risks / rollback notes

- **Risk:** a consumer config in the wild uses the string form and now hard-fails config-lint. **Mitigation / accepted:** that config's setup lane is already not running (Assumption 2), so the failure surfaces an existing break. The error message names the required shape, making the fix mechanical.
- **Risk:** the new guard short-circuits before the per-field checks and masks them. **Mitigation:** AC-4 regression assertion — `invalid-type-gaps.json`'s existing `lanes[0].cwd` / `lanes[0].commands` / `lanes[1].commands` violations must still fire.
- **Rollback:** revert the commit; both files are self-contained and the schema is untouched.

## Out-of-scope

- Changing `schema/second-shift.config.schema.json` (already correct — D4).
- Teaching verifyctl a string shorthand (explicitly rejected — D1).
- Auditing other unguarded `keys` call sites in `config-lint.sh` beyond `lanes`/`extraLanes`. The same latent pattern may exist elsewhere (e.g. `stageWorkflows[]`, `implementDelegates[]`, `planGates[]`); worth a follow-up issue, not this fix. Note the `empty`-collapse mechanism documented above means those sites are likely silent too, not merely crash-prone.
- Changing `preflight.sh`'s `bad()` control flow (it increments `FAILS` and continues rather than aborting, which is why its lane read is still reachable on a run whose config-lint already failed). The Step 7 guard makes the read safe; restructuring preflight's failure semantics is separate.
- Plugin version bump / release mechanics — handled by the repo's release process at merge.

Unverified references: none — every path, function, and line cited above was read in the worktree at `06be9f1`.
