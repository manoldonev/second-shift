# Plan — #74: cost-block amends via plain `gh` when the bot is disabled

## Context / problem framing

`pipeline-cost-block.sh` unconditionally requires an executable bot wrapper before it will amend the cost block onto a PR. On a repo where the bot is disabled, that guard fires and the sub-step records `costBlockApplied: "skipped-no-bot-wrapper"`, so no cost block ever lands — even though `gh` is present and authenticated. Observed on #33 (PR #73).

**Root-cause correction (from Stage-1 spec review).** The issue attributes this to `$GH_BOT` resolving to the string `gh`. It never does: `_default_bot()` (`pipeline-cost-block.sh:92-100`) always derives a *filesystem path* under `$HOME/.config/<repo>/gh-as-bot.sh`. On a bot-disabled repo that path simply does not exist, so `[ ! -x "$GH_BOT" ]` (line 102) fires. The symptom in the issue is real; the mechanism is not. Consequently the fix keys off config `tracker.bot.enabled` rather than inspecting `$GH_BOT`'s runtime value — a `[ "$GH_BOT" = gh ]` special case would never fire and would leave the bug in place.

The script reads `.claude/second-shift.config.json` today only for `.paths.pipelineStateDir` (lines 33-40); it consults no `tracker.bot` key at all. Its siblings do: `tools/bot-commit.sh` branches on `.tracker.bot.enabled`, and `tools/claim-issue.sh` + `tools/pipeline-doctor.sh` honor `.tracker.bot.wrapperPath`. This change closes that gap.

## Assumptions

- `costBlockApplied` is a closed enum documented in `state-schema.md`; adding a value requires a doc edit in the same PR.
- The existing selftest contract ("pure-local: no Claude CLI, no network, no real `gh`") is binding — the new cases must stub `gh`, never invoke it.
- Existing behavior for an enabled bot with a present wrapper must be byte-identical; that is the change's blast radius.

## Decision Ledger

