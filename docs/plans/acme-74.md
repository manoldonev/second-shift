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
| D-1 | Bot-vs-plain identity signal | Config `.tracker.bot.enabled` is authoritative; the runtime value of `$GH_BOT` is never sniffed | codebase-derived |
| D-2 | Wrapper path precedence when bot enabled | `$GH_BOT` env > `.tracker.bot.wrapperPath` > derived default | codebase-derived |
| D-3 | Stray `$GH_BOT` on a bot-disabled repo | Ignored — config decides identity, env only supplies the path when enabled | codebase-derived |
| D-4 | Write-site seam | A resolved `GH_CMD` global used at the single `pr edit` call site; the `pr view` read stays bare `gh` | codebase-derived |
| D-5 | Selftest seam for the bot-disabled amend | Fake `gh` prepended to `PATH`, logging its argv; no new env hook | codebase-derived |
| D-6 | `costBlockApplied` when `gh` is absent | New `skipped-no-gh-cli`, replacing the misleading `skipped-otel-error` recorded at line 416 | codebase-derived |
| D-7 | `.tracker.bot.envVar` parity | Deferred — the script hardcodes the `GH_BOT` name; honoring a configurable var name is a wider change unrelated to this symptom | deferred |
| D-8 | `.tracker.bot.enabled` when the config is absent or unreadable | Treat the bot as disabled and amend via plain `gh` — `jq -r '.tracker.bot.enabled // false'`, no separate skip value | user-answered |
| D-9 | Selftest config-injection seam | The existing `SECOND_SHIFT_CONFIG` env var — no new hook. Each case also sets `STATECTL_STATE_DIR` so pointing the config elsewhere cannot drag state-file resolution with it | codebase-derived |

**Rationale.**

- **D-1** rests on the `bot-commit.sh:37-47` precedent, and on the issue's stated mechanism being disproved (see Context above).
- **D-2** follows the house pattern at `claim-issue.sh:63-84`.
- **D-3** avoids a config/env contradiction resolving silently in the env's favor.
- **D-4**: line 437 is the only bot-identity write in the script, and the comment at line 412 already fixes reads to plain `gh`.
- **D-5** keeps the selftest's pure-local contract; a `PATH` shim covers both the read and the write.
- **D-6**: that site's current value is already wrong today, and a bot-disabled repo makes it far more reachable.
- **D-9**: both seams already exist. `STATECTL_STATE_DIR` short-circuits `resolve_state` ahead of everything else; `SECOND_SHIFT_CONFIG` overrides the config path once a repo root has been resolved.

D-3 and D-6 are the two places this plan chooses a stricter behavior than the issue text implies. D-6 expands scope to `state-schema.md`, contradicting the issue's "no schema change" line — that line was an estimate written before the enum was checked, not a constraint.

D-8 is the decision the previous Stage-4 review blocked on, and the one entry here that is not codebase-derived. Both defaults were defensible and they fail in opposite directions: default-false risks a wrong-identity write on an unreadable config, default-true keeps this issue's bug alive in a corner. The operator chose default-false on precedent — `bot-commit.sh:40` already resolves the identical question the same way, so the alternative would have put two sibling helpers on opposite defaults for the same key. A dedicated unreadable-config skip value was considered and rejected: it would preserve both properties at the cost of an enum member every consumer would have to learn.

## Affected files/modules

- `plugins/dev-pipeline/skills/run/pipeline-cost-block.sh` — the identity guard (lines 88-106) and the write site (line 437).
- `plugins/dev-pipeline/skills/run/tools/cost-block-selftest.sh` — four new cases.
- `plugins/dev-pipeline/skills/run/state-schema.md` — `costBlockApplied` enum + prose (line 296 narrows, one value added).
- `plugins/dev-pipeline/skills/run/cost-tracking-setup.md` — two `skipped-no-bot-wrapper` prose sites (lines 13, 113), plus the troubleshooting value list at 107-118 which must gain `skipped-no-gh-cli`. Line 13 additionally asserts `tracker.bot.envVar` support this script does not have (D-7) — that false claim is corrected, not merely reworded.
- `plugins/dev-pipeline/skills/run/stages/9-open-pr.md` — line 297 lists "no bot wrapper" as an unconditional cost-block prerequisite, which stops being true for bot-disabled repos; line 295 hardcodes `$GH_BOT pr edit` as *the* write path and must describe the conditional identity.
- `plugins/dev-pipeline/skills/run/cost-tracking-fixtures/README.md` — lines 19-20 document the old unconditional outcomes ("no `$GH_BOT` wrapper → `skipped-no-bot-wrapper`", "`$GH_BOT` present → reaches the amend step"), both of which are now config-dependent.

