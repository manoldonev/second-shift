# Plan: read-only preflight as the onboarding finish line (#30)

## Context / problem framing

Today "verify onboarding" means running the pipeline on a real ticket — a mutating first run is the highest-anxiety possible first contact. Issue #30 adds a read-only preflight mode that `/second-shift:onboard` invokes as its final step: echo the resolved targets (tracker/repos/branches), perform one tracker READ (no claim), resolve worktree paths string-only, execute every non-null command lane once, and write a preflight report — with zero tracker/git/remote mutations.

The environment layer already exists: `plugins/dev-pipeline/skills/run/tools/pipeline-doctor.sh` is config-aware post-#17 (tracker-gated sections, PM probes derived from the configured command table, config-driven label set). Preflight **invokes** doctor rather than duplicating it, then adds the three things doctor does not do: the resolved-target echo, the tracker read, and the command-lane execution — and folds everything into one report.

Intake resolved decisions (binding, from the issue #30 intake comment):

1. **Write boundary** — forbidden: tracker mutations, git mutations (branch/worktree/commit), remote writes. Permitted: the local report file and transient lane artifacts (dependency installs, test output). Source-mutating lanes never run.
2. **"Existing gate machinery"** = the Pre-flight environment gate pieces (`config-lint.sh`, `check-extensions.sh`, label-existence READ) + doctor's config-aware layer. There is no factored "Target Confirmation Gate" artifact today; the target echo is newly written, read-only.
3. **Worktree/branch resolution is string-only** — computed from config, no `git worktree add`, no `statectl init`, no state file.
4. **Ticket source** — optional ticket-key argument; when absent, github reads the queue head (a READ); jira skips the tracker read with a note.
5. **Scope boundary** — in-scope: the preflight tool + onboard finish-line wiring + doc ripples. Deferred: removing onboard's interactive bot/label wall (the intake comment cited it as "Step 7"; it actually lives in onboard Step 3, elicitation item 7).

## Assumptions

- Preflight is a shell tool (`preflight.sh`), not a new pipeline mode flag on `/dev-pipeline:run` — the "mode" the issue names is delivered as a directly invokable read-only entry point that onboard (a Claude session) runs via Bash, mirroring how `pipeline-doctor.sh` is invoked today. No `DEV_PIPELINE_MODE` value is added (that enum stays `auto|interactive`).
- Doctor's one filesystem write (`mkdir -p .claude/worktrees`, pipeline-doctor.sh section 6) and its `mktemp` scratch files are inside the permitted write boundary (local, non-git-tracked, non-tracker). The report notes this.
- The consumer repo's `.claude/pipeline-state/` directory is the established local-only artifact home — the preflight report lands there. It is NOT gitignored in every repo (not in this one), so the report writer surfaces a gitignore reminder when the path is not ignored rather than assuming.
- macOS `/bin/bash` 3.2 compatibility is required for all new shell (repo-wide convention, proven by selftests).

## Decision Ledger

| # | Decision | Provenance | Rationale |
|---|----------|------------|-----------|
| 1 | Preflight = new `preflight.sh` invoking `pipeline-doctor.sh` as its environment section, not a doctor flag or a SKILL.md prose mode | codebase-derived | The issue mandates "builds on that layer rather than duplicating it"; doctor's exit-code contract (count of FAILs) and section framing are reused wholesale. A doctor flag would overload an advisory tool with a report-writing contract; prose modes are un-selftestable. |
| 2 | Write boundary: tracker/git/remote forbidden; local report + transient lane artifacts permitted; source-mutating lanes (`format` configured as a string, `lint` when `lintAutofixes: true`) SKIP-with-note | codebase-derived | `schema/second-shift.config.schema.json` documents `lintAutofixes` as "whether the lint command mutates files"; `verifyctl.sh` documents the `format` lane as the repo's own formatter run verbatim. A generic check-mode transformation is not derivable for arbitrary commands, so skip-with-note is the only universally safe posture. |
| 3 | Lane execution runs in the current checkout (no worktree, no scratch clone) | codebase-derived | Doctor's PM probes already run here; onboarding has no worktree yet; the lanes' purpose at preflight is "prove the configured commands are invokable and green on this machine", which the checkout satisfies. |
| 4 | Ticket source: optional `<ticket-key>` argument; absent + github → queue-head READ via `gh issue list`; absent/present + jira → SKIP-with-note (MCP reads are session-side, unreachable from bash) | codebase-derived | `tools/tracker/README.md` operation table: jira fetch-ticket is `mcp__atlassian__getJiraIssue` — not invokable from a shell tool. Preflight stays runnable issue-independent (the onboard finish line has no ticket in hand). |
| 5 | Report location: `.claude/pipeline-state/preflight-report.md`, overwritten per run; exit code = FAIL count (doctor convention) | codebase-derived | Same lifecycle as other local-only run artifacts; a stable path lets onboard print it and CONTRIBUTING snippets reference it. |
| 6 | eval-criteria.md gains no preflight clause | deferred | Criterion 1 scores pipeline runs; preflight is not a pipeline run. Revisit if retro data shows preflight runs being mis-scored. |
| 7 | Onboard's Step 3 bot/label wall (elicitation item 7) stays — creation belongs to onboarding; preflight only verifies | codebase-derived | Preflight is read-only by contract — it can never create labels or a bot wrapper, so the wall's creation half cannot be subsumed. Follow-up owns any dedup. |

## Affected files/modules

| File | Change |
|------|--------|
| `plugins/dev-pipeline/skills/run/tools/preflight.sh` [NEW] | The read-only preflight tool |
| `plugins/dev-pipeline/skills/run/tools/preflight-selftest.sh` [NEW] | Selftest incl. the zero-write assertion |
| `plugins/dev-pipeline/skills/run/SKILL.md` | Document the preflight entry point beside the pipeline-doctor mention in Prerequisites |
| `plugins/second-shift/skills/onboard/SKILL.md` | Step 8.5: invoke preflight, print the report; keep pick-a-small-ticket as the follow-up line |
| `plugins/dev-pipeline/skills/run/tools/tracker/README.md` | Add the read-only `preflight-read` row to the operation table |
| `docs/onboarding.md` | Finish-line paragraph: preflight replaces "dry-run ticket" prose |
| `plugins/dev-pipeline/.claude-plugin/plugin.json` | Version bump (minor — re-derive latest at commit time) |
| `plugins/second-shift/.claude-plugin/plugin.json` | Version bump (minor — re-derive latest at commit time) |
| `CHANGELOG.md` | Entries under the in-progress marketplace release |

## Reuse inventory

- `plugins/dev-pipeline/skills/run/tools/pipeline-doctor.sh` — invoked whole as the environment section (its exit code = its FAIL count folds into the report). Grep-verified: exists, exit-code contract at header line 14.
- `plugins/dev-pipeline/skills/run/tools/config-lint.sh` — invoked (doctor does NOT run config-lint; the run SKILL's pre-flight does) for the config-shape gate. Grep-verified.
- `plugins/dev-pipeline/skills/run/tools/check-extensions.sh` — invoked for the extension-file manifest gate. Grep-verified.
- Doctor's `resolve_sibling()` / repo-root / `CFG` resolution idioms — copied into `preflight.sh` (same monorepo-vs-install-cache dual layout problem).
- Label-set precedence (tracker.labels union → `stageParams.requiredLabels` → shipped six) — already inside doctor section 4; NOT re-implemented in preflight (doctor owns it).
- Branch/worktree naming idioms: `tracker.branchPrefix` + `${BRANCH##*/}` basename + `topology.repos.<host>.worktreesDir` — string computation copied from `stages/2-worktree.md` conventions into the target echo.
- No new helpers beyond the two [NEW] files — no existing preflight/report equivalent exists (grep for `preflight` under `plugins/dev-pipeline` returns only the SKILL.md pre-flight gate prose and doctor comments).

## Implementation steps

1. **`preflight.sh` [NEW]** — `usage: preflight.sh [<ticket-key>]`, bash 3.2-safe, `set -uo pipefail`. Sections, each contributing OK/WARN/FAIL/SKIP lines to stdout AND the report:
   a. **Resolve** repo root (`SECOND_SHIFT_REPO_ROOT` → git-common-dir → cwd), `CFG` (`SECOND_SHIFT_CONFIG` override), plugin dirs (doctor's idioms).
   b. **Config gates**: `config-lint.sh "$CFG"` (FAIL on reject; SKIP when no config) then `check-extensions.sh` (FAIL on reject).
   c. **Target Confirmation echo** (read-only, the issue's parenthetical): tracker.type + writes-effective, branchPrefix, keyPattern, topology.type, per-repo `path`/`baseBranch`/`worktreesDir` (with defaults), the computed branch (`<branchPrefix><key-or-EXAMPLE>`), the computed worktree path string, plans-dir/plan-file pattern. Echo only — no `statectl`, no git mutations.
   d. **Environment section**: run `pipeline-doctor.sh` (capture output verbatim into the report; its exit code adds to the FAIL count). Doctor is already tracker-gated and PM-probing (#17).
   e. **Tracker READ (no claim)**: github → with `<ticket-key>`: `gh api repos/{owner}/{repo}/issues/<key>` (assert readable, echo title/labels); without: `gh issue list --label <queue-label> --limit 1` (queue-head READ; empty queue = OK-with-note). jira → SKIP-with-note (MCP is session-side). Uses regular `gh` — reads never need `$GH_BOT`.
   f. **Command lanes, once each, in the current checkout**: `commands.<host>.lanes[]` (setup) sequentially, then `lint` / `typecheck` / `test` / `build` (each non-null), then `extraLanes[].commands[]` (their `when` changed-file gate is not evaluable at preflight — no diff exists — so they run unconditionally with a "when-gate not evaluated" note). Mutating skips: `format` configured as a string → SKIP (`repo formatter mutates the tree`); absent `format` → SKIP (`scoped prettier needs a diff; nothing to format-check at preflight`); `lint` with `lintAutofixes: true` → SKIP (`configured lint mutates files`). Each lane: OK on rc=0, FAIL with an output tail otherwise.
   g. **Report**: write `.claude/pipeline-state/preflight-report.md` (`mkdir -p` the dir) — header (date, config path, ticket key or "issue-independent"), the target echo, per-section results, doctor output, lane table, the write-boundary statement (what was deliberately not done: no claim, no branch, no worktree, no push, no comment), and the verdict line. Exit code = total FAIL count.
2. **`preflight-selftest.sh` [NEW]** — fixture-driven (temp dir + fixture config + mock `gh`/doctor via PATH shims + `SECOND_SHIFT_REPO_ROOT`/`SECOND_SHIFT_CONFIG` overrides), asserting:
   - **Zero-write**: fixture repo is a real `git init` checkout; after a full run, `git status --porcelain` is empty except the report path, no new branches (`git branch` unchanged), the mock `gh` recorded **only** read verbs (no `-X POST/PATCH/PUT/DELETE`, no `issue edit/comment`, no `pr create`).
   - Mutating-lane skips: fixture with `format: "mockfmt ."` + `lintAutofixes: true` → report carries both SKIP notes; neither command executed (shim guard: mockfmt/lint-with-fix log-and-fail if invoked).
   - Lane execution: non-null `test`/`typecheck` fixture commands run exactly once; a failing lane → nonzero exit and FAIL line.
   - Ticket-key arg vs queue-head fallback: mock `gh` proves `issues/<key>` GET vs `issue list` query.
   - jira fixture: tracker read SKIP; doctor's github sections already self-gate.
   - Report exists at the documented path; exit code equals injected FAIL count.
3. **`SKILL.md`** (run skill): in Prerequisites, after the pipeline-doctor paragraph, add the preflight paragraph — what it adds over doctor (target echo, tracker read, lane pass, report), the invocation (`bash "${CLAUDE_PLUGIN_ROOT}/skills/run/tools/preflight.sh" [<ticket-key>]`), and the read-only contract.
4. **Onboard `SKILL.md` Step 8.5**: replace "Print the first-run instructions (until a read-only preflight ships)" with: resolve the dev-pipeline install path (`claude plugin list --json` → `.installPath`, the doctor-skill convention — never a cache path from memory), run `preflight.sh`, surface the report + verdict; then the pick-a-small-ticket line as the actual first run.
5. **`tracker/README.md`**: add `preflight-read` operation row (github: queue-head/`issues/<key>` GET; jira: session-side MCP, tool SKIPs).
6. **`docs/onboarding.md`**: update the finish-line prose to name preflight as the onboarding verdict, dry-run ticket as step two.
7. **Version bumps + CHANGELOG**: re-derive current versions at commit time (`scripts/check-plugin-version-bumps.sh` is the gate); minor-bump `dev-pipeline` and `second-shift`; CHANGELOG entries under the in-progress release.

## Test strategy

Verify-after (infra/tooling — shell + markdown; no runtime product surface beyond the tool itself, which the selftest drives end-to-end). `preflight-selftest.sh` is auto-discovered by the repo test lane (`find . -name '*-selftest.sh' … SKIP_STRESS=1 bash`). The zero-write assertion is the heart: it is the executable form of the feature's promise. Negative assertions (no claim/branch/worktree/push/comment) live as mock-`gh` verb recording + git-state diffing, per intake's "negative ACs in the verification section".

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
|-------|-------------------|---------|---------|

(Intake AC snapshot is empty — issue #30 carries no `AC-n` IDs; the resolved intake decisions above are the binding scope. Empty table per the snapshot-empty case.)

## Verification commands

```bash
# repo green gate (from repo root of the worktree)
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -n1 -I{} env SKIP_STRESS=1 bash {}
bash scripts/check-plugin-version-bumps.sh
# feature-specific
bash plugins/dev-pipeline/skills/run/tools/preflight-selftest.sh
# live smoke (this repo is itself an onboarded consumer):
bash plugins/dev-pipeline/skills/run/tools/preflight.sh 30 || true   # exit = FAIL count; report at .claude/pipeline-state/preflight-report.md
```

## Risks / rollback

- **Doctor's runtime inside preflight** (~10 selftests) makes the finish line slow-ish (≈1–2 min). Acceptable for a one-time onboarding verdict; noted in the report header. Rollback: preflight is additive — deleting the two [NEW] files and reverting the doc edits restores today's behavior exactly.
- **Lane execution on a mis-configured repo** could run an expensive test suite. That is the point (prove the lane), and onboard just wrote the config; FAIL output is tailed, not unbounded.
- **`gh issue list` empty queue** at preflight is normal for a fresh consumer — OK-with-note, never FAIL.
- Preflight does not modify `pipeline-doctor.sh` — zero risk to the existing doctor contract.

## Out-of-scope

- Removing/refactoring onboard's Step 3 interactive bot/label wall (elicitation item 7; creation half — deferred follow-up).
- `eval-criteria.md` preflight clause (deferred; criterion 1 scores pipeline runs).
- Any `DEV_PIPELINE_MODE` enum change, statectl/state-schema surface, or new failureContext reason — preflight never touches state.
- CI-native preflight (issue #52's architecture) and jira MCP reads from shell.
