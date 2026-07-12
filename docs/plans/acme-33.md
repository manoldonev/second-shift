# Plan: onboard emits a consumer-repo CI evidence workflow — config-lint @ pinned ref + ref↔lockfile lockstep (#33)

## Context

`/second-shift:onboard` writes a consumer repo's second-shift configuration from evidence and emits a fixed set of committed artifacts (config, settings pin, lockfile, thin presence-check + its SessionStart hook, consent doc — `plugins/second-shift/skills/onboard/SKILL.md` Steps 4/6/7). The *gate of record* for a consumer is server-side CI; the committed thin-check is presence-only and **never blocks** (`plugins/second-shift/templates/consumer/second-shift-doctor.sh` — `exit 0` always).

Issue #33 adds a server-side backstop: onboard emits, **on request**, a small consumer-repo GitHub Actions workflow that (a) runs `config-lint` against the committed config **at the pinned marketplace ref**, and (b) asserts the settings ref and lockfile ref agree — so a half-done upgrade PR (one that bumps the settings ref but not the lockfile, or vice-versa) is caught before merge.

Both checks already exist as *client-side* logic: `plugins/second-shift/skills/doctor/tools/doctor.sh` implements the ref↔lockfile lockstep (lines 55-62) and onboard Step 5 (`SKILL.md` lines 110-115) already fetches `config-lint.sh` at the pinned ref via `gh api` for the not-yet-installed case. This issue ports that pair into a committed, server-side workflow.