Two further prose sites assert unconditional bot identity and become config-dependent with this change. They are small but in scope — leaving them is how the drift this PR is cleaning up got here in the first place:

- `cost-tracking-setup.md:116` — "the bot-identity `gh pr edit` call failed" is now only true on a bot-enabled repo.
- `cost-tracking-fixtures/README.md:20` — the `$GH_BOT`-present expectation is really an amend-reached expectation, independent of which identity performs it.

## Reuse inventory

- `_default_bot()` (`pipeline-cost-block.sh:92`) — reused unchanged as the last fallback in the enabled-bot path.
- `record()` (`pipeline-cost-block.sh:51`) — reused for every new exit path; the state-file contract is unchanged.
- `resolve_state()`'s config anchoring (`pipeline-cost-block.sh:27-40`) — factored into two helpers, `_repo_root()` `[NEW]` and `_config_path()` `[NEW]`, so the new `tracker.bot` read and the existing `paths.pipelineStateDir` read share one resolution instead of duplicating it.

  **The current precedence is not a flat chain, and the plan must not describe it as one.** `resolve_state()` resolves a repo root first (`SECOND_SHIFT_REPO_ROOT` > git-common-dir), and only *inside* the `[ -n "$root" ]` branch does it consult `SECOND_SHIFT_CONFIG` (line 35, as the `${SECOND_SHIFT_CONFIG:-$root/...}` default). With no resolvable root it returns a relative state path and never reads a config at all. So:

  - `_repo_root()` echoes `SECOND_SHIFT_REPO_ROOT` > git-common-dir parent > empty.
  - `_config_path()` echoes `SECOND_SHIFT_CONFIG` when set, else `<root>/.claude/second-shift.config.json` when `_repo_root()` is non-empty, else empty.
  - `resolve_state()` keeps its existing `[ -n "$root" ]` structure verbatim and calls `_config_path()` only inside that branch. Within that branch the two are equivalent by construction, so **`resolve_state()` behavior is genuinely unchanged** — the extraction does not quietly start honoring `SECOND_SHIFT_CONFIG` in the no-root case.
  - The new `tracker.bot` read calls `_config_path()` directly, so it honors `SECOND_SHIFT_CONFIG` even with no resolvable root. An empty return means "no config" and resolves to `enabled: false` per D-8.

  **The `STATECTL_STATE_DIR` early return (lines 23-26) stays in `resolve_state()` and must NOT move into either helper** — it is a state-file override, not a config override. Inheriting it would make the `tracker.bot` read silently skip the config (and so fall to `enabled: false`, an identity downgrade) whenever an operator or a selftest set a state dir — which the new cases do.
- `cost-tracking-fixtures/state-two-runs-B.json` — reused as the amend fixture; it already carries a PR URL and passes the PR-count guard.
- `cost-tracking-fixtures/two-runs-shared-session.jsonl` — reused as the metrics fixture.
- **`COST_LOG_FILE`** (`pipeline-cost-block.sh:70`) — the existing redirect seam for `write_cost_log_row`'s output, already used by the selftest's `dump_logrow()` (line 82). Every new case sets it to a temp path. Its default is `$(dirname "$STATE_FILE")/cost-log.jsonl`, so once D-9 points `STATECTL_STATE_DIR` at a temp dir the log already lands there — setting `COST_LOG_FILE` is belt-and-braces, not the sole guard it would be without the state-dir override. Kept anyway: it makes each case's output path explicit rather than a consequence of another seam, so a later change to state-dir handling cannot silently redirect synthetic rows into the operator's real `cost-log.jsonl`.
- No other new helpers introduced.

Unverified references: none.

## Implementation steps

