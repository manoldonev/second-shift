# Plan: verify verdict honesty — no lane reports clean/passed unless it ran (#98)

## Context

`verifyctl.sh` initializes every lane verdict optimistically (`vs_format="clean" vs_lint="clean" vs_tsc="clean" vs_test="passed" vs_build="clean"`, `verifyctl.sh:362`) and only overwrites on failure. Three defect families follow: (1) `verifySummary.build` is a misnamed setup-lane signal whose default lies — the configured `commands.<id>.build` is never executed (#113 owns execution); (2) any failure that short-circuits later lane blocks (setup-lane failure, format-lane failure — both gate the trio via `overall == "pass"` at `verifyctl.sh:482`/`:527`) leaves un-run lanes reporting `clean`/`passed`; (3) the Stage-6 completion gate (`statectl.sh:367-371`) checks shape only, so a summary that verified nothing completes the stage. Issue #98 (body v5) settles decisions D1–D3/D2a–D2c and AC-1…AC-10.

## Assumptions

- The `verifySummary` per-field token sets stay closed: `format: clean|applied|failed|skipped`, `lint: clean|failed|skipped`, `typeCheck: clean|failed|skipped`, `test: passed|failed|skipped`, `setup: clean|failed|skipped`. No `not-run` token.
- The state dir is gitignored local state; no migration for existing state files (a stale `build` key in an old state file is inert — the gate reads live summaries written by this same toolkit version).
- `statectl` never reads `second-shift.config.json` — preserved by routing every legitimate skip through string summaries emitted by verifyctl (which does read config).

## Decision Ledger

| # | Decision | Provenance | Note |
| - | -------- | ---------- | ---- |
| 1 | Lane verdicts initialize to `skipped` and are promoted on execution, replacing init-optimistic + demotion | codebase-derived | Makes the D3 invariant (a lane that did not run never reports clean/passed) structural — covers setup AND format short-circuits with one mechanism |
| 2 | `build` field renamed `setup`; config key `commands.<id>.build` untouched | codebase-derived | Issue D1; execution of the config key is #113 |
| 3 | Stage-6 object gate = positive predicate over present `lint`/`typeCheck`/`test`/`ext:*` keys | codebase-derived | Issue D2; negation is null-unsafe (measured) |
| 4 | Opt-out and when-gated-miss ride the existing string-summary acceptance | codebase-derived | Issue D2b/D2c; keeps statectl config-free |
| 5 | Exact wording of the two die messages (gate refusal vs setup-failed) | deferred | Cosmetic; settled at implementation within AC-3/AC-8 constraints |

## Affected files

All under `plugins/dev-pipeline/skills/run/`:

- `verifyctl.sh` — lane init/promotion, `setup` rename, opt-out + when-gated string paths
- `statectl.sh` — Stage-6 completion gate (case `6)` at `:360-373`, both branches)
- `verifyctl-selftest.sh` — `:165` build assertion → `setup`; new cases AC-1/AC-4/AC-7/AC-10
- `statectl-selftest.sh` — `complete_stage` case `6)` at `:81`; new gate cases (AC-3, AC-8, ext-only accept)
- `tools/config-lint.sh` — `:77` key list + boolean type-check for `allowUnverified` (mirrors `lintAutofixes` at `:81`)
- `state-schema.md` — `verifySummary` shape at `:107`, Stage-6 precondition prose at `:225`, every example carrying `"build"`
- `stages/6-verify.md` — prose: summary shape, gate semantics, `allowUnverified`
- `../../.claude-plugin/plugin.json` (dev-pipeline `plugin.json`) — version bump, re-derived at implementation time against open PRs claiming 2.2.8/2.2.9
- `../../CHANGELOG.md` (dev-pipeline changelog) — entry under the new version

## Reuse inventory

- `record_failure()` (`verifyctl.sh:366-375`) — existing failure recorder; reused unchanged for all failure paths
- `emit_verdict` / `build_verdict_ctx` (`verifyctl.sh:659-661` call site) — existing verdict emission; reused for both new string summaries
- The INERT string acceptance in `statectl.sh:370-371` (`type == "string" and length > 0`) — reused verbatim for D2b/D2c strings
- `die` helper in `statectl.sh` — reused for the two new gate messages
- `lintAutofixes` boolean rule (`tools/config-lint.sh:81`) — pattern copied for `allowUnverified`
- No new helpers introduced

## Implementation steps

1. **verifyctl.sh — honest lane init.** Replace `verifyctl.sh:362` inits with `vs_format="skipped" vs_lint="skipped" vs_tsc="skipped" vs_test="skipped" vs_setup="skipped"`. Promote on execution: setup-lanes loop sets `vs_setup="clean"` after a non-empty `lanes[]` run completes with no failure, `"failed"` on failure (`:467` site, renamed from `vs_build`); format block sets `clean`/`applied`/`failed` when it actually runs (`FORMAT_MODE=skip` leaves `skipped` — the existing `:520` line becomes redundant but harmless); trio blocks set `vs_lint="clean"`/`vs_tsc="clean"`/`vs_test="passed"` on rc==0 in the existing classification section (`:527-:599`), `"failed"` on nonzero. Un-run blocks never touch their variable — AC-1/AC-10 fall out structurally.
2. **verifyctl.sh — rename emit.** `:659-661`: emit `setup: $vs_setup` instead of `build: $vs_b`; drop the `vs_build` variable name entirely (grep leaves zero `vs_build` occurrences).
3. **verifyctl.sh — load `ALLOW_UNVERIFIED`** [NEW] in `load_config` (`:141-190`): `jq -r '.commands[$h].allowUnverified // false'`.
4. **verifyctl.sh — D2b/D2c string emissions** in the SUITE path just before object-verdict emission (`:659`): compute `TRIO_UNCONFIGURED` (all of `CMD_LINT`/`CMD_TYPECHECK`/`CMD_TEST` empty) and `EXT_COUNT`/`EXT_ALL_WHEN_SKIPPED`. If `overall == "pass"` AND `TRIO_UNCONFIGURED`: (a) `EXT_COUNT == 0` AND `ALLOW_UNVERIFIED == true` → emit string `"skipped (no verify lanes configured — allowUnverified opt-out)"`; (b) `EXT_COUNT > 0` AND every ext lane was when-skipped → emit string `"skipped (when-gated verify lanes did not match the diff)"`. Any recorded failure (`overall == "fail"`) always falls through to the object emit — a failure is never masked (issue D2b precedence).
5. **statectl.sh — Stage-6 content gate.** In case `6)` (`:360-373`), object branch: after the existing shape check, apply the D2 predicate (issue body v5, verbatim jq) `[ to_entries[] | select((.key | IN("lint","typeCheck","test")) or (.key | startswith("ext:"))) | .value ] | map(select(. != "skipped")) | length > 0`. On failure: if `.setup == "failed"` → die naming the setup failure (AC-8), else → die telling the operator to configure a verify lane or set `commands.<repo-id>.allowUnverified` (AC-3). Same predicate applied inside the be-fe-pair `all(...)` branch per target. String branch unchanged. `--force` (crash-recovery) bypasses as today.
6. **config-lint.sh** — add `allowUnverified` to the known-keys list (`:77`) and a boolean type-check mirroring `lintAutofixes` (`:81`) (AC-9).
7. **verifyctl-selftest.sh** — update `:165-167` (`build` → `setup`, still `"clean"`: that fixture configures `lanes[]` which run). New cases [NEW]: (AC-1) failing `lanes[]` step → `setup=="failed"`, trio+format all `"skipped"`; (AC-10) failing format command → `format=="failed"`, trio all `"skipped"`; (AC-4) zero-lane config + `allowUnverified:true` → string summary containing `allowUnverified`; (AC-7) trio-null + one `when`-gated ext lane + non-matching diff → string summary containing `when-gated`.
8. **statectl-selftest.sh** — `complete_stage` case `6)` (`:81`): `{"format":"clean"}` → `{"format":"clean","test":"passed"}` (keeps every multi-stage test green under the new gate). New cases [NEW]: (AC-3) `verify-summary-set '{"format":"clean"}'` then `set-stage 6 --status completed` must die; all-skipped object must die; (AC-6 shape) `{"lint":"skipped","typeCheck":"skipped","test":"skipped","ext:x":"clean"}` must complete; (AC-8) `{"setup":"failed",...all skipped}` refusal text names setup.
9. **state-schema.md** — `:107` shape → `{format, lint, typeCheck, test, setup}` + per-field enums; `:225` precondition prose describes the content gate + string exemptions; sweep remaining `"build"` examples (grep `"build"` within verifySummary contexts).
10. **stages/6-verify.md** — prose for the new summary field, gate semantics, and the `commands.<repo-id>.allowUnverified` knob.
11. **Version + changelog** — bump dev-pipeline `plugin.json` (re-derive latest: check `git tag`/open PRs for in-flight 2.2.8/2.2.9 claims first), add CHANGELOG entry.

## Test strategy

Verify-after (shell infra; no `unitTestScope` — the repo's test lane IS the selftest suite). Every AC lands as a selftest case in step 7/8 rather than a co-located spec. The full trio (`shellcheck` lint lane + selftest test lane) runs at Stage 6 via verifyctl itself — which after this change is self-hosting proof: the run's own verifySummary must satisfy the new gate.

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| ----- | ----------------- | ------- | ------- |
| AC-1 | setup failure → setup:failed, rest skipped | 1 | verifyctl-selftest new case (AC-1) |
| AC-2 | `setup` field present, no `build` field | 1, 2, 9 | verifyctl-selftest `:165` updated assertion (AC-2) |
| AC-3 | gate refuses no-verification object incl. absent-key case | 5 | statectl-selftest new cases (AC-3) |
| AC-4 | zero-lane + opt-out → string path completes | 3, 4 | verifyctl-selftest new case (AC-4) |
| AC-5 | INERT unchanged | — (no code touches INERT path) | existing INERT selftest cases stay green (AC-5) |
| AC-6 | ext-lane-only clean satisfies gate | 5 | statectl-selftest new case (AC-6) |
| AC-7 | when-gated miss → string path completes | 4 | verifyctl-selftest new case (AC-7) |
| AC-8 | setup-failed refusal names setup | 5 | statectl-selftest new case (AC-8) |
| AC-9 | config-lint boolean allowUnverified | 6 | config-lint fixture run in verification commands — no test (covered-by-selftest) |
| AC-10 | format failure → trio skipped | 1 | verifyctl-selftest new case (AC-10) |

## Verification commands

```bash
cd plugins/dev-pipeline/skills/run
bash verifyctl-selftest.sh                # includes new AC cases
bash statectl-selftest.sh                 # includes gate cases + drift-check
bash tools/config-lint.sh <fixture>       # allowUnverified accept/reject fixtures
find . -name '*.sh' -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
grep -rn "vs_build" . && echo LEAK || echo clean
```

## Risks / rollback

- **Init-to-skipped touches every lane block** — a missed promotion site would demote a lane that ran. Mitigated by the selftest suite asserting per-lane tokens on the happy path (existing `:165` block) plus the new AC cases. Rollback: single revert commit; no data migration either direction.
- **statectl-selftest drift-check** (`gen-statectl-validators.sh`) regenerates closed-enum validators from `state-schema.md`; the gate predicate is not enum-generated, but `state-schema.md` edits must keep the generated blocks byte-stable. Verified by running the drift-check in the suite.
- **In-flight version claims** — the deep-review stack (#86/#87/#73) claims dp bumps to 2.2.9 unmerged; step 11 re-derives instead of hardcoding.

## Out-of-scope

- Executing `commands.<id>.build` as a lane (#113)
- verifyctl top-level `status` honesty for zero-verification runs (#115)
- Any new `verifySummary` token (`not-run` rejected at intake)
