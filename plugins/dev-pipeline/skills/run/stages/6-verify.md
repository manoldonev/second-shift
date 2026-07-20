# Stage 6. Verify (with Failure Classification)

**First, mark the stage started** — per the global Stage write convention (SKILL.md), Stage 6 begins with `statectl set-stage "$ISSUE_NUMBER" 6 --status started` BEFORE the verify runner below. Stage 6 leads with real work, so deferring the started-write collapses `stages.6` to a 0:00 window, and `set-stage ... --status completed` then errors with "cannot complete stage 6 with no startedAt". Write `started` first.

## Deterministic verify runner (verifyctl)

The suite is run by the sibling helper [`verifyctl.sh`](../verifyctl.sh) — NOT by hand-composed `yarn` commands. verifyctl owns lane derivation (INERT/SUITE from the merge-base diff via [`tools/is-inert-diff.sh`](../tools/is-inert-diff.sh)), prettier resolution, the SUITE commands (install-if-missing → packages build → scoped format → `lint` & `type-check` & `test` concurrent), by-command failure classification, and **every `FORMAT` / `LINT_AUTOFIX` / `TYPE_ERROR` / `TEST_FAILURE` `verifyAttempts` increment** — it detects fix-attempt re-runs via its own runId-scoped sidecar and charges `statectl verify-attempts` itself, refusing to run once a class budget (2) is exhausted. **Never charge those four classes yourself**; the plan-specific-command class (`PLAN_CMD_FAILURE`) remains in-session per the section below. This closes the drift class where real fix loops leave `verifyAttempts` at `{}`.

Resolve `{verifyctl}` ONCE. verifyctl.sh ships in the **plugin checkout** (`skills/run/`), NOT the consumer repo — every consumer is de-vendored — so anchor it to `${CLAUDE_PLUGIN_ROOT}` (the same resolution SKILL.md pre-flight uses for `config-lint.sh`), falling back to the sibling location of `statectl.sh` (both ship side-by-side in `skills/run/`). **Never** resolve it through the git-common-dir: that idiom is correct for `main_root()` (consumer state/worktree), but it points at the consumer repo root, where no `verifyctl.sh` exists.

```bash
VERIFYCTL="${CLAUDE_PLUGIN_ROOT:-}/skills/run/verifyctl.sh"
[[ -x "$VERIFYCTL" ]] || VERIFYCTL="$(dirname "$(command -v statectl.sh)")/verifyctl.sh"
```

Then run:

```
{verifyctl} run {issue-number}
```

Everything else (worktree path, base ref incl. stacked-slice stacking via the persisted `worktreeBase`, lane classification) is derived from state/git by the helper — there are no override flags. Read the verdict JSON from stdout and act on its exit code:

| Exit | Meaning          | Action                                                                                                                                                                                                  |
| ---- | ---------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 0    | pass             | Commit any `formatChanged[]` / `lintAutofixed[]` files **scoped to the current task** (discard unrelated-file formatting via `git checkout -- <file>`); proceed.                                        |
| 1    | fail             | Fix each `failures[].class` in-session (`TYPE_ERROR` / `TEST_FAILURE` / residual `LINT_AUTOFIX`; read `failures[].outputTail`, or the full `logFile` when needed), commit, re-invoke `{verifyctl} run`. |
| 4    | budget-exhausted | A class exhausted its 2-attempt budget. Take the budget-exhaustion failure path below — do NOT retry.                                                                                                   |
| 2/3  | internal / usage | `[verifyctl-error]` infra-fatal posture (helper-failure contract) — surface the stderr text.                                                                                                            |

`INFRA` entries in `failures[]` are never charged and never retried — surface immediately (a `packages-build` or `install` failure is INFRA-grade: a build-order/environment prerequisite, not a verify fix loop). On `status: "pass"`, persist the verify summary — **both lanes**, verifyctl's skip strings included (the INERT skipped-string, the zero-lane `allowUnverified` opt-out string, the when-gated extraLanes-miss string — #98):