**Scope (settled at intake, issue #33 comment `passed-with-decisions`):** this run implements ONLY the onboard CI-workflow emission (title + paragraph 1). The second paragraph's `Second-Shift: <version> <state-key>` PR trailer and `gates-unverified` label are **deferred/out-of-scope** — design context (a *rejected* hard-block idea *downgraded* to "advisory, not blocking"), under-specified (undefined `<version>`/`<state-key>`, undefined label trigger), and living in a different plugin (dev-pipeline Stage 9), not onboard. See Out-of-scope.

## Assumptions

- The emitted workflow must be **self-contained**: CI runners have no plugin cache installed, so it fetches `config-lint.sh` at the pinned ref (it does NOT shell out to `doctor.sh`, whose config-lint section WARN-*skips* when the plugin is absent — exactly the CI case).
- `jq` and `gh` are preinstalled and authenticated (via the built-in `GITHUB_TOKEN`) on GitHub `ubuntu-latest` runners — the standard, documented runner image contract.
- The marketplace repo is public (`manoldonev/second-shift`), so `gh api …/contents/…?ref=<ref>` resolves with the default `github.token` in a consumer's Actions runner.
- Emitting the workflow file produces a **failing check** on drift; making that check *block merge* is a branch-protection (required-status-check) decision owned by the repo admin, not something a committed file can set for itself.
- This is a `second-shift`-plugin change to the onboard skill's consumer-emission surface — single bounded context, `no-split` (intake verdict).

## Decision Ledger

| # | Decision | Choice | Provenance | Rationale |
|---|----------|--------|------------|-----------|
| 1 | Check engine placement | Emit a committed shell script `second-shift-ci-check.sh` + a thin `.yml` wrapper — NOT inline bash in YAML | codebase-derived | Mirrors the emitted thin-check precedent (`second-shift-doctor.sh` + `second-shift-doctor-selftest.sh`): a real `.sh` is shellcheckable and hermetically testable; inline YAML bash is neither. |
| 2 | config-lint acquisition | Fetch `config-lint.sh` at the lockfile's pinned ref via `gh api …/contents/…?ref=<ref>` and run it | codebase-derived | The established onboard Step 5 pattern (`SKILL.md` 110-115). Runners have no plugin cache; `doctor.sh` §7 WARN-skips in that state, so it cannot be the CI engine. |
| 3 | lockstep logic | Port `doctor.sh` §2 (lines 55-62) verbatim-in-spirit: compare `settings extraKnownMarketplaces.<mkt>.source.ref` vs `lockfile marketplace.ref`, reuse its FAIL message | codebase-derived | Single source of truth for the message/semantics; the check is ~6 lines of jq, too small to warrant a shared fetched script and `doctor.sh` isn't standalone-runnable in CI anyway. |
| 4 | Exit contract | Exit code = number of failed checks (doctor / pipeline-doctor convention) | codebase-derived | Matches `doctor.sh` (`exit "$FAILS"`) and `pipeline-doctor.sh`; a non-zero exit is what surfaces the red check. |
| 5 | Test mock seam | `SECOND_SHIFT_CONFIG_LINT` env override — when set to a local path, the check uses it instead of fetching | codebase-derived | Same injectable-seam technique as `GH_BOT` (claim-issue.sh) and `DOCTOR_*` (doctor.sh); lets the selftest exercise (a) with no network. |
| 6 | "on request" mechanism | An opt-in question in onboard's existing Step-3 one-batch elicitation; emit only when accepted | codebase-derived | Onboard already treats on-request prerequisites (label creation, Step 3.7.b) as batch opt-ins; no new interview turn. |
| 7 | merge-blocking framing | Emit the file (red check on drift) + document that marking it a *required status check* is the admin's step; onboard does NOT configure branch protection | codebase-derived | Configuring branch protection is a strictly higher privilege than emitting a file; consistent with onboard treating label creation as a documented prerequisite it never forces. |
| 8 | PR trailer + `gates-unverified` label | Deferred to a follow-up issue | deferred | Cross-plugin (dev-pipeline Stage 9), under-specified, and framed "advisory, not blocking" in the issue. Out of this ticket's scope. |

## Affected files

All paths repo-relative; all exist at `origin/main` @ `8f4db74` unless tagged `[NEW]`.

1. `plugins/second-shift/templates/consumer/second-shift-ci-check.sh` **[NEW]** — the check engine: (a) fetch+run config-lint at the pinned ref, (b) ref↔lockfile lockstep; exit = FAIL count; `SECOND_SHIFT_CONFIG_LINT` mock seam.
2. `plugins/second-shift/templates/consumer/second-shift-ci.yml` **[NEW]** — emitted GitHub Actions workflow: `on: pull_request`, checkout, run the check script with `GH_TOKEN: ${{ github.token }}`. Header comment documents the "mark as required status check to block merge" admin step.
3. `plugins/second-shift/templates/consumer/second-shift-ci-check-selftest.sh` **[NEW]** — hermetic selftest: matched/drifted lockstep fixtures, mocked config-lint pass/fail via `SECOND_SHIFT_CONFIG_LINT`, exit-code-is-FAIL-count assertions, canary (`ref: main`) case, `.yml` structural token assertion.
4. `plugins/second-shift/skills/onboard/SKILL.md` — Step 3 elicitation: add the opt-in question; new emit sub-step under Step 7 (copy the two template files into the consumer, on accept); Step 8 commit-list update; the required-status-check caveat.
5. `docs/onboarding.md` — add the emitted CI workflow to the emitted-files bullet list (lines 19-24) and one sentence on the two checks.
6. `plugins/second-shift/templates/consumer/SECOND-SHIFT.md` — consent doc: disclose the committed `.github/workflows/second-shift-ci.yml` + `.claude/tools/second-shift-ci-check.sh` under the `second-shift` plugin section (same pattern as the doctor SessionStart hook disclosure).
7. `CHANGELOG.md` — Unreleased entry under the in-progress `v2.2.0` section.
8. `plugins/second-shift/.claude-plugin/plugin.json` — `second-shift` version bump (re-derive latest at bump time per repo discipline; currently 1.4.0).

## Reuse inventory

- ref↔lockfile lockstep logic + FAIL message: `plugins/second-shift/skills/doctor/tools/doctor.sh:55-62` — ported into the check script (grep-verified).
- config-lint fetch-at-ref: `plugins/second-shift/skills/onboard/SKILL.md:112-115` (`gh api "repos/manoldonev/second-shift/contents/plugins/dev-pipeline/skills/run/tools/config-lint.sh?ref=<ref>" --jq .content | base64 --decode`) — the check script reuses this exact command shape (grep-verified).
- config-lint contract: `plugins/dev-pipeline/skills/run/tools/config-lint.sh` — `config-lint.sh <file>`, exit `0` valid / `1` violations / `3` usage (grep-verified header).
- Emitted-artifact + hermetic-selftest structure and env-mock seam: `plugins/second-shift/templates/consumer/second-shift-doctor.sh` + `second-shift-doctor-selftest.sh` (`mktemp -d` fixture tree, `check()` helper, `SECOND_SHIFT_CACHE_DIR` override) — the new script + selftest follow this shape (grep-verified).
- Lockfile/settings field paths: `.marketplace.ref` / `.marketplace.repo` (lockfile), `.extraKnownMarketplaces.<mkt>.source.ref` (settings) — as read by `doctor.sh:51-53` (grep-verified).
- No new helpers beyond the `[NEW]` script + selftest above — no existing equivalent found (`grep -rn "second-shift-ci" plugins/` empty at base).

## Implementation steps

1. **`second-shift-ci-check.sh` [NEW]:** `set -uo pipefail`; resolve `ROOT` from `git rev-parse --show-toplevel` (fallback `.`); read `LOCK=.claude/second-shift.lock.json`, `SETTINGS=.claude/settings.json`, `CONFIG=.claude/second-shift.config.json`; `MKT="second-shift"`. `FAILS=0`; `ok()/bad()` helpers echoing `[second-shift-ci]` lines and incrementing `FAILS` (doctor convention). **Check (b) lockstep:** `LOCK_REF=$(jq -r '.marketplace.ref // ""' "$LOCK")`, `SET_REF=$(jq -r --arg m "$MKT" '.extraKnownMarketplaces[$m].source.ref // ""' "$SETTINGS")`; port `doctor.sh:56-60` (match → ok; empty SET_REF → bad "no marketplace ref pin"; mismatch → bad "settings ref (…) and lockfile ref (…) disagree — a half-done upgrade …"). **Check (a) config-lint:** if `SECOND_SHIFT_CONFIG_LINT` is set, `LINT="$SECOND_SHIFT_CONFIG_LINT"`; else fetch to a `mktemp` via `gh api "repos/<repo>/contents/plugins/dev-pipeline/skills/run/tools/config-lint.sh?ref=$LOCK_REF"` (repo from `.marketplace.repo`), `base64 --decode`; run `bash "$LINT" "$CONFIG"` → `bad` on non-zero. Guard missing `jq`/`gh`/files with a clear `bad`. `exit "$FAILS"`.
2. **`second-shift-ci.yml` [NEW]:** `name: second-shift evidence`; `on: pull_request` (+ `push: branches: [<default>]` — onboard substitutes the detected base branch, mirroring `ci.yml`); one `ubuntu-latest` job: `actions/checkout@v4`, then `run: bash .claude/tools/second-shift-ci-check.sh` with `env: GH_TOKEN: ${{ github.token }}`. Header comment: "Emitted by /second-shift:onboard (#33). To BLOCK merges on drift, mark this check a required status check in branch protection — the workflow only reports; it cannot require itself."
3. **`second-shift-ci-check-selftest.sh` [NEW]:** hermetic, `mktemp -d` repo tree with `.claude/{settings.json,second-shift.lock.json,second-shift.config.json}`. Cases: (i) matched refs + a stub config-lint that exits 0 → overall exit 0, silent-ish; (ii) drifted refs (`settings v9.8.0` vs `lock v9.9.0`) → exit ≥1 + "disagree" message (AC-3); (iii) config-lint stub exits 1 → exit ≥1 (AC-2); (iv) canary `ref: main` matched → exit 0; (v) `.yml` structural assertion (`grep` for `pull_request`, the check-script invocation, `GH_TOKEN`). Uses `SECOND_SHIFT_CONFIG_LINT` pointing at a fixture stub for every case (no network). Auto-discovered by the green-gate `*-selftest.sh` find.
4. **`onboard/SKILL.md`:** Step 3 — add opt-in question ("Emit a consumer-repo CI evidence workflow — config-lint @ pinned ref + ref↔lockfile lockstep? Recommended; reports a red check on a half-done upgrade PR."). Step 7 — new sub-step "Also emit the CI evidence workflow (when accepted in Step 3)": copy `second-shift-ci.yml` → `.github/workflows/` and `second-shift-ci-check.sh` → `.claude/tools/` (executable bit; substitute `<default>` branch + `<repo>`), and state the required-status-check caveat. Step 8 item 6 — add both files to the "commit in one PR" list.
5. **`docs/onboarding.md`:** add a bullet to the emitted-files list — "an optional `.github/workflows/second-shift-ci.yml` + `.claude/tools/second-shift-ci-check.sh` (on request): the server-side backstop that lint-checks the committed config at the pinned ref and asserts settings ref ↔ lockfile ref agree."
6. **`SECOND-SHIFT.md`:** under `### second-shift`, note the two optional committed CI files (present only if the repo enabled them) and that the workflow reports (does not block unless marked required).
7. **`CHANGELOG.md` + `plugin.json`:** Unreleased `second-shift` entry under `v2.2.0`; bump `second-shift` plugin version after re-deriving the latest released version.
8. Run the full green gate (shellcheck + JSON validation + all selftests) per Verification commands.

## Test strategy

Verify-after (tooling/CI/docs change — no apps/api runtime surface; this repo has no `unitTestScope`):

- `second-shift-ci-check-selftest.sh` is the mutation-resistant regression: dropping the lockstep comparison, inverting the drift condition, or removing the config-lint invocation each fails a distinct assertion. Matched vs drifted fixtures prove the lockstep; a stub config-lint that exits 0 vs 1 proves check (a) wiring without network.
- `shellcheck` over the two new `.sh` files (green-gate lint, `-e SC1091,SC2015,SC2181`).
- `.yml` correctness is asserted structurally in the selftest (token grep) — the repo has no actionlint; the runtime contract (jq/gh preinstalled, `github.token`) is documented, not unit-testable here.
- AC-1 (onboard emits on request) is a model-behavior contract; the selftest proves the template files + tokens exist, the emit itself is exercised on real onboard runs.

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
|-------|-------------------|---------|---------|
| AC-1 | onboard emits the CI workflow file on request | 2, 4 | second-shift-ci-check-selftest.sh (template presence + `.yml` tokens) (AC-1) |
| AC-2 | workflow lint-checks the committed config at the pinned ref | 1, 2 | second-shift-ci-check-selftest.sh (config-lint fetch token + stub exit-1 → fail) (AC-2) |
| AC-3 | workflow fails when settings ref and lockfile ref disagree | 1, 3 | second-shift-ci-check-selftest.sh (drifted fixture → non-zero exit) (AC-3) |

## Verification commands

```bash
# in the worktree root
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -n1 -I{} env SKIP_STRESS=1 bash {}
# targeted:
bash plugins/second-shift/templates/consumer/second-shift-ci-check-selftest.sh
```

## Risks / rollback

- **Runner assumptions:** the check assumes `jq`/`gh`/`github.token` on the runner. Mitigation: those are the documented `ubuntu-latest` contract; the script `bad`s (not crashes) on a missing tool so the failure is legible. Rollback: revert the single PR — the emitted files are opt-in and additive; no state migration.
- **Fetch flakiness / private-fork:** a network blip or a private marketplace fork could make the config-lint fetch fail. Mitigation: legible `bad` message; the lockstep check (no network) still runs; `SECOND_SHIFT_CONFIG_LINT` lets a fork point at a vendored lint. 
- **Prose-gate drift (onboard emit step):** the "on request" opt-in + caveat are model-executed onboard prose. Mitigation: the selftest pins the template artifacts; `pipeline-retro` audits skill drift.

## Out-of-scope

- The `Second-Shift: <version> <state-key>` PR trailer and `gates-unverified` label (issue paragraph 2) — deferred; cross-plugin (dev-pipeline Stage 9), under-specified, advisory-not-blocking. A follow-up issue can spec it.
- Configuring branch protection / required status checks (higher privilege than emitting a file; documented as the admin's step — Decision Ledger 7).
- Changing `doctor.sh` or `config-lint.sh` themselves (reused as-is; the CI workflow is a server-side port, not a rewrite).
- Any dev-pipeline change.

Unverified references: none.