1. **Factor `_repo_root()` and `_config_path()`** out of `resolve_state()` in `pipeline-cost-block.sh`, per the shapes in the Reuse inventory. `resolve_state()` keeps its `STATECTL_STATE_DIR` early return and its `[ -n "$root" ]` structure, calling `_config_path()` only inside that branch — so its behavior is unchanged.
2. **Replace the identity guard** (lines 101-106) with the config-driven branch: read `.tracker.bot.enabled` via `jq -r '.tracker.bot.enabled // false'` against `_config_path()`, defaulting to `false` when the file is absent, unreadable, or malformed (D-8). When true, resolve the wrapper by D-2 precedence (expanding a leading `~` in `wrapperPath`) and keep the existing `-x` guard + `skipped-no-bot-wrapper` record; when false set `GH_CMD=gh` and log the operator-identity fallback. Set `GH_CMD` in both branches.
3. **Point the write site at `GH_CMD`** — `"$GH_CMD" pr edit` at line 437; leave the `gh pr view` read bare.
4. **Retag the missing-`gh` exit** (line 416) from `skipped-otel-error` to `skipped-no-gh-cli`.
5. **Extend `cost-block-selftest.sh`** with a shared harness and the four cases below. The harness must, per case: create a temp dir; write the case's config there and point `SECOND_SHIFT_CONFIG` at it (or at a nonexistent path for `config-absent`); create a temp state dir, **copy the `state-two-runs-B.json` fixture into it as `<issue>.json`**, and point `STATECTL_STATE_DIR` at that dir; set `COST_LOG_FILE` to a temp path; build the logging fake `gh` on `PATH` and, where the case needs one, the logging stub wrapper. The fixture copy is the step that keeps these cases out of the real pipeline-state dir entirely — without it `resolve_state()` has nothing to find and the script exits early at the "no state file" guard, so the case would pass vacuously.
6. **Update `state-schema.md`** — add `skipped-no-gh-cli`, narrow `skipped-no-bot-wrapper` (line 296) to "the bot is enabled and its wrapper is missing".
7. **Update `cost-tracking-setup.md`** — three edits: (a) line 13 states the wrapper is a prerequisite *only when the bot is enabled* and that a bot-disabled repo amends under operator identity; (b) the same line drops the false `tracker.bot.envVar` claim (D-7 — the script reads the literal `GH_BOT` name); (c) the troubleshooting value list (107-118) narrows `skipped-no-bot-wrapper` and gains a `skipped-no-gh-cli` entry ("`gh` is not on `PATH` — install it").
8. **Update `stages/9-open-pr.md`** — line 295's `$GH_BOT pr edit` becomes identity-conditional prose; line 297's prerequisite list makes the bot wrapper conditional on the bot being enabled and adds `skipped-no-gh-cli` to the enumerated values.
9. **Update `cost-tracking-fixtures/README.md`** — lines 19-20's expected-outcome bullets become config-conditional (bot enabled + no wrapper → `skipped-no-bot-wrapper`; bot disabled → reaches the amend step under operator identity → `skipped-amend-failed`). While there, correct the inherited inaccuracy in line 20's parenthetical: the fixture URL `https://github.com/owner/repo/pull/8002` parses fine — the sed extracts `owner/repo` and `8002` — so the amend does **not** "fail the parse". It fails at the `gh pr view` read, because that PR does not exist. Same outcome, wrong stated mechanism.
10. **Correct the two residual bot-identity prose sites** — `cost-tracking-setup.md:116` and the `README.md:20` wording, per Affected files.

## Test strategy

Verify-after (infra shell change, no product behavior). All four cases drive the **real script end-to-end** through the amend path — no dump hooks — against the existing state + metrics fixtures, with `gh` and the wrapper stubbed as argv-logging scripts. Because no dump hook short-circuits them, these cases execute `write_cost_log_row`; each therefore sets `COST_LOG_FILE` to a temp path so no synthetic row ever reaches the real `cost-log.jsonl` (the fixture state files are already removed by the existing `trap`). Each case asserts both the recorded `costBlockApplied` **and** which binary actually received `pr edit`, so a case cannot pass by recording the right value while writing through the wrong identity.

