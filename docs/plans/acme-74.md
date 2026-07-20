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
| D-8 | `.tracker.bot.enabled` when the config is absent or unreadable | Treat the bot as **disabled** and amend via plain `gh` — `jq -r '.tracker.bot.enabled // false'`, no separate skip value | user-supplied (operator refinement on the issue, resolving the Stage-4 block; mirrors `bot-commit.sh:40`) |
| D-9 | Selftest config-injection seam | The existing `SECOND_SHIFT_CONFIG` env var — no new hook. Each case also sets `STATECTL_STATE_DIR` so pointing the config elsewhere cannot drag state-file resolution with it | codebase-derived (both seams already exist and are honored ahead of the git-common-dir chain) |

Rationale notes: D-3 and D-6 are the two places this plan chooses a stricter behavior than the issue text implies. D-6 expands scope to `state-schema.md`, contradicting the issue's "no schema change" line — that line was an estimate written before the enum was checked, not a constraint.

D-8 is the decision the previous Stage-4 review blocked on, and it is the one entry here that is **not** codebase-derived — both defaults were defensible and they fail in opposite directions (default-false risks a wrong-identity write on an unreadable config; default-true keeps this issue's bug alive in a corner). The operator chose default-false on precedent: `bot-commit.sh:40` already resolves the identical question the same way, so the alternative would have put two sibling helpers on opposite defaults for the same key. A dedicated unreadable-config skip value was considered and rejected — it would preserve both properties at the cost of an enum member consumers would have to learn.

## Affected files/modules

- `plugins/dev-pipeline/skills/run/pipeline-cost-block.sh` — the identity guard (lines 88-106) and the write site (line 437).
- `plugins/dev-pipeline/skills/run/tools/cost-block-selftest.sh` — four new cases.
- `plugins/dev-pipeline/skills/run/state-schema.md` — `costBlockApplied` enum + prose (line 296 narrows, one value added).
- `plugins/dev-pipeline/skills/run/cost-tracking-setup.md` — two `skipped-no-bot-wrapper` prose sites (lines 13, 113), plus the troubleshooting value list at 107-118 which must gain `skipped-no-gh-cli`. Line 13 additionally asserts `tracker.bot.envVar` support this script does not have (D-7) — that false claim is corrected, not merely reworded.
- `plugins/dev-pipeline/skills/run/stages/9-open-pr.md` — line 297 lists "no bot wrapper" as an unconditional cost-block prerequisite, which stops being true for bot-disabled repos; line 295 hardcodes `$GH_BOT pr edit` as *the* write path and must describe the conditional identity.
- `plugins/dev-pipeline/skills/run/cost-tracking-fixtures/README.md` — line 19 documents the old unconditional "no `$GH_BOT` wrapper → `skipped-no-bot-wrapper`" outcome, which is now config-dependent.

## Reuse inventory

- `_default_bot()` (`pipeline-cost-block.sh:92`) — reused unchanged as the last fallback in the enabled-bot path.
- `record()` (`pipeline-cost-block.sh:51`) — reused for every new exit path; the state-file contract is unchanged.
- `resolve_state()`'s config anchoring (`pipeline-cost-block.sh:27-40`) — the `SECOND_SHIFT_CONFIG` > `SECOND_SHIFT_REPO_ROOT` > git-common-dir chain is factored into a `_config_path()` helper `[NEW]` so the new `tracker.bot` read and the existing `paths.pipelineStateDir` read share one resolution instead of duplicating it. **The `STATECTL_STATE_DIR` early return (line 23-26) stays in `resolve_state()` and must NOT move into `_config_path()`** — it is a state-file override, not a config override; inheriting it would make the new `tracker.bot` read silently skip the config (and so fall to `enabled: false`, an identity downgrade) whenever an operator or selftest set a state dir.
- `cost-tracking-fixtures/state-two-runs-B.json` — reused as the amend fixture; it already carries a PR URL and passes the PR-count guard.
- `cost-tracking-fixtures/two-runs-shared-session.jsonl` — reused as the metrics fixture.
- **`COST_LOG_FILE`** (`pipeline-cost-block.sh:70`) — the existing redirect seam for `write_cost_log_row`'s output, already used by the selftest's `dump_logrow()` (line 82). Every new case sets it to a temp path. Load-bearing: the new cases run the script past `write_cost_log_row` (no dump hook short-circuits them), so without this seam each CI run would append synthetic analytics rows to the operator's real `cost-log.jsonl`.
- No other new helpers introduced.

Unverified references: none.

## Implementation steps

1. **Factor `_config_path()`** out of `resolve_state()` in `pipeline-cost-block.sh` — same precedence, no behavior change — and have `resolve_state()` call it. The `STATECTL_STATE_DIR` early return stays behind in `resolve_state()` (see Reuse inventory).
2. **Replace the identity guard** (lines 101-106) with the config-driven branch: read `.tracker.bot.enabled` via `jq -r '.tracker.bot.enabled // false'` against `_config_path()`, defaulting to `false` when the file is absent, unreadable, or malformed (D-8). When true, resolve the wrapper by D-2 precedence (expanding a leading `~` in `wrapperPath`) and keep the existing `-x` guard + `skipped-no-bot-wrapper` record; when false set `GH_CMD=gh` and log the operator-identity fallback. Set `GH_CMD` in both branches.
3. **Point the write site at `GH_CMD`** — `"$GH_CMD" pr edit` at line 437; leave the `gh pr view` read bare.
4. **Retag the missing-`gh` exit** (line 416) from `skipped-otel-error` to `skipped-no-gh-cli`.
5. **Extend `cost-block-selftest.sh`** with a shared harness (temp config writer keyed on `SECOND_SHIFT_CONFIG` + `STATECTL_STATE_DIR` per D-9, a logging fake `gh` on `PATH`, and a logging stub wrapper) and the four cases below.
6. **Update `state-schema.md`** — add `skipped-no-gh-cli`, narrow `skipped-no-bot-wrapper` (line 296) to "the bot is enabled and its wrapper is missing".
7. **Update `cost-tracking-setup.md`** — three edits: (a) line 13 states the wrapper is a prerequisite *only when the bot is enabled* and that a bot-disabled repo amends under operator identity; (b) the same line drops the false `tracker.bot.envVar` claim (D-7 — the script reads the literal `GH_BOT` name); (c) the troubleshooting value list (107-118) narrows `skipped-no-bot-wrapper` and gains a `skipped-no-gh-cli` entry ("`gh` is not on `PATH` — install it").
8. **Update `stages/9-open-pr.md`** — line 295's `$GH_BOT pr edit` becomes identity-conditional prose; line 297's prerequisite list makes the bot wrapper conditional on the bot being enabled and adds `skipped-no-gh-cli` to the enumerated values.
9. **Update `cost-tracking-fixtures/README.md`** — line 19's expected-outcome bullet becomes config-conditional (bot enabled + no wrapper → `skipped-no-bot-wrapper`; bot disabled → reaches the amend step under operator identity).

## Test strategy

Verify-after (infra shell change, no product behavior). All four cases drive the **real script end-to-end** through the amend path — no dump hooks — against the existing state + metrics fixtures, with `gh` and the wrapper stubbed as argv-logging scripts. Because no dump hook short-circuits them, these cases execute `write_cost_log_row`; each therefore sets `COST_LOG_FILE` to a temp path so no synthetic row ever reaches the real `cost-log.jsonl` (the fixture state files are already removed by the existing `trap`). Each case asserts both the recorded `costBlockApplied` **and** which binary actually received `pr edit`, so a case cannot pass by recording the right value while writing through the wrong identity.

| Case | Config | `$GH_BOT` | Asserts |
| --- | --- | --- | --- |
| bot-disabled | `enabled: false` | unset | `costBlockApplied == true`; fake `gh` log contains `pr edit` |
| wrapper-missing | `enabled: true` | nonexistent path | `costBlockApplied == "skipped-no-bot-wrapper"`; no `pr edit` anywhere |
| wrapper-present | `enabled: true` | executable stub | `costBlockApplied == true`; wrapper log contains `pr edit`; fake `gh` log does **not** |
| config-absent | `SECOND_SHIFT_CONFIG` → nonexistent path | set to an executable stub | `costBlockApplied == true`; fake `gh` log contains `pr edit`; wrapper log does **not** |

The `wrapper-present` case is the regression guard: it is what a naive "always fall through to `gh`" implementation breaks, and neither issue criterion covered it. The `config-absent` case pins D-8 — it deliberately sets `$GH_BOT` to a *working* wrapper so the assertion can only pass if the absent config, not a missing wrapper, drove the identity choice; it also covers D-3 (a stray `$GH_BOT` never overrides a disabled/defaulted bot).

Mutation surface: config `commands.second-shift.unitTestScope` is `null`, so the unit-test mutation gate does not apply.

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| --- | --- | --- | --- |
| AC-1 | Bot-disabled + `gh` present → amended, not skipped | 2, 3 | `cost-block-selftest.sh` bot-disabled case (AC-1) |
| AC-2 | `skipped-no-bot-wrapper` only when bot enabled + wrapper missing | 2, 6 | `cost-block-selftest.sh` wrapper-missing case (AC-2) |
| AC-3 | Bot-enabled + wrapper present → still amends through the wrapper | 2, 3 | `cost-block-selftest.sh` wrapper-present case (AC-3) |
| AC-4 | Config absent/unreadable → bot disabled → amend via plain `gh` | 1, 2 | `cost-block-selftest.sh` config-absent case (AC-4) |

## Verification commands

```bash
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -n1 -I{} env SKIP_STRESS=1 bash {}
```

## Risks / rollback notes

- **Identity regression** — a bug in the enabled branch could push PR edits under operator identity on a bot repo. AC-3 asserts the wrapper receives the write, and D-8 widens the exposure (an unreadable config now downgrades identity by design), so the `config-absent` case pins that the downgrade happens *only* for the config reason; `shellcheck` plus the existing selftest cases cover the rest. Rollback is reverting one commit; the sub-step is non-fatal by design, so a failure degrades to a missing cost block, never a failed pipeline.
- **Enum addition** — a consumer parsing `costBlockApplied` against the old closed set would not recognize `skipped-no-gh-cli`. Nothing in-repo parses it beyond `pipeline-retro` prose; `state-schema.md` is updated in the same commit.
- **Selftest `PATH` shim leakage** — the fake `gh` must be scoped to the case's subshell so later cases and the surrounding CI run keep the real `gh`. Enforced by exporting `PATH` per-invocation, not globally, plus the existing `trap`-based temp cleanup.

## Out-of-scope

- `.tracker.bot.envVar` parity (D-7) — the script keeps reading the literal `GH_BOT` name. The doc edits in this PR will not assert `envVar` support for this script, so they stay accurate rather than papering over the gap; closing it is a separate ticket.
- Any change to OTel collection, the rollup, the time fence, or the rendered block.
- Bot identity for any other pipeline write site.