| ID | Decision | Choice | Provenance |
| --- | --- | --- | --- |
| D-1 | Bot-vs-plain identity signal | Config `.tracker.bot.enabled` is authoritative; `$GH_BOT`'s runtime value is never sniffed | codebase-derived (bot-commit.sh:37-47 precedent; issue's stated mechanism disproved) |
| D-2 | Wrapper path precedence when bot enabled | `$GH_BOT` env > `.tracker.bot.wrapperPath` > derived default | codebase-derived (claim-issue.sh:63-84 house pattern) |
| D-3 | Stray `$GH_BOT` on a bot-disabled repo | Ignored — config decides identity, env only supplies the path when enabled | codebase-derived (avoids a config/env contradiction resolving silently in env's favor) |
| D-4 | Write-site seam | A resolved `GH_CMD` global used at the single `pr edit` call site; the `pr view` read stays bare `gh` | codebase-derived (line 437 is the only bot-identity write; line 412 comment already fixes reads to plain gh) |
| D-5 | Selftest seam for the bot-disabled amend | Fake `gh` prepended to `PATH`, logging its argv; no new env hook | codebase-derived (keeps the pure-local contract; PATH shim covers both the read and the write) |
| D-6 | `costBlockApplied` when `gh` is absent | New `skipped-no-gh-cli`, replacing the misleading `skipped-otel-error` recorded at line 416 | codebase-derived (that site's current value is already wrong today; bot-disabled makes it far more reachable) |
| D-7 | `.tracker.bot.envVar` parity | Deferred — the script hardcodes the `GH_BOT` name; honoring a configurable var name is a wider change unrelated to this symptom | deferred |

Rationale notes: D-3 and D-6 are the two places this plan chooses a stricter behavior than the issue text implies. D-6 expands scope to `state-schema.md`, contradicting the issue's "no schema change" line — that line was an estimate written before the enum was checked, not a constraint.

## Affected files/modules

- `plugins/dev-pipeline/skills/run/pipeline-cost-block.sh` — the identity guard (lines 88-106) and the write site (line 437).
- `plugins/dev-pipeline/skills/run/tools/cost-block-selftest.sh` — three new cases.
- `plugins/dev-pipeline/skills/run/state-schema.md` — `costBlockApplied` enum + prose.
- `plugins/dev-pipeline/skills/run/cost-tracking-setup.md` — two `skipped-no-bot-wrapper` prose sites (lines 13, 113).
- `plugins/dev-pipeline/skills/run/stages/9-open-pr.md` — line 297 lists "no bot wrapper" as an unconditional cost-block prerequisite, which stops being true for bot-disabled repos.

## Reuse inventory

- `_default_bot()` (`pipeline-cost-block.sh:92`) — reused unchanged as the last fallback in the enabled-bot path.
- `record()` (`pipeline-cost-block.sh:51`) — reused for every new exit path; the state-file contract is unchanged.
- `resolve_state()`'s config anchoring (`pipeline-cost-block.sh:27-40`) — the `SECOND_SHIFT_CONFIG` > `SECOND_SHIFT_REPO_ROOT` > git-common-dir chain is factored into a `_config_path()` helper `[NEW]` so the new `tracker.bot` read and the existing `paths.pipelineStateDir` read share one resolution instead of duplicating it.
- `cost-tracking-fixtures/state-two-runs-B.json` — reused as the amend fixture; it already carries a PR URL and passes the PR-count guard.
- `cost-tracking-fixtures/two-runs-shared-session.jsonl` — reused as the metrics fixture.
- **`COST_LOG_FILE`** (`pipeline-cost-block.sh:70`) — the existing redirect seam for `write_cost_log_row`'s output, already used by the selftest's `dump_logrow()` (line 82). Every new case sets it to a temp path. Load-bearing: the new cases run the script past `write_cost_log_row` (no dump hook short-circuits them), so without this seam each CI run would append synthetic analytics rows to the operator's real `cost-log.jsonl`.
- No other new helpers introduced.

Unverified references: none.

## Implementation steps

1. **Factor `_config_path()`** out of `resolve_state()` in `pipeline-cost-block.sh` — same precedence, no behavior change — and have `resolve_state()` call it.
2. **Replace the identity guard** (lines 101-106) with the config-driven branch: read `.tracker.bot.enabled`; when true resolve the wrapper by D-2 precedence (expanding a leading `~` in `wrapperPath`) and keep the existing `-x` guard + `skipped-no-bot-wrapper` record; when false set `GH_CMD=gh` and log the operator-identity fallback. Set `GH_CMD` in both branches.
3. **Point the write site at `GH_CMD`** — `"$GH_CMD" pr edit` at line 437; leave the `gh pr view` read bare.
4. **Retag the missing-`gh` exit** (line 416) from `skipped-otel-error` to `skipped-no-gh-cli`.
5. **Extend `cost-block-selftest.sh`** with a shared harness (temp config writer + logging fake `gh` on `PATH` + logging stub wrapper) and the three cases below.
6. **Update `state-schema.md`** — add `skipped-no-gh-cli`, narrow `skipped-no-bot-wrapper` to "the bot is enabled and its wrapper is missing".
7. **Update `cost-tracking-setup.md`** — correct both prose sites to say the skip is bot-enabled-only and note the bot-disabled path uses operator identity.
8. **Update `stages/9-open-pr.md`** — line 297's prerequisite list: the bot wrapper is a prerequisite only when the bot is enabled; add `skipped-no-gh-cli` to the enumerated values.

## Test strategy

Verify-after (infra shell change, no product behavior). All three cases drive the **real script end-to-end** through the amend path — no dump hooks — against the existing state + metrics fixtures, with `gh` and the wrapper stubbed as argv-logging scripts. Because no dump hook short-circuits them, these cases execute `write_cost_log_row`; each therefore sets `COST_LOG_FILE` to a temp path so no synthetic row ever reaches the real `cost-log.jsonl` (the fixture state files are already removed by the existing `trap`). Each case asserts both the recorded `costBlockApplied` **and** which binary actually received `pr edit`, so a case cannot pass by recording the right value while writing through the wrong identity.

| Case | Config | `$GH_BOT` | Asserts |
| --- | --- | --- | --- |
| bot-disabled | `enabled: false` | unset | `costBlockApplied == true`; fake `gh` log contains `pr edit` |
| wrapper-missing | `enabled: true` | nonexistent path | `costBlockApplied == "skipped-no-bot-wrapper"`; no `pr edit` anywhere |
| wrapper-present | `enabled: true` | executable stub | `costBlockApplied == true`; wrapper log contains `pr edit`; fake `gh` log does **not** |

The three cases cover the first two acceptance criteria and the intake-added third one, in that order. The `wrapper-present` case is the regression guard: it is what a naive "always fall through to `gh`" implementation breaks, and neither issue criterion covered it.

Mutation surface: config `commands.second-shift.unitTestScope` is `null`, so the unit-test mutation gate does not apply.

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| --- | --- | --- | --- |
| AC-1 | Bot-disabled + `gh` present → amended, not skipped | 2, 3 | `cost-block-selftest.sh` bot-disabled case (AC-1) |
| AC-2 | `skipped-no-bot-wrapper` only when bot enabled + wrapper missing | 2 | `cost-block-selftest.sh` wrapper-missing case (AC-2) |

The bot-enabled regression criterion added at intake is not part of the Stage-1 snapshot, so it has no row here by design; it is covered by the `wrapper-present` selftest case and tracked in the Test strategy table above.

## Verification commands

```bash
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -n1 -I{} env SKIP_STRESS=1 bash {}
```

## Risks / rollback notes

- **Identity regression** — a bug in the enabled branch could push PR edits under operator identity on a bot repo. AC-3 asserts the wrapper receives the write; `shellcheck` plus the existing selftest cases cover the rest. Rollback is reverting one commit; the sub-step is non-fatal by design, so a failure degrades to a missing cost block, never a failed pipeline.
- **Enum addition** — a consumer parsing `costBlockApplied` against the old closed set would not recognize `skipped-no-gh-cli`. Nothing in-repo parses it beyond `pipeline-retro` prose; `state-schema.md` is updated in the same commit.
- **Selftest `PATH` shim leakage** — the fake `gh` must be scoped to the case's subshell so later cases and the surrounding CI run keep the real `gh`. Enforced by exporting `PATH` per-invocation, not globally, plus the existing `trap`-based temp cleanup.

## Out-of-scope

- `.tracker.bot.envVar` parity (D-7) — the script keeps reading the literal `GH_BOT` name. The doc edits in this PR will not assert `envVar` support for this script, so they stay accurate rather than papering over the gap; closing it is a separate ticket.
- Any change to OTel collection, the rollup, the time fence, or the rendered block.
- Bot identity for any other pipeline write site.