| Case | Config | `$GH_BOT` | Asserts |
| --- | --- | --- | --- |
| bot-disabled | `enabled: false` | unset | `costBlockApplied == true`; fake `gh` log contains `pr edit` |
| wrapper-missing | `enabled: true` | nonexistent path | `costBlockApplied == "skipped-no-bot-wrapper"`; no `pr edit` anywhere |
| wrapper-present | `enabled: true` | executable stub | `costBlockApplied == true`; wrapper log contains `pr edit`; fake `gh` log does **not** |
| config-absent | `SECOND_SHIFT_CONFIG` → nonexistent path | set to an executable stub | `costBlockApplied == true`; fake `gh` log contains `pr edit`; wrapper log does **not** |

**Fake-`gh` contract** (stated explicitly — the cases depend on it and it must not be left to accident). The stub must satisfy three things, or a case passes or fails for the wrong reason:

1. **Discoverable by `command -v gh`** — it is an executable file named exactly `gh` in a temp dir prepended to `PATH`, because the script gates the whole amend on `command -v gh` (line 414) before reaching the write.
2. **Answers the `pr view` read** — `gh pr view --json body --jq .body` must exit 0 and emit a body that does **not** contain `<!-- pipeline-cost-block -->`. An empty line is sufficient; a nonzero exit makes `amend_pr` return 1 and the case records `skipped-amend-failed` instead of exercising the write.
3. **Logs argv and exits 0 for every other invocation** — including `pr edit`. The assertions grep this log, so it is the test's only observation point.

The stub wrapper for the bot-enabled cases needs only points 2 and 3 (it is invoked by path, not found on `PATH`), and the `wrapper-present` case additionally asserts the fake `gh` log is free of `pr edit` — which is what distinguishes it from a naive always-fall-through implementation.

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

**Commit requirements (CI-enforced).** This is a `plugins/**` change, so the implementation commit needs a `Changelog:` trailer describing the consumer-visible effect — `check-changelog-trailer.sh` rejects the PR without one. The trailer is grep-anywhere, so it survives the squash from any commit on the branch. `Changelog: none` is not appropriate here: the bot-disabled amend and the new `skipped-no-gh-cli` value are both consumer-visible. This PR must **not** touch `plugin.json` versions, `CHANGELOG.md`, or `marketplace.json` — those are derived at release time and `check-frozen-files.sh` rejects a feature PR that edits them.

## Risks / rollback notes

- **Identity regression** — a bug in the enabled branch could push PR edits under operator identity on a bot repo. AC-3 asserts the wrapper receives the write, and D-8 widens the exposure (an unreadable config now downgrades identity by design), so the `config-absent` case pins that the downgrade happens *only* for the config reason; `shellcheck` plus the existing selftest cases cover the rest. Rollback is reverting one commit; the sub-step is non-fatal by design, so a failure degrades to a missing cost block, never a failed pipeline.
- **Enum addition** — a consumer parsing `costBlockApplied` against the old closed set would not recognize `skipped-no-gh-cli`. Nothing in-repo parses it beyond `pipeline-retro` prose; `state-schema.md` is updated in the same commit.
- **Selftest `PATH` shim leakage** — the fake `gh` must be scoped to the case's subshell so later cases and the surrounding CI run keep the real `gh`. Enforced by exporting `PATH` per-invocation, not globally, plus the existing `trap`-based temp cleanup.

## Out-of-scope

- `.tracker.bot.envVar` parity (D-7) — the script keeps reading the literal `GH_BOT` name. The doc edits in this PR will not assert `envVar` support for this script, so they stay accurate rather than papering over the gap; closing it is a separate ticket.
- **`pipeline-doctor.sh`'s unconditional bot-wrapper check** — it reports a missing wrapper as a hard failure regardless of `.tracker.bot.enabled`, which is the same drift class this PR fixes in the cost-block script. Deliberately out of scope: doctor is a separate entry point with its own failure contract, and widening this PR to cover it would mix a bug fix with an unrelated behavior change to the onboarding gate. Worth a follow-up ticket.
- Any change to OTel collection, the rollup, the time fence, or the rendered block.
- Bot identity for any other pipeline write site.