**Verdict-honesty contract (#98).** The object summary's lanes initialize `skipped` and are promoted on execution — a lane that did not run never reports `clean`/`passed`; `setup` (renamed from the pre-#98 `build` field) reports the `lanes[]` setup outcome. `set-stage 6 --status completed` additionally enforces a content gate on object summaries: at least one verifying lane (`lint`/`typeCheck`/`test`/`ext:*`) must have actually run (`format`/`setup` never satisfy it; absent keys fail). A zero-lane repo either sets `commands.<repo-id>.allowUnverified: true` (verifyctl then emits the opt-out string — only when nothing failed) or the gate refuses with instructions. `commands.<id>.build` remains accepted-but-unexecuted config until #113.

```bash
statectl.sh verify-summary-set "$ISSUE_NUMBER" --json "$VERIFY_SUMMARY_JSON"
```

The Stage-6 completion precondition refuses `set-stage 6 --status completed` without it, and Stage 7's `build-checkpoint-7 --verify-summary` sources the same top-level field (crash-recovery safe). The single-repo `{verifyctl} run {issue-number}` above is the `standalone`/`monorepo` path.

**be-fe-pair (config `topology.type: be-fe-pair`) — verify EACH target repo (#5).** A pair run verifies every repo in `.targetRepos` independently, passing `--repo <id>`:

```bash
if [[ "$(jq -r '.topology.type // "standalone"' "$SECOND_SHIFT_CONFIG" 2>/dev/null || echo standalone)" == "be-fe-pair" ]]; then
  for r in $(statectl.sh get "$ISSUE_NUMBER" '.targetRepos // [] | join(" ")'); do
    VERDICT=$({verifyctl} run "$ISSUE_NUMBER" --repo "$r")   # the exit-code table above applies PER repo
    # On pass, persist THIS repo's summary (both lanes). verifyctl already charged
    # this repo's per-class retry budget itself (worktrees.<r>.verifyAttempts).
    statectl.sh verify-summary-set "$ISSUE_NUMBER" --repo "$r" --json "$VERIFY_SUMMARY_JSON"
  done
fi
```

`--repo <id>` makes verifyctl load **`commands.<id>`** (never the host's), verify **`worktrees.<id>.worktreePath`** against **`worktrees.<id>.base`** (the BE `alpha` / FE `main` cut in Stage 2), use a **per-repo sidecar** (`{issue}-<id>-verify.log`), and charge **`worktrees.<id>.verifyAttempts`**. The Stage-6 completion precondition then requires a `worktrees.<id>.verifySummary` for **every** target — a repo whose verify never ran has no summary, so Stage 6 **cannot complete**. That is the pair "never a silent green" gate (#5): a `[FE]`-touching run is verified with `commands.fe` in the FE worktree, or it fails closed.

### Lane reference (verifyctl consumes this; documented for humans)

A changed file is INERT iff it matches the canonical pattern set in [`tools/is-inert-diff.sh`](../tools/is-inert-diff.sh) (the single source of truth): `*.md` · `*.sh` · `.github/workflows/*.yml` · `.claude/**/*.{mjs,cjs,py,tsv,json,jsonl}` · `.claude/second-shift/.known-extensions` · `.prettierignore` · `.gitignore`. Any non-matching path — `.ts/.tsx/.js/.json` outside `.claude/`, lockfiles, `package.json`, config, CSS, Python, Rust, anything new or unrecognized — selects the SUITE lane (default-to-SUITE when in doubt; never widen the inert list mid-run). verifyctl re-derives the lane on every invocation, so a fix commit that introduces a non-inert file automatically flips the lane.

**Why the `.claude` Workflow scripts are inert.** The dev-pipeline Workflow scripts (the `.mjs`/`.cjs` files under `.claude/skills/.../workflows/`) live outside the yarn workspace tree (`apps/*`, `packages/*`) and are referenced by no `tsconfig` / `eslint` / `jest` config, so the configured lint/type-check/test commands (config `commands.<host>.*`) give them zero coverage — running the suite is pure wasted install+build cost on an otherwise docs/shell diff. Their real verification is the plan-specific commands (syntax wrap-`node --check`, predicate unit tests), which run on both lanes, so marking them inert loses no coverage. A `.mjs`/`.cjs` file anywhere else (e.g. `apps/web/next.config.mjs`) is not matched and still selects SUITE. The repo `.prettierignore` lists the same `.claude/**/*.mjs` glob, so a direct `prettier --check`/`--write` on these paths is a no-op too — the inert-lane decision here and the repo-level prettier contract stay in lockstep. The pre-commit type-check hook (`.claude/hooks/pre-commit-typecheck.sh`) reuses this same `.claude/**/*.{mjs,cjs}` carve-out, kept in lockstep with the single source of truth (`tools/is-inert-diff.sh`) by its `pre-commit-typecheck-selftest.sh`.

**Why `.claude` `.tsv` data files are inert.** A `.tsv` under `.claude/` (e.g. `tools/prose-budget.baseline.tsv`) is pipeline-internal data read only by a shell tool (`prose-budget.sh`) — no `tsconfig`/`eslint`/`jest` config references it, so the configured lint/type-check/test commands (config `commands.<host>.*`) give it zero coverage, and it is outside the prettier format-glob `*.{ts,tsx,js,json,md}` so the INERT-lane `prettier --check` already skips it. Running the suite on a `.tsv`-only diff is therefore pure wasted install+build cost for a guaranteed-identical result. The anchor is deliberately `.claude/`-scoped: a `.tsv` anywhere else (e.g. an `apps/**` test fixture consumed by a `*.test.ts`) is **not** matched and still selects SUITE — the conservative default for files that could feed the JS/TS suite is preserved.

**Why `.claude` `.json` and `.jsonl` data files are inert.** A `.json`/`.jsonl` under `.claude/` — the cost-tracking fixtures (`cost-tracking-fixtures/*.{json,jsonl}` read only by `pipeline-cost-block.sh` / `cost-block-selftest.sh`), `.claude/settings.json`, the audit `.jsonl` ledgers, etc. — lives outside the yarn workspace tree (`apps/*`, `packages/*`) and is referenced by no `tsconfig`/`eslint`/`jest` config, so the configured lint/type-check/test commands (config `commands.<host>.*`) give it zero coverage. That zero-coverage fact (not a narrower "fixture read by a shell tool" framing) is the load-bearing reason and it holds for every `.claude/`-scoped JSON/JSONL, whether or not a shell tool reads it. Running the suite on such a diff is therefore pure wasted install+build cost for a guaranteed-identical result; the real verification is the plan-specific commands (e.g. the cost-block selftest), which run on both lanes. Unlike `.tsv`, `.json` **is** in the prettier format-glob `*.{ts,tsx,js,json,md}`, so the INERT-lane `prettier --check` still checks changed `.json` paths (correct — that is the format gate doing its job); `.jsonl` is outside the format-glob and is skipped, like `.tsv`. The anchor is deliberately `.claude/`-scoped: a `.json`/`.jsonl` anywhere else (`tsconfig.json`, `package.json`, an `apps/**` fixture consumed by a `*.test.ts`) is **not** matched and still selects SUITE — the conservative default for files that could feed the JS/TS suite is preserved.

**Why `.claude` `.py` tooling files are inert.** A `.py` under `.claude/` — the agent-eval-kit harness (`pipeline-state/agent-eval-kit/run-eval.py`) and the per-eval `rubric.py` files — lives outside the yarn workspace tree (`apps/*`, `packages/*`) and is referenced by no `tsconfig`/`eslint`/`jest` config, so the configured lint/type-check/test commands (config `commands.<host>.*`) give it zero coverage. Running the suite on a `.claude/**/*.py`-only code diff is therefore pure wasted install+build cost for a guaranteed-identical result; the real verification is Python tooling (`ruff` / `python -c "import ast; ast.parse(...)"`) run as plan-specific commands, which fire on both lanes. Like `.tsv`/`.jsonl`, `.py` is outside the prettier format-glob `*.{ts,tsx,js,json,md}`, so the INERT-lane `prettier --check` already skips it. The anchor is deliberately `.claude/`-scoped: a `.py` anywhere else (`services/ml-service/**`, covered by `ruff`/`pytest`) is **not** matched and still selects SUITE — the conservative default for files with real test/lint coverage is preserved.

**Why `.claude/second-shift/.known-extensions` is inert.** The consumer extension allowlist is pipeline-internal config read by exactly one reader — `tools/check-extensions.sh` (`ALLOW="$SS/.known-extensions"`, where `SS` is `<root>/.claude/second-shift`). No `tsconfig`/`eslint`/`jest` config references it, so the configured lint/type-check/test commands (config `commands.<host>.*`) give it zero coverage — the same load-bearing rationale as the `.claude` `.tsv`/`.jsonl`/`.py` carve-outs. Being extensionless it is also outside the prettier format-glob `*.{ts,tsx,js,json,md}`, so the INERT-lane `prettier --check` already skips it and no format coverage is lost. Without this carve-out a diff that only adds/edits/deletes the allowlist pays the full SUITE lane for a guaranteed-identical result (observed: a single `.known-extensions` deletion forced SUITE on an otherwise config+Markdown diff). Unlike the extension-scoped carve-outs above, the anchor is the **exact canonical path**, not `.claude/`-wide: `check-extensions.sh` reads this one location and no other, so a same-named file anywhere else (`.claude/other/.known-extensions`, a repo-root `.known-extensions`) is **not** matched and still selects SUITE. This keeps the boundary at _config that cannot affect lint/type-check/test_ rather than widening it to "any extensionless dotfile under `.claude/`" — consistent with the `.npmrc`/`.nvmrc`/`.yarnrc.yml` exclusion noted below.

**Why `.prettierignore` and `.gitignore` are inert.** Changing `.prettierignore` can only alter which files Prettier _skips_; it cannot change the result of the configured lint/type-check/test commands (config `commands.<host>.*`), and the format gate (`prettier --check`/`--write`) is independently scoped to the changed `*.{ts,tsx,js,json,md}` paths, not recomputed from the ignore file. `.gitignore` is the same class: it only alters which paths git _ignores_, never the lint/type-check/test result computed over the working tree (an ignore rule does not untrack already-tracked sources, and the suite runs over the files present). So a `.prettierignore`- or `.gitignore`-only edit is provably suite-irrelevant. The boundary is deliberately narrow — _config that cannot affect lint/type-check/test_, NOT "any extensionless dotfile": `.npmrc`, `.nvmrc`, and `.yarnrc.yml` change toolchain/install behavior and still correctly select SUITE.

### Failure classification (reference — verifyctl classifies; you fix)

| Failure Class      | Signal                                        | Fix Handler                                                          | Charged by  |
| ------------------ | --------------------------------------------- | -------------------------------------------------------------------- | ----------- |
| `FORMAT`           | prettier fails on a changed file              | Usually auto-applied (`formatChanged[]`); a hard failure is a parse error to fix. | verifyctl   |
| `LINT_AUTOFIX`     | ESLint errors                                  | verifyctl runs `--fix` + recheck itself; residual errors come back as a failure to fix. | verifyctl   |
| `TYPE_ERROR`       | the configured type-check command (config `commands.<host>.typecheck`) fails | Read `outputTail`, fix type issue, re-invoke verifyctl.               | verifyctl   |
| `TEST_FAILURE`     | the configured test command (config `commands.<host>.test`) fails with assertion error | Read failing test, fix code or test, re-invoke verifyctl.             | verifyctl   |
| `PLAN_CMD_FAILURE` | A plan-specific verification command fails     | Fix, re-run the command; charge in-session (below).                   | in-session  |
| `INFRA`            | Command not found, OOM, timeout, packages-build/install failure | Surface to user immediately — not auto-fixable, never charged. | never       |

**Retry budget:** Max 2 fix attempts **per failure class**. The four suite classes are tracked by verifyctl's sidecar (a re-invocation after a failed run IS the fix attempt — verifyctl charges it); `PLAN_CMD_FAILURE` is charged in-session via `statectl verify-attempts "$ISSUE_NUMBER" --incr PLAN_CMD_FAILURE` on each fix attempt, compared against the same budget.

**Plan-specific verification commands are in scope — on BOTH lanes.** The plan's "Verification commands" section (selftests, regenerate-and-diff checks, custom scripts) runs **in-session** as part of this stage, after verifyctl passes; the inert lane never skips them. A fix loop on them charges `PLAN_CMD_FAILURE` (tool-missing/environment errors stay `INFRA` — never charged); this class is the in-session carve-out from verifyctl's counter ownership, so the sidecar's fix-attempt detection for the suite classes is never muddied. Running them earlier (during Stage 5) is fine for fast feedback, but a fix loop on them is a verify fix loop regardless of which stage discovered it: track it at that moment.

**INFRA failures are never retried** — fail-fast immediately.

**Approach-failure circuit breaker:** If `TEST_FAILURE` exhausts its budget (verifyctl exit 4, class `TEST_FAILURE`) AND was preceded by another `TEST_FAILURE` exhaustion in the same Stage 5→6 implement-verify cycle (two consecutive exhaustions with no clean run in between), treat this as a fundamental approach mismatch rather than a fixable bug. The fix-attempt loop will not converge by churning; stop.

- **If a failure class exhausts its budget — verifyctl exit 4 (autonomous default):**
  - Comment on issue via `$GH_BOT issue comment` with the verdict JSON's failure detail (`stage: verify`, `status: failed`).
  - Write the failureContext atomically:

    ```bash
    # For approach-failure (two consecutive TEST_FAILURE exhaustions):
    statectl.sh mark-failed "$ISSUE_NUMBER" \
      --reason approach-failure-circuit-breaker --stage 6 \
      --json "$(statectl.sh build-failure-context \
        --reason approach-failure-circuit-breaker --stage 6 \
        --kv failureClass="$FAILURE_CLASS" \
        --kv errorTail="$ERROR_TAIL")"

    # For any other budget exhaustion (TYPE_ERROR, PLAN_CMD_FAILURE, single-shot
    # TEST_FAILURE without the consecutive-exhaustion pattern), no closed-enum
    # reason exists yet — comment-only path; do NOT call mark-failed (would fail
    # closed-enum validation). Operator inspects the issue comment and clears
    # state manually.
    ```

  - Keep worktree + branch for manual rescue.
  - **STOP** with rc=0. Do not remove `in-progress` — the issue needs manual attention.

- **Under `DEV_PIPELINE_MODE=interactive`:** skip the `mark-failed` write; surface the failure to the user with the full error output and ask how to proceed.

## Quality pass — "make it good" (advisory, once per run)

After the suite is green, run a single bounded cleanup pass over the branch diff — make it work, then make it good. The pass is **advisory**: it never prompts, never retries, never increments `verifyAttempts`, never invokes `mark-failed`, and never blocks `set-stage 6 --status completed`. Identical under `auto` and `interactive` (no failure path, no prompt).

**Once-per-run guard.** If `stages.6.qualityPass.runId` equals the state file's `.runId`, skip this entire section — Stage 8's review loop re-runs verify after fixing blockers, and the pass must not re-fire. Otherwise, BEFORE touching any file, write:

```bash
statectl.sh quality-pass-set "$ISSUE_NUMBER" \
  --json "{\"runId\": \"$RUN_ID\", \"status\": \"running\"}"
```

**Scope.** SUITE lane only — on the INERT lane record `{runId, status: "completed", outcome: "skipped-inert"}` and move on. The cleanup surface is the same merge-base diff verifyctl derives — read `base`/`mergeBase` from the verdict JSON rather than re-deriving; on stacked slices this is the persisted `worktreeBase`, never the bare base branch (prior slices' code is out of scope).

Apply-scope rules:

- Edits confined to files in the diff. Importing an existing out-of-diff helper is allowed; modifying out-of-diff files is not — record such extractions as suggestions instead.
- On `designDriven` runs, `apps/web` files implemented by the design-toolkit:design-faithful engine are excluded from apply scope (a cleanup there would leave the Stage-5 live-render fidelity unverified). Suggestions only.
- Behavior-preserving edits only. No bug-hunting — a suspected bug is Stage 8's job, not a cleanup.

**Checklist (quality only — reuse / simplification / altitude):**

- Reuse over reinvention: check every helper/method this diff introduced against the plan's **Reuse inventory** and a grep of the codebase — replace near-duplicates with the existing utility.
- Dead code / unused exports introduced by this diff. On stacked slices, consult the decomposition plan first — an export provisioned for a later slice is NOT dead.
- Collapse over-abstraction this diff introduced (single-use wrappers, needless indirection, speculative generality).
- Altitude: logic sitting at the wrong layer within the changed files.
- Skip style-only churn the formatter/linter owns.

**Apply + commit.** If no cleanups are warranted, record `{runId, status: "completed", outcome: "no-candidates"}` and move on — no commit, no re-verify (zero cost; the common case). Otherwise apply the cleanups, run the scoped prettier on the touched files (discard unrelated-file formatting), and land **at most one commit**: `refactor(scope): <summary>` via bot identity (`bash "${CLAUDE_PLUGIN_ROOT}/skills/run/tools/bot-commit.sh" -C "$WT" -m ...` — a bare `git commit` silently uses the operator identity). If the pre-commit `type-check` hook rejects the commit, discard the edits (`git -C "$WT" checkout -- .`) and record `outcome: "reverted"` — no retry. Immediately after a successful commit, record `{runId, status: "running", outcome: "applied-unverified", commitSha: "<sha>"}` — the sha makes crash rollback deterministic.

**Safety-net re-verify (one shot).** Run `{verifyctl} run {issue-number} --no-attempt` — the `--no-attempt` contract is load-bearing: no budget check, no `verifyAttempts` increment, no sidecar write (read-only accounting posture; a red safety net followed by the reset leaves accounting byte-identical to the pre-cleanup state).

- Green → finalize `outcome: "applied"` + one-liners per cleanup in `applied[]`.
- Red → `git -C "$WT" reset --hard {commitSha}^` (the commit is unpushed and terminal; reset restores the byte-identical already-verified tree — no third verify run, no revert-commit noise in the PR) → `outcome: "reverted"`. NEVER iterate on a red safety net, NEVER increment `verifyAttempts`.

**Suggestions.** Out-of-apply-scope cleanups worth a human's eye (cross-file extraction, design-faithful candidates) go to `suggestions[]` — max 3 one-liners; drop the rest.

Finalize with one closing write, e.g.:

```bash
statectl.sh quality-pass-set "$ISSUE_NUMBER" --json "{
  \"runId\": \"$RUN_ID\", \"status\": \"completed\", \"outcome\": \"applied\",
  \"commitSha\": \"$SHA\", \"applied\": [\"...\"], \"suggestions\": []
}"
```

Stage 7 composes `qualityPassSummary` from this state (so a fresh-session crash-recovery resume loses nothing); a `reverted` outcome additionally gets a `deviations[]` `{kind: "surprise"}` entry at Stage 7 (a reset leaves no branch trace — the ledger is the only disclosure).

**Crash-recovery resume.** Re-entering Stage 6 with `qualityPass.status == "running"`: discard uncommitted changes in the worktree; if `outcome` is `applied-unverified`, `git -C "$WT" reset --hard {commitSha}^` and set `outcome: "reverted"`; set `status: "completed"` and proceed. Never re-attempt the pass — advisory work is not worth a resume loop.

**State:** the four suite-class `verifyAttempts` increments are verifyctl-owned (sidecar-driven); `PLAN_CMD_FAILURE` is the one in-session `verify-attempts` write. `stages.6.qualityPass` is written via `statectl quality-pass-set` (never raw jq). On pass, `verify-summary-set` precedes `set-stage 6 --status completed` (completion precondition); the quality pass never blocks that write.

#### Visual capture (render-surface changes only)

After the verify commands above pass, capture rendered screenshots so the next reviewer (LLM or human) sees the page, not just the diff. **Observation only — no assertion, no retry, no failure class, never blocks the pipeline.** The point is to surface renders when they are cheaply available, not to gate on a brittle heuristic. (This stays in-stage prose — Playwright MCP tools cannot run inside a bash runner.)

**Resolve `stageParams.visualCapture` (default = the shipped literals).** Read the capture constants from the consumer config once. Every key is optional; an absent key (an empty config) resolves to exactly today's value, so the default case is byte-for-byte unchanged:

```bash
# baseUrl (default "http://localhost:3001/") and devServerCommand (default "yarn dev").
VC_BASE_URL=$(jq -r '.stageParams.visualCapture.baseUrl // "http://localhost:3001/"' "$SECOND_SHIFT_CONFIG" 2>/dev/null || echo "http://localhost:3001/")
VC_DEV_SERVER_CMD=$(jq -r '.stageParams.visualCapture.devServerCommand // "yarn dev"' "$SECOND_SHIFT_CONFIG" 2>/dev/null || echo "yarn dev")
# smokeRoutes (default ["/"]) and viewports (default ["mobile","tablet","laptop"]) — newline-delimited.
VC_SMOKE_ROUTES=$(jq -r '(.stageParams.visualCapture.smokeRoutes // ["/"]) | .[]' "$SECOND_SHIFT_CONFIG" 2>/dev/null || echo "/")
VC_VIEWPORTS=$(jq -r '(.stageParams.visualCapture.viewports // ["mobile","tablet","laptop"]) | .[]' "$SECOND_SHIFT_CONFIG" 2>/dev/null || printf 'mobile\ntablet\nlaptop\n')
# triggerGlobs (default = the shipped render-surface globs) — newline-delimited.
VC_TRIGGER_GLOBS=$(jq -r '(.stageParams.visualCapture.triggerGlobs // ["apps/web/src/app/**/*.{tsx,jsx}","apps/web/src/app/**/*.css","apps/web/src/components/**/*.{tsx,jsx}","apps/web/tailwind.config.{ts,js}"]) | .[]' "$SECOND_SHIFT_CONFIG" 2>/dev/null || printf 'apps/web/src/app/**/*.{tsx,jsx}\napps/web/src/app/**/*.css\napps/web/src/components/**/*.{tsx,jsx}\napps/web/tailwind.config.{ts,js}\n')
```

**Viewport name → pixel dimensions (owned by the stage, not config).** `viewports` carries only names from the closed enum (`mobile` · `tablet` · `laptop` · `desktop`); this stage maps each name to its `WIDTHxHEIGHT`. The map lives here so config stays pure names:

| Name      | Dimensions  |
| --------- | ----------- |
| `mobile`  | 375 × 812   |
| `tablet`  | 768 × 1024  |
| `laptop`  | 1480 × 900  |
| `desktop` | 1920 × 1080 |

```bash
declare -A VC_VIEWPORT_DIMS=(
  [mobile]="375x812" [tablet]="768x1024" [laptop]="1480x900" [desktop]="1920x1080"
)
```

**Trigger.** Run the capture only if `git diff --name-only` against the PR base contains any path matching one of the resolved `$VC_TRIGGER_GLOBS`. The default set (config `stageParams.visualCapture.triggerGlobs` overrides it) is:

- `apps/web/src/app/**/*.{tsx,jsx}`
- `apps/web/src/app/**/*.css`
- `apps/web/src/components/**/*.{tsx,jsx}`
- `apps/web/tailwind.config.{ts,js}`

If the diff contains only paths matching none of `$VC_TRIGGER_GLOBS` (with the default set, e.g. `apps/web/src/lib/**/*.ts`, `apps/web/src/hooks/**/*.ts`, `apps/web/src/types/**`, `apps/web/**/*.test.{ts,tsx}`, `apps/web/**/*.spec.{ts,tsx}`, `apps/web/next.config.{mjs,js,ts}`, `apps/web/**/*.md`, `apps/web/public/**`), skip silently.

**Capture procedure.**

1. Start the dev server (`$VC_DEV_SERVER_CMD` — default `yarn dev` — from repo root, run in background) and wait for `$VC_BASE_URL` (default `http://localhost:3001/`) to respond — 60 s timeout.
2. For each `(route, viewport)` pair — the Cartesian product of the resolved `$VC_SMOKE_ROUTES` × `$VC_VIEWPORTS`, each route joined onto `$VC_BASE_URL` and each viewport name resolved to `WIDTHxHEIGHT` via `VC_VIEWPORT_DIMS`: `mcp__playwright__browser_navigate` → `mcp__playwright__browser_resize` → `mcp__playwright__browser_take_screenshot`. Save to `.claude/pipeline-state/{ISSUE_NUMBER}-screenshots/{route-slug}-{viewport-width}.png` (route `/` → `root`). With the default config this is exactly:
   - `/` × 375 × 812 (mobile)
   - `/` × 768 × 1024 (tablet)
   - `/` × 1480 × 900 (laptop)
3. The smoke-route list defaults to exactly `/` (the resolved `$VC_SMOKE_ROUTES`). User-scoped routes are deliberately out of the default set — without a dev-auth posture, navigating to them silently measures the login page; a repo that has solved dev-auth opts them in via `stageParams.visualCapture.smokeRoutes` rather than editing this skill.

**Sanctioned fallback — headless Chrome.** When the Playwright MCP tools are absent from the session (the `playwright-error` class before any call is even possible), do NOT skip straight away if a Chrome binary is available: capture the same route × viewport matrix with `chrome --headless=new --window-size=WxH --screenshot=<path> <url>`. Caveat (observed in a retro): Chrome clamps its window to ~500px minimum width, so the 375px `mobile` viewport is unattainable — capture at the clamped width, name the file by the ACTUAL width (e.g. `root-500.png`, never a mislabeled `root-375.png`), and log one line: `visual-capture: substituted — headless Chrome for Playwright MCP (unavailable); mobile clamped to <W>px`. The substitution is a disclosed deviation (record it in the Stage-7 `deviations[]`), not a silent skip. With neither Playwright nor Chrome, take the failure handling below.

**Failure handling.** If the dev server fails to start, the route fails to load, or any Playwright call errors, append one line to the **Stage 6 log** and `echo` the same line to stdout, then proceed to Stage 7 Doc Update.

- **Log file:** `.claude/pipeline-state/${ISSUE_NUMBER}-stage6.log` (inside the already-gitignored `.claude/pipeline-state/` tree, which exists by Stage 6 since Stage 1 wrote the state file). This is an operator/eval breadcrumb with **no programmatic reader** — nothing downstream parses it; it is the human-readable trail for "why was there no screenshot?".
- **Line format (exactly one line per skip):** `visual-capture: skipped — <reason>` where `<reason>` is one of `dev-server-timeout`, `route-load-failed`, or `playwright-error`, optionally followed by `: <underlying error>`. Example: `visual-capture: skipped — dev-server-timeout: no response on http://localhost:3001/ within 60s`.

```bash
# Illustrative — REASON and DETAIL are set by the calling capture step:
#   REASON ∈ {dev-server-timeout, route-load-failed, playwright-error}
#   DETAIL = the underlying error string (may be empty)
echo "visual-capture: skipped — ${REASON}${DETAIL:+: $DETAIL}" \
  | tee -a ".claude/pipeline-state/${ISSUE_NUMBER}-stage6.log"
```

Visual capture has no retry budget, no `verifyAttempts` entry, no failure class. A skipped capture means Stage 9 omits the `## Visual Verification` section from the PR body entirely — it does NOT emit a section with a "capture failed" note. **Absence of the section is the load-bearing signal**; the Stage 6 log is supplementary diagnostics only.

On verify success, proceed to **Stage 7 Doc Update**.

---

_Stage 6 of the [dev-pipeline](../SKILL.md) flow. Return to the router for cross-stage contracts (Invocation Routing, Failure Contract, State Persistence, etc.)._
