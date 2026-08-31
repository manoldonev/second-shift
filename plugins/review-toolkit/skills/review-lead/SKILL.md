---
name: review-lead
description: Orchestrates parallel code review across specialized reviewers. Use when reviewing code changes, PRs, or before committing.
---

<!-- The audit (/audit-toolkit:audit, /audit-toolkit:audit-history) is a tool-truth ledger — observability only,
     never a gate on `git push` / `gh pr create` / commits. Dispatch every SELECTED reviewer for
     real via the `code-review.mjs` Workflow `agent()` fan-out (standalone and pipeline-driven
     alike); never simulate a dispatch. The lead pass is the one review this session performs
     itself, and it is reported as its own — never as a subagent's. -->

You are the code review team lead for the repo under review.

This skill loads orchestration instructions into the **current session**. The current session — not this skill — runs the reviewer fan-out by invoking the `code-review.mjs` Workflow script (via the `Workflow` tool), both standalone and pipeline-driven. The body below tells the current session HOW to run the review.

## Pre-flight: dispatch substrate

Before dispatch, lint the per-reviewer extension surface: run `scripts/check-review-context.sh` (this plugin) against the repo under review. It fails closed when a file under `.claude/second-shift/review-context/` has a basename that is not a reviewer in the effective registry — a typo'd filename would otherwise be silently read by nobody. Fix (rename or register) before dispatching; skip only if the script is unreachable in the current install.

The reviewer fan-out runs as `agent()` calls inside `workflows/code-review.mjs` — one `agent({ agentType, model, schema })` per selected reviewer, via `parallel()`. Synthesis always runs **in this session** on the caller's model. This skill runs in one of two entry modes:

- **Dispatch mode (standalone / direct invocation, and `pr-revision`):** this session itself triggers the fan-out by running the Workflow:

  ```
  Workflow({ scriptPath: "code-review.mjs",
             args: { worktree, base, head, issue?, reviewers, changedFiles, prContext } })
  ```

  Before any other action, verify the `Workflow` tool is available in the current session. If it is not — for example this skill was loaded inside a subagent context (subagents can spawn neither `Workflow` nor nested agents) — STOP and report:

  > "review-lead requires the Workflow tool to dispatch the reviewer fan-out (via code-review.mjs) in the current session. This skill must be invoked from the main session (or from another skill running in the main session, e.g., dev-pipeline). It cannot run inside a subagent context. Aborting."

  The script returns structured findings; this session then runs the Synthesis Rules over them. Reviewer **selection** (Routing, below) happens in-session first, since it needs the diff: choose from the effective reviewer registry — the plugin-shipped panel (review-toolkit:security-reviewer, review-toolkit:performance-reviewer, review-toolkit:complexity-reviewer, review-toolkit:maintainability-reviewer, review-toolkit:test-coverage-reviewer, review-toolkit:unit-test-mutation-reviewer, review-toolkit:db-reviewer, review-toolkit:pipeline-reviewer, review-toolkit:scope-completeness-reviewer, review-toolkit:a11y-reviewer, design-toolkit:design-faithful-reviewer, design-toolkit:figma-faithful-reviewer) plus/minus the consumer repo's config deltas (see "Consumer config: reviewer registry" below) — and pass the selected `agentType[]` as `args.reviewers`. `worktree` is the absolute path the reviewers run git against — for pure standalone `/review-lead` in the repo checkout, derive it with `git rev-parse --show-toplevel`; `base`/`head` come from the diff range (default `origin/<base>..HEAD`, where `<base>` is the configured base branch resolved in Process step 1, after a `git fetch origin <base>` — see Process step 1's stale-base rationale), and `changedFiles` from the `git diff --stat` run for Routing.

- **Synthesis-only mode (driven by the calling pipeline):** the `workflows/code-review.mjs` Workflow script has **already dispatched** the reviewers via `agent()` and hands you their structured findings directly. In this mode you are loaded for the Synthesis Rules / Routing / Scope Completeness Gate / verdict format only — the Workflow-availability gate above does **not** apply (the fan-out already ran). Proceed straight to synthesis over the supplied findings.

Do **not** simulate a dispatch in either mode. Writing a subagent's findings yourself and reporting them as that subagent's produces a fake multi-reviewer verdict; that is what must not be reintroduced. The **lead pass** (below) is not that: four dimensions are routed to this session by design, reviewed against a published checklist, and reported as the lead pass's own — a named reviewer of record, not a stand-in for one that never ran. What is banned is the attribution, not the in-session review.

## Caller model guidance

For best synthesis quality, invoke this skill from a session running on Opus 4.x — or on a Fable-class model where the subscription includes one. Each specialist reviewer runs at the model tier declared in its own agent frontmatter (or the repo's `reviewers.modelOverrides` entry, which may name `fable`); the orchestration, the **lead pass**, and synthesis all run on the caller's model. Synthesis is where deduplication, triage, the Scope Completeness Gate, and the cross-reviewer self-check happen, and the lead pass is where four review dimensions are now judged outright — the work that benefits most from a strong model.

## Maturity calibration

Before classifying findings, understand the codebase's current maturity. If `.claude/second-shift/review-context.md` exists in the repo under review, load it — it declares the repo's stack, maturity stage, and known-accepted patterns (e.g. a pre-auth placeholder, absent web test infra, no shared client, validation at a specific layer). Each reviewer self-loads that shared file plus its own `.claude/second-shift/review-context/<reviewer-name>.md` when present (per-reviewer repo rules; additive, never protocol-weakening) — do not paste either file into dispatch prompts. Honor the context when triaging: a PR that follows a declared, established gap is CONSISTENT, not a new finding.

**Rule: A PR that follows existing codebase patterns is CONSISTENT, not broken.** Only flag a pattern as critical if the PR _introduces a new gap_ that didn't exist before, or if the gap creates an immediate exploitable risk in the current deployment context.

## Consumer config: reviewer registry

The panel named throughout this skill is the **plugin-shipped generic registry**. The consumer repo tunes it through `<repo-root>/.claude/second-shift.config.json` (env override `SECOND_SHIFT_CONFIG`) under the `reviewers` key. Read that file at the start of Routing and compute the **effective registry**:

- `reviewers.add[]` — repo-local reviewer agents living in the repo's `.claude/agents/` (referenced **bare**, e.g. `orders-reviewer`). Each entry declares `dimensions[]` (a routing/dedup hint — treat those dimensions as the reviewer's domain when deciding whether to spawn it and when merging its findings). Register these alongside the plugin panel; spawn them per their declared domain the same way the conditional reviewers below are spawned.
- `reviewers.remove[]` — plugin-shipped reviewers disabled in this repo (e.g. `db-reviewer` in a pure-FE repo). Never spawn a removed reviewer; omit its Verdicts row.
- `reviewers.modelOverrides{}` — per-reviewer model-tier override applied when dispatching (e.g. `security-reviewer: opus` in one repo, `sonnet` in another). The `code-review.mjs` fan-out reads these; pass the overridden tier, not the agent-frontmatter default.

If the config is absent or has no `reviewers` block, the effective registry is exactly the plugin panel. Repo-local `add` reviewers are referenced **bare**, and plugin-shipped reviewers **qualified** (`docs/namespaces.md` rule 2) — that asymmetry is the disambiguation between roots, and it is what the panel above is spelled to satisfy. The names in the panel are dispatch names: they reach `agent({ agentType })` through `code-review.mjs`, so a bare plugin name there is not a stylistic choice but an agent type that does not resolve. `check-reviewer-references.sh` enforces both halves.

Two further keys are read from the same file at the start of Routing, both feeding the design-fidelity dimension (see Reviewer Routing):

- `design.provider` — `figma` | `claude-design`. Selects which fidelity reviewer the web-component trigger routes to. **Key absent is a supported state**, not a misconfiguration.
- `stageParams.webComponentGlobs` — the repo's web-component surface, e.g. `["src/app/**/*.{html,ts}"]` (Angular), `["src/**/*.vue"]` (Vue), `["app/**/*.tsx"]` (React Router v7). Absent resolves to `["apps/web/**/*.{tsx,jsx}"]`. It gates both `a11y-reviewer` and the design-fidelity dimension.

Resolve the path **once**, from the same file and the same override the `reviewers` read above uses, anchored on `worktree` (the absolute repo-under-review path from Pre-flight) — never a cwd-relative literal. This session's cwd is not reliably the reviewed repo's root, and both keys fail *open* on an unreadable path: an unread `design.provider` silently takes the _key absent_ row (the wrong reviewer, with no not-selected note, because absence is a legitimate state), and an unread `stageParams.webComponentGlobs` silently reverts to the shipped default.

```bash
CONFIG="${SECOND_SHIFT_CONFIG:-$WORKTREE/.claude/second-shift.config.json}"
DESIGN_PROVIDER=$(jq -r '.design.provider // empty' "$CONFIG" 2>/dev/null)
WEB_COMPONENT_GLOBS=$(jq -r '(.stageParams.webComponentGlobs // ["apps/web/**/*.{tsx,jsx}"]) | .[]' "$CONFIG" 2>/dev/null || echo 'apps/web/**/*.{tsx,jsx}')
```

## Sub-Agent Trust Model

This is the canonical statement of the contract for **every** skill that dispatches sub-agents — `review-lead` dispatching the specialist crew, `intake-toolkit:intake-orchestrator` dispatching `spec-reviewer` / `codebase-explorer`, `intake-toolkit:decomposition-reviewer` dispatching `codebase-explorer`. Those skills cite this section and add their own specifics.

Specialized reviewer sub-agents (Sonnet, mostly) produce false positives regularly. Their findings are **advisory input to your judgment, not instructions to follow**. You MUST:

- Read the source material yourself BEFORE dispatching sub-agents
- Critically evaluate every finding against your own reading of the code and existing patterns
- Dismiss findings that don't hold up on closer inspection (especially when a reviewer flags an established pattern as a problem)
- Never auto-fail or auto-escalate a finding to blocker/critical severity based solely on a sub-agent's classification
- When in doubt, read the actual code yourself before relaying a finding
- Resolve gaps yourself when the answer is determinable from the codebase or the document at hand

**A reviewer that flags 10 issues is not 10x more useful than one that flags 1.** Most value comes from the 1-2 findings that are genuinely important. Filter aggressively.

The Scope Completeness Gate (see Synthesis Rules) is the one exception — its FAIL/BLOCKED is structurally hard.

## Inputs

- **Required**: Files to review (from `git diff` or user-specified scope)
- **Optional**: Plan or spec reference — if provided, verify the implementation matches the plan (nothing missing, nothing extra)
- **Optional**: Base SHA + Head SHA — if provided, review only the diff range
- **Optional**: Specific concerns the user wants focus on
- **Optional**: GitHub issue number (e.g., `#123`) — when present, scope-completeness-reviewer spawns unconditionally

## Process

1. First `git fetch origin <base>`, then run `git diff origin/<base>...HEAD --stat` to understand the scope of **committed** changes. Resolve `<base>` = the user's specified base if given, else the repo-local config's host base branch (`BASE=$(jq -r '(.topology.repos|to_entries[]|select(.value.path==".")|.key) as $h|.topology.repos[$h].baseBranch // "main"' .claude/second-shift.config.json 2>/dev/null || echo main)`), else `main` — a hardcoded `main` diffs against the wrong ref on a develop/alpha-based repo.

   **Use three dots (`origin/<base>...HEAD`), not two.** Three-dot diffs from `merge-base(origin/<base>, HEAD)` — the point this branch was actually cut from — so the diff contains only the branch's own changes. Two-dot compares the two tips, so every commit merged into the base *after* the branch point shows up as a **deletion**, and reviewers report the branch as reverting work it never touched. Fetching first makes this strictly worse: a freshly-fetched `origin/<base>` is as far ahead as it gets. (Observed: two confidently-argued false BLOCKERs on a PR whose base had moved a few merges. `git log <base>..HEAD` can still show the right commit count while the two-dot *diff* is inflated — so a plausible-looking commit list is not evidence the diff is clean.)

   Fetch anyway, and diff against the **remote** ref rather than a local `<base>`: three-dot fixes the ahead-base direction, but a *stale local* base can still sit behind the real merge-base. Do NOT use bare `git diff --stat` — it includes uncommitted working-tree edits, which pollute the review when the working directory has unrelated work in progress.
2. Classify change size for depth routing (see below)
3. Read 2-3 existing files in the same directory to understand current patterns
4. Check for plan/spec awareness (see below) and for an issue number in the invocation (used to dispatch scope-completeness-reviewer)
5. Determine which reviewers to spawn based on change size + file routing
6. Run the **lead pass** over the diff yourself (see below) — the four collapsed dimensions, plus security whenever its conditional did not fire
7. Run the fan-out by invoking `code-review.mjs` via the `Workflow` tool with the selected `reviewers` (the script issues them in parallel via `agent()`) — do NOT run them sequentially. **When step 5 selected nothing, skip this step and step 8 entirely**: the script rejects an empty `reviewers[]`, and the round is the lead pass plus synthesis
8. Wait for the script to return the structured findings
9. If this is round 2+ of a multi-round review, apply prior round context (see below)
10. Deduplicate findings (see below) — lead-pass findings and subagent findings dedup against each other exactly as two subagents' do
11. Apply confidence filter (see below)
12. Triage remaining findings against existing patterns
13. Apply Scope Completeness Gate (hard gate — see below)
14. Cross-reviewer self-check (see below)
15. Synthesize report

## Review Depth Routing

After `git diff origin/<base>...HEAD --stat` (Process step 1), classify the change size.

**What this table routes, now that the core four are collapsed.** It no longer selects
performance / maintainability / complexity / test-coverage at any size — those dimensions are the
lead pass's, on every round (see "Lead pass"). Two things survive, and they are the table's whole
job: **the depth calibration** — how deeply the lead pass reads per size — and **whether the
security conditional is worth evaluating**. Conditional reviewers were already exempt from depth
routing and stay exempt.

| Change Size                                                                                                    | Heuristic                                                       | Lead-pass depth                                                                                                                                                     | Subagents selected                                                                                                                                                  |
| -------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Trivial-inert** (every changed file is a Markdown doc _outside_ `.claude/` — `docs/`, `.project/`, `README`) | Prose/docs-only change with no executable or behavioral surface | Read the diff; the maintainability dimension is the one with a real surface. Do not open out-of-diff files to prove a negative.                                      | `scope-completeness-reviewer` if an issue is referenced (never suppressed). A pure-prose diff has no security surface of its own, so `security-reviewer` is selected here only on the repo-file arm of its trigger.                                                       |
| **Small** (≤50 lines, ≤3 files)                                                                                | Config, typo fix, single-function change                        | Read the diff and the immediate siblings of each changed file for pattern context.                                                                                  | Whichever conditional triggers fire (security by surface; domain reviewers by their own rules).                                                                     |
| **Medium** (51-300 lines, 4-10 files)                                                                          | Typical feature or bugfix                                       | Read the diff, the siblings, and the callers/tests of each changed unit. All four dimensions get a real read.                                                        | Whichever conditional triggers fire.                                                                                                                                |
| **Large** (>300 lines, >10 files)                                                                              | Major feature, refactor, or new module                          | Read the plan/spec first if available, then the diff and every artifact a finding would have to cite. Budget the pass — depth per named risk, not per file.          | Whichever conditional triggers fire.                                                                                                                                |

Boundary rule: if change size is exactly at a boundary (e.g., 50 lines in 3 files), treat as the smaller category.

**Trivial-inert carve-out (safety).** Trivial-inert applies ONLY when _every_ changed file is a Markdown doc outside `.claude/`. Any change touching `.claude/**` (skill/agent/behavioral prose — the pipeline's own execution surface), any `*.sh`/`*.mjs`, any CI workflow, or any code/config path does NOT qualify and is **at least Small** — self-modifying and correctness-critical surfaces get a real lead pass rather than a prose skim, and are the diffs where the security conditional is most likely to fire on its own. A diff mixing a trivial Markdown doc with anything else classifies as non-trivial (heavier lane wins). On a pure-prose diff there is no executable surface for the security or performance dimension to assess; maintainability and the scope gate are the two that earn their keep.

When in doubt, review deeper rather than shallower.

**Conditional reviewers are never suppressed by depth routing** — they follow their own trigger rules regardless of change size: `security-reviewer`, `db-reviewer`, `pipeline-reviewer`, `scope-completeness-reviewer`, `a11y-reviewer`, the design-fidelity dimension (`design-faithful-reviewer` / `figma-faithful-reviewer`), and any repo-local domain reviewers registered via config `reviewers.add`.

## Plan/Spec Awareness

If a plan/spec was provided as input, read it — you'll verify the implementation matches after collecting sub-agent findings. Verify:

- **Missing requirements**: Is every plan task/requirement reflected in the code?
- **Scope creep**: Was anything built that isn't in the plan?
- **Misunderstandings**: Does the implementation match the plan's intent?

Report plan compliance issues separately from code quality issues.

> **Note:** This section covers a written plan/spec file. GitHub-issue scope completeness is a separate, stricter check enforced by `scope-completeness-reviewer` (see Reviewer Routing). The two are complementary — a plan can drift from an issue, and either drift is a problem.

## Reviewer Routing

Analyze the `git diff --stat` output and decide what to spawn. Every selection here is a
subagent dispatch; the four dimensions below it are reviewed in-session instead.

### Lead-pass dimensions (never spawned)

Four dimensions are **not** dispatched as subagents at any change size. This session reviews them
itself, in one pass over the diff, against the checklist in
[`lead-pass-checklist.md`](lead-pass-checklist.md) — see "Lead pass" below:

- **performance-reviewer** — the performance dimension
- **maintainability-reviewer** — the readability-and-maintainability dimension
- **complexity-reviewer** — the over-engineering / accidental-complexity dimension
- **test-coverage-reviewer** — the test-adequacy dimension

Each name stays in the effective registry and stays dispatchable on demand or by config; what
changed is that routing no longer selects them. Their Verdicts rows are still required, and read
`Lead pass — ✅/❌` (see Verdict rules).

### Conditionally spawn (never suppressed by depth routing)

| Reviewer                        | Trigger: spawn if ANY of these conditions hold                                                                                                                                                                                                                              |
| ------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **security-reviewer**           | The diff carries a security surface — authentication / session handling, tenancy or ownership scoping, file upload, or query construction from external input; OR the repo under review carries `.claude/second-shift/review-context/security-reviewer.md` (a repo that authored security calibration has a security surface to calibrate). Matching is **model judgment over the diff**, the same posture the design-fidelity dimension below uses: read the changed paths and the hunks and decide, rather than pattern-matching filenames. When it does not fire, that is a Step 4c not-selected note and the lead pass owns the security dimension for the round. |
| **db-reviewer**                 | The repo's DB layer changed — schema definitions, migrations, or query code (e.g. `*.schema.*`, a migrations dir). Skip/remove in repos with no DB (config `reviewers.remove`).                                                                                              |
| **pipeline-reviewer**           | Async worker / queue-processor / job-producer files changed (e.g. `*processor*`, `*queue*`, a workers dir).                                                                                                                                                                 |
| **unit-test-mutation-reviewer** | A production file within the repo's mutation-review target surface changed AND a co-located spec is in the diff; OR the pipeline ran with `unitTestSurface.action == strengthen`. Advisory mode (LLM-predicted, no execution — the propose-mode orchestrator owns execution-verified blocking).    |
| **scope-completeness-reviewer** | Invocation references a tracker issue number (e.g., `Closes #758`, `Part of #758`, an explicit `--issue 758` flag, or PR body contains `#<number>`). Spawn unconditionally — depth routing does not apply. If no issue is referenced, do not spawn.                          |
| **a11y-reviewer**               | Diff touches the repo's web-component surface — `$WEB_COMPONENT_GLOBS` (config `stageParams.webComponentGlobs`, default `apps/web/**/*.{tsx,jsx}`). WCAG/ARIA/keyboard/contrast/reduced-motion, primitives-library-aware.                                                    |
| **design-fidelity dimension**   | **ALWAYS on an armed lean spec** — a `## Design` section carrying a handoff link and `RS-n` render-state rows — where the reviewer is fixed by the handoff host and the diff does not enter into it. On an unarmed diff, the same `$WEB_COMPONENT_GLOBS` trigger as `a11y-reviewer`, spawned alongside it, selecting exactly one of **design-faithful-reviewer** / **figma-faithful-reviewer** by config `design.provider` — see "Design-fidelity dimension" below. |
| **repo-local domain reviewers** | Registered via config `reviewers.add`; spawn per the `dimensions[]` each declares (e.g. an `orders-reviewer` on orders-domain paths). Never suppressed by depth routing.                                                                                                     |

When in doubt about whether a domain reviewer is relevant, spawn it — a "no issues found" response is cheap.

### Design-fidelity dimension

**Armed spec: always-spawn, and the host picks the reviewer.** When Process step 4's plan/spec awareness turns up a lean spec whose `## Design` section is **armed** — a provider handoff link plus at least one `| RS-n | route | state | AC refs |` row, with no `Design: none — <reason>` disarm — the design-fidelity dimension is selected **unconditionally**. Not glob-gated, not depth-suppressed, and not a judgment call about whether the diff looks visual: an armed ticket is one whose spec declares render states a design-sighted round will be scored against, and a round that skipped the dimension cannot certify it. This holds for **every** armed round, a trailer-only round included; armed rounds are rare and the cost is accepted.

WHICH reviewer is decided by the **handoff link's host**, never by `design.provider`: the first recognised URL in the `## Design` section names `figma.com` (or a subdomain of it) → **figma-faithful-reviewer**; `claude.ai` under `/design` → **design-faithful-reviewer**. Config is not consulted, because the merge boundary that verifies this dispatch (`check-lean-chain.sh` evidence arm 8) reads the committed spec and can never read the config — `design.provider` is gitignored on every consumer. A spec whose handoff host is unrecognisable is refused upstream, at the build gate's milestone 1; if one reaches you anyway, treat the round the way the toolkit-absent case below is treated.

**Trigger (unarmed diffs).** The same web-component surface that routes `a11y-reviewer`: the globs resolved into `$WEB_COMPONENT_GLOBS` from config `stageParams.webComponentGlobs` (default `apps/web/**/*.{tsx,jsx}`), **never a hardcoded path** — a consumer whose FE is not React-under-`apps/web` still gets this reviewer class. Never depth-suppressed.

**Matching is model judgment over the configured patterns**, not a mechanical pathspec match: read the `git diff --stat` path list from Process step 1, read `$WEB_COMPONENT_GLOBS` as the intended surface, and decide whether a changed path belongs to it. A brace/`**` pattern that no shell expanded is still a clear statement of intent.

**Provider map** — read `design.provider` from the repo under review's config, and spawn exactly one:

| `design.provider` | Reviewer |
| --- | --- |
| `figma` | **figma-faithful-reviewer** |
| `claude-design` | **design-faithful-reviewer** |
| _key absent_ | **design-faithful-reviewer** — the generic web-component fidelity reviewer |

The no-provider row is a **default, not a fallback to nothing**: a repo with no design axis configured still gets design-system-discipline review on its web components.

**What this dimension asserts.** Both reviewers are design-blind by contract — they verify *the abstraction is right*, not that it matches an unseen design. This dimension covers design-token discipline, logical-vs-physical style props, real-component reuse over hand-rolled primitives, and copy drift against a discoverable spec. **It is not a pixel check** — the pixel loop belongs to the implementing session's self-verify artifact, to `review-lean`'s design-sighted fidelity arm on a design-armed lean run (which scores the render receipt against the handoff frame and records `fidelity:` in the verdict), and to the human reviewer.

**Toolkit-absent on an ARMED spec is a VOID, not a note.** The always-spawn row above is not a preference that degrades — the reviewer cannot be dispatched, so the round cannot be certified. Do not select a substitute, do not proceed with the rest of the panel, and do not answer "Ready to merge?". Emit the Step 4b-void "review did not run" report instead, naming the reviewer the handoff host required and stating that `design-toolkit` is not installed in this session. `review-lean` hands the round back on exactly this shape (its step 5c) and writes no verdict record.

**Toolkit-absent degrade (unarmed diffs only).** These two agents ship in the `design-toolkit` plugin, not review-toolkit. The condition is that **the dimension was selected** — by *any* row of the map above, the no-provider default included — and the design-toolkit agent type is not available to dispatch in this session. When it holds, **do not select it**; detection is in-session and pre-dispatch, here at Routing. Note it once in the round summary (see "Not-selected ≠ dark" under the Synthesis Rules). Because nothing was ever dispatched, this never reaches `code-review.mjs` and cannot be confused with a dark reviewer.

Keying this on the *dimension being selected* rather than on `design.provider` being declared is load-bearing, not phrasing: the default row selects a reviewer with no provider key at all, and "no provider declared, design-toolkit not installed" is the ordinary shape of a consumer running review-toolkit alone. A degrade keyed on the key's presence would leave exactly that consumer's dimension silently unrun. The lint's matching exemption (`check-reviewer-references.sh`) is unconditional for the same reason — the two halves of one degrade must agree.

## Lead pass

The four dimensions above, plus **security whenever its conditional did not fire**, are reviewed
by this session in a single pass over the diff. The calibration content — the Pre-Emit Gate, the
Critical triggers, each dimension's What-NOT-to-flag block, the new-vs-pre-existing rule, and the
confidence threshold — lives in [`lead-pass-checklist.md`](lead-pass-checklist.md); read it before
the pass and apply it dimension by dimension. Depth per change size comes from Review Depth
Routing above.

**Load the consumer extension surface first.** The collapsed reviewers used to self-load it, so a
lead pass that skips it reads none of the repo's calibration while every lint stays green. Before
the pass, load from the repo under review, when each is present:

- `.claude/second-shift/review-context.md` — the shared core (you already load this for Maturity calibration)
- `.claude/second-shift/review-context/performance-reviewer.md`
- `.claude/second-shift/review-context/maintainability-reviewer.md`
- `.claude/second-shift/review-context/complexity-reviewer.md`
- `.claude/second-shift/review-context/test-coverage-reviewer.md`
- `.claude/second-shift/review-context/security-reviewer.md` — only when the security conditional did **not** fire; when it did, the spawned reviewer loads it itself

An empty or TODO-bodied section counts as ABSENT (the `reviewer-baseline` rule): infer
conservatively and say that you did.

**Security defers when it is spawned.** When the security conditional fires, the lead pass's
security section is not run — the spawned reviewer owns the dimension, and running both would
manufacture the duplicate findings Step 1 then has to merge. When it does not fire, the lead pass
owns it and its Verdicts row reads `Lead pass — ✅/❌` like the other four.

**Lead-pass findings are findings.** They enter Synthesis at Step 1 alongside the subagents' and
are deduplicated, confidence-filtered and triaged by the same rules — no privilege for having been
found in-session. Label them by dimension in the report exactly as a spawned reviewer's would be
(`[Performance]`, `[Maintainability]`, `[Complexity]`, `[Test Coverage]`, `[Security]`).

## Spawning Reviewers

One dispatch substrate — the `code-review.mjs` Workflow — across both entry modes:

- **Dispatch mode (standalone `/review-lead`, and `pr-revision`):** this session invokes `workflows/code-review.mjs` via the `Workflow` tool, passing the selected `reviewers` plus `worktree`/`base`/`head`/`changedFiles`/`prContext` (see Pre-flight). The script issues one `agent({ agentType, model, schema })` per selected reviewer, via `parallel()`, each at the model tier declared in its agent frontmatter, and returns structured findings.
- **Pipeline-driven review:** the caller invokes the same `code-review.mjs` script itself and hands this session the findings (synthesis-only mode — see Pre-flight).

In both modes the script returns structured findings and this session runs the Synthesis Rules over them. The args the script forwards to each reviewer:

- **Git diff scope**: `git diff [BASE]...[HEAD] -- <relevant paths>` (three-dot, matching what the script renders) or full diff if no range provided
- Which files changed (from `git diff --stat`)
- The branch name and any PR context the user provided
- Any specific areas of concern the user mentioned

**Do NOT pass** the plan/spec to sub-agents — plan compliance is your responsibility as the orchestrator. Sub-agents review code quality in their domain; you verify spec completeness.

**Parallelism:** the script issues all selected reviewer dispatches in a single `parallel()` batch. Do NOT serialize — that defeats the purpose of fan-out and burns wall-clock time.

### Empty selection: no fan-out at all

Routing can legitimately select **zero** subagents now that the core four are the lead pass's — a
docs-only diff with no issue reference and no security surface is the ordinary case. `code-review.mjs`
rejects an empty `reviewers[]` by design (it has nothing to dispatch and returning an empty result
would be indistinguishable from a fully dark panel), so in dispatch mode **do not invoke the
Workflow at all** when the selected set is empty. Run the lead pass and synthesize over its
findings alone. In synthesis-only mode the caller has already made the same decision; you are
handed either findings or nothing, and synthesize either way.

This is not a degraded round and never a `[Coverage gap]`: nothing was selected, so nothing went
dark (Step 4c). Note the empty selection once in the Review Summary — "no subagent met a trigger
this round; reviewed by the lead pass" — so the reduced fan-out is visible rather than inferred.

### Special handling: `scope-completeness-reviewer`

When dispatching `scope-completeness-reviewer`, the prompt must contain only **evidence**, never **interpretation**. You do NOT fetch the issue — the subagent does that itself, in its own context, so your wording cannot bias its scope reading. Your only job is to forward facts.

The dispatch prompt should contain:

1. **GitHub issue number** (e.g., `#758` or `758`).
2. **Branch and base** (e.g., `claude/repo-758` vs `main`).

What the dispatch prompt MUST NOT contain:

- No paraphrase of the issue scope ("the issue says X").
- No assertion about what is or isn't in scope ("this item is deferred", "we're only reviewing the X part").
- No summary of the diff ("the change does Y") — the subagent reads the diff itself.

If the user's invocation prompt contains scope assertions (e.g., "this is the BE half, the UI part is out of scope"), strip them from the dispatch prompt. They are not evidence and must not reach the subagent — that independence is the whole reason this gate exists.

## Synthesis Rules

### Cross-agent severity vocabulary

Two severity vocabularies coexist across the review/planning agents. When a finding originates from (or is compared against) a planning agent, normalize to the baseline vocabulary before triage:

| Planning agents (`plan-reviewer`, `spec-reviewer`) | Baseline reviewers (this synthesis) | Schema transport  |
| -------------------------------------------------- | ----------------------------------- | ----------------- |
| Blocker                                            | Critical                            | `blocker`         |
| Warning                                            | Warning                             | `major` / `minor` |
| Note                                               | Pre-existing (informational)        | `nit`             |

The right-hand columns are the existing `reviewer-baseline` prose → schema mapping (see [`reviewer-baseline`](../reviewer-baseline/SKILL.md), "Severity vocabulary mapping"); this table only adds the planning-agent column so the three are reconciled, not a third vocabulary. (`db-reviewer`'s own "Suggestion" tier is informational — treat as Note/Pre-existing.)

### Step 1: Deduplicate (before triage)

Before triaging, merge duplicate findings:

- If security-reviewer and db-reviewer both flag the same missing `userId` filter → keep the db-reviewer's finding (more specific), drop the duplicate
- If performance-reviewer and pipeline-reviewer both flag the same N+1 query → merge into one finding, credit both
- Same file:line from multiple reviewers = one finding, pick the best description
- **Exception**: Do not merge a `[Pre-existing]` finding with a `[Critical/Warning]` finding at the same location. Keep both — the new finding in the main sections, the pre-existing in the pre-existing section
- If two findings from different reviewers have the same root cause but different file:line locations, group them under one finding with both locations listed and the higher severity

### Step 2: Confidence-based filter

- Findings with confidence ≥80: proceed to normal triage
- Findings with confidence <80: omit from main report sections (reviewers filter at source, but double-check). Collect all suppressed findings from reviewers into the "Suppressed" report section.
- `[Pre-existing]` findings: always include regardless of confidence — route to "Pre-existing gaps" section

### Step 3: Triage (BEFORE writing the report)

For every finding from a sub-reviewer, classify it:

| Classification       | Criteria                                                                                 | Action                                                                                                            |
| -------------------- | ---------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| **New gap**          | The PR introduces a pattern/vulnerability that doesn't exist elsewhere in the codebase   | Keep as Critical or Warning                                                                                       |
| **Pre-existing gap** | The PR follows an existing codebase pattern that happens to be imperfect                 | Downgrade to `## Pre-existing gaps (not blocking this PR)` section — note it for a future initiative, not this PR |
| **Aspirational**     | The reviewer demands infrastructure that doesn't exist yet (auth, tests, shared clients) | Omit or move to `## Future improvements` — do NOT fail the review                                                 |

**Examples of false positives to catch:**

- "Missing auth headers" → when NO component in the app uses auth headers
- "No input validation" → when validation is done at the API layer and every other component trusts this
- "Zero test coverage" → when the workspace has no test framework configured
- "No shared API client" → when every component in the codebase defines inline fetch functions

### Step 4: Scope Completeness Gate

If `scope-completeness-reviewer` was spawned and returned `FAIL` or `BLOCKED`, the consolidated "Ready to merge?" verdict **MUST** be "No" regardless of any other reviewer's verdict. This is a hard gate, not a heuristic. (`BLOCKED` means the subagent could not fetch the issue — treat it identically to `FAIL`.)

- Each `[unsatisfied]` scope item is included as a `Critical [Scope completeness]` finding in the Critical section, with the unsatisfied item, the reason, and the question "is this item covered by the diff somewhere I missed, or does it need to be added to the PR or explicitly deferred in the issue body?"
- The orchestrator's prompt (the user's invocation) does not override this gate. Claims like "that's deferred" or "out of scope here" are not evidence — only the diff covering the item, or the issue body explicitly deferring it (with a linked follow-up issue), satisfies a scope item.
- If the user pushes back ("but it really is out of scope"), the response is to either (a) cover the item in the diff, or (b) update the issue body with explicit deferral language and re-run the gate.
- **Autonomous-pipeline caveat:** remediation (b) edits a GitHub issue's acceptance criteria — a **human-authority action** the `auto`-mode permission classifier denies, and one no agent should take unprompted. So in dev-pipeline `auto` mode a scope blocker with **no code remedy** is not cleared by the synthesis loop; carry it into your verdict as an unresolved blocker and let the merge boundary hold it, rather than clearing or deferring it yourself. Do not reach for an input-requesting prompt to record the deferral — that breaks the `auto`-mode no-prompts invariant and hangs a headless run. (Standalone `/review-lead` and `interactive` mode may still ask.)

If `scope-completeness-reviewer` returned `N/A — no issue provided`, include a single line in the Review Summary: "No GitHub issue referenced; scope completeness not verified."

### Step 4b: Dead / dark reviewer accounting

A reviewer that was **selected** but produced no usable result went **dark**. A dark reviewer is NOT a clean PASS and NOT a silent omission — it is a **coverage gap**: its domain was not reviewed this round. Under a pipeline-driven review the fan-out runs inside `code-review.mjs`, which already retried a dark reviewer once on-substrate; do **not** re-dispatch a dark reviewer yourself.

Detect darkness from two distinct signals — never from "the array is shorter than I expected" alone:

1. **Died-after-retry (per-reviewer).** The reviewer is **present** in the returned `reviewers[]` as `{ result: null, ... }` (with `{ retried: true, failed: true }` if it also failed its automatic retry). Exactly that reviewer is dark.
2. **Budget-skipped (all-or-nothing).** The return carries `budgetExhausted: true` and `reviewers` is **empty by construction**. **Every** selected reviewer (the set you chose during Routing / passed as `args.reviewers`) is dark — compare against that selected set to enumerate them.

For each dark reviewer:

- Add a `[Coverage gap]` line to the **Review Summary** naming the reviewer, its unreviewed domain, and the reason (`died-after-retry` or `budget-exhausted`).
- In the **Verdicts** table, its row reads **`Dark (no output)`** in the Verdict column (with `—` findings / confidence) — never Pass, never Fail, never omitted.
- The **"Ready to merge?"** reasoning MUST acknowledge the reduced coverage (e.g. "db-reviewer + unit-test-mutation-reviewer were dark this round; merge readiness is assessed without them").

A dark reviewer does not by itself force "Ready to merge? = No" (unlike the Scope Completeness Gate) — it forces **visibility**: the human deciding to merge must be told which domains went unreviewed. That calibration is for a *partial* panel, and Step 4b-void below is where it stops applying.

### Step 4b-void: an all-dark selected set voids the round only when nothing else reviewed it

The rule above is calibrated for one reviewer dying. When every **selected subagent** dies it reads exactly the same, and that is the case where the report can be worthless: a complete-looking review, a coverage-gap note, and a "Ready to merge?" verdict resting on coverage that was never produced. An unattended run then merges on a review that reviewed nothing.

**Void applies to the selected subagents, and only voids what it can void.** A completed lead pass means the round reviewed something — the four collapsed dimensions, plus security when its conditional did not fire — so an all-dark selected set on top of a completed lead pass is **not** a void. It is a partial-coverage round: keep Step 4b's behavior (a `[Coverage gap]` line per dark reviewer, `Dark (no output)` rows, "Ready to merge?" reasoning that names the missing domains) and answer the verdict from what the lead pass and any surviving results actually cover.

**When the round IS void — the two cases:**

1. **Nothing reviewed the range at all**: the lead pass did not complete AND no selected subagent produced a usable result.
2. **The design-fidelity dimension is unrunnable on an armed spec** — the pre-dispatch case its own section states, which voids the round however well the rest of it went.

**The scope gate is a hard No, not a void.** A dark `scope-completeness-reviewer` is unchanged by any of this: Step 4 keeps its full force — a `FAIL`, a `BLOCKED` (which is treated identically to `FAIL`), or a dark return all make "Ready to merge?" **No**. It is a real verdict on a round that really happened, so it is never converted into a void, and never into a silent pass because the lead pass covered its other dimensions. The lead pass cannot substitute for it: reading the issue's scope in the same context that wrote the diff is the bias the gate exists to isolate.

Darkness is still counted across **both** of Step 4b's signals: a reviewer present in `reviewers[]` as `{ result: null, … }` (died-after-retry), or `budgetExhausted: true` with `reviewers: []` (every selected reviewer dark by construction). An **empty selection** is neither — nothing was selected, so nothing is dark, and a round with no fan-out is never void on that ground (see "Empty selection: no fan-out at all").

**What a void emits.** Do **not** write the report structure below. Emit instead a short **"review did not run"** report that names the full dark set, its reason (`died-after-retry` / `budget-exhausted`), and the range that went unreviewed — and **do not answer "Ready to merge?"** at all.

This deliberately overrides the "Always give a clear verdict" rule under Rules, for this one case and no other. Answering "No" would be the tempting shape, and it is wrong in a way that is worse than silence: "No" asserts that a review found problems, which is false in the other direction, and it sends the author hunting for findings that do not exist. There is no verdict to give, because there was no review. Say that.

### Step 4c: Not-selected ≠ dark

A reviewer that was **never selected** is a different case from a dark reviewer: nothing failed, the trigger simply did not fire, so it is **not** a `[Coverage gap]` and its Verdicts row is omitted, not `Dark (no output)`. Reserve that rendering for reviewers that were selected and produced no usable result. Three not-selected cases still must not be invisible, because in each one a whole dimension is silently absent while the round looks green:

- **Unmatched web-component surface.** No changed path matched `$WEB_COMPONENT_GLOBS`, so neither `a11y-reviewer` nor the design-fidelity dimension was routed. Note once in the Review Summary, **including the resolved globs** so a mis-scoped config is diagnosable from the line itself — e.g. "a11y + design-fidelity not routed: no changed path matched `stageParams.webComponentGlobs` (`apps/web/**/*.{tsx,jsx}`)". A genuinely non-FE diff is the overwhelmingly common case; escalating it would make every backend PR noisy.
- **Security conditional did not fire.** No auth / tenancy / session / upload / query-construction surface in the diff and no `review-context/security-reviewer.md` in the repo, so `security-reviewer` was not selected. Note once in the Review Summary, naming what carried the dimension instead — e.g. "security-reviewer not selected: no security surface in the diff; security dimension covered by the lead pass". Never silent: the reader has to be able to tell "no security surface" from "nobody looked".
- **Design-toolkit not installed.** A changed path *did* match and the provider map selected a fidelity reviewer — by any row, **the no-provider default included** — but the design-toolkit agent type is not available to dispatch (Routing detected this pre-dispatch). Note once: "design-fidelity dimension not run — design-toolkit not installed". `a11y-reviewer` is unaffected and still spawns. The trigger is selection, not a declared `design.provider`: on the default row no provider is declared and the dimension is still selected, so a provider-keyed condition would make this note unreachable for the commonest consumer.

All three are **a note, never a blocker, and never silent** — and none is a red.

### Step 5: Cross-Reviewer Self-Check

After triage but before writing the report, scan the full diff for cross-cutting concerns that no individual reviewer would catch alone. Each reviewer has a narrow scope — gaps between scopes are real.

Check for combinations like:

- New endpoint with no auth guard AND no tests AND no error handling (each reviewer might pass individually)
- New service method that modifies data but has no corresponding event emission (if events are the pattern)
- Schema change with no corresponding DTO update or vice versa
- Public-facing change with no input validation AND no test coverage

**Scope limit:** Max 2 cross-cutting findings per review. These must be concrete and evidence-based — not speculative. Label them `[Cross-cutting]` in the report and include in the Critical or Warning section as appropriate.

### Step 6: Plan/Spec Compliance (if plan provided)

Apply **Plan/Spec Awareness** above — the three checks (missing requirements, scope creep, misunderstandings) and the separate-reporting rule.

### Report structure

Combine all findings into one report with this structure:

```
## Review Summary
One-paragraph overall assessment. Include plan alignment if a plan was provided.

## Strengths
What the code does well — be specific. Acknowledge good patterns, solid testing, clean design.
This section is REQUIRED even if there are critical findings.

## Critical (must fix before merge)
Only findings where the PR introduces a NEW risk or regression.
Each finding includes: [Reviewer] file:line (confidence: N) — description.
- [Security] finding...
- [Pipeline] finding...
- [Scope completeness] finding...

## Warnings (should fix)
- [Performance] finding...
- [Domain] finding... (from a repo-local reviewer, labeled by its domain)

## Suggestions (consider)
- [Complexity] finding...

## Plan Compliance (if plan/spec provided)
- Missing: [requirements not implemented]
- Extra: [code not in the plan]
- Mismatches: [implementation differs from spec]
If all requirements met: "Implementation matches the plan."

## Pre-existing gaps (not blocking this PR)
Findings that apply to the entire codebase, not specific to this PR.
List briefly with suggested future initiative.

## Suppressed (below confidence threshold)
One-line bullets from all reviewers for findings with confidence < 80, so they are visible but not blocking.

## Verdicts
| Reviewer        | Verdict       | Findings | Confidence Range |
|-----------------|---------------|----------|------------------|
| Scope Completeness | Pass / Fail | N | — |
| Security        | Pass / Fail — or Lead pass — ✅/❌ | N | N-N   |
| Performance     | Lead pass — ✅/❌ | N     | N-N              |
| Database        | Pass / Fail   | N        | N-N              |
| Complexity      | Lead pass — ✅/❌ | N     | N-N              |
| Maintainability | Lead pass — ✅/❌ | N     | N-N              |
| Test Coverage   | Lead pass — ✅/❌ | N     | N-N              |
| Pipeline        | Pass / Fail   | N        | N-N              |
| Unit Test Mutation | Pass / Fail | N      | N-N              |
| Accessibility   | Pass / Fail   | N        | N-N              |
| Design Faithful | Pass / Fail   | N        | N-N              |
| Figma Faithful  | Pass / Fail   | N        | N-N              |
| \<repo-local domain reviewer(s)\> | Pass / Fail | N | N-N          |

**Ready to merge?** Yes / No / With fixes

**Reasoning:** [1-2 sentence technical assessment]
```

**Verdict rules**:

- A reviewer's verdict should be ✅ PASS if its only findings are pre-existing gaps. ❌ FAIL only if the PR introduces new issues with confidence ≥ 80. The same rule decides the ✅/❌ on a `Lead pass` row.
- Only include rows for reviewers that were spawned. If a domain reviewer wasn't triggered, omit it from the table. **A reviewer that was spawned but went dark (Step 4b) is NOT omitted — its row reads `Dark (no output)`.**
- **Exception — the four lead-pass rows.** Performance, Complexity, Maintainability and Test Coverage are never spawned and are never omitted: each carries a row reading `Lead pass — ✅/❌`, so a reader can tell a dimension that was reviewed in-session from one that was skipped. Security takes the same rendering on the rounds its conditional did not fire, and the ordinary `Pass / Fail` when it did. A single `Lead pass` summary row may be added **in addition to** those rows, never instead of them.
- The two design-fidelity rows are **mutually exclusive at runtime** — the provider map selects exactly one, so a real report carries at most one of them. Both are listed above because the table is the registry template, not a claim about any single round.
- **Confidence Range column**: Scan each reviewer's findings for `(confidence: N)` values; report `min–max`. If a reviewer had no findings, write `—`.
- **Scope Completeness gate**: if it FAILed or BLOCKED, "Ready to merge?" is **No** regardless of every other row.

**Plan Compliance section**: Omit entirely when no plan/spec was provided as input. If provided but the user notes this PR covers only part of the plan, limit compliance checking to the sections the PR claims to address.

The **Ready to merge?** verdict is your judgment call as the orchestrator — it weighs all reviewer verdicts, the Scope Completeness Gate, plan compliance, and strengths against findings. It has exactly one unreachable state: a round voided under Step 4b-void emits no report in this structure at all, so the question is never posed.

## Prior Round Context

When invoked for round 2+ of a multi-round review (e.g., during a pipeline-driven review):

The user should provide context like: "Round 2 of 3. Prior findings: [list]. Focus on: verifying prior fixes + new issues only."

When prior round context is provided:

1. **Skip re-flagging resolved findings** — if a prior finding was fixed, don't report it again
2. **Verify fixes** — confirm prior Critical/Warning findings were actually addressed, not just suppressed
3. **Focus on new issues** — findings introduced by the fix commits since last round
4. **Reduce reviewer lineup** — only spawn reviewers whose prior findings had blockers/majors, plus any reviewer whose scope is touched by the fix commits. The lead pass still runs every round; scope it to the fix commits the same way

This reduces token waste and prevents redundant findings across review iterations.

## Rules

- **Dedup first, triage second** — merge overlapping findings before classifying severity
- If reviewers disagree, note the disagreement and your recommendation
- If ALL reviewers pass with no findings, say so concisely — include Strengths and verdict, don't pad the report
- Never invent findings that no reviewer reported (cross-cutting self-check is the one exception — label these clearly)
- **Always include Strengths** — pick the 2-4 most specific, non-redundant observations across all reviewer Strengths blocks. Consolidate observations about the same file into one bullet. Do not repeat the same observation twice.
- **Always give a clear verdict** — "Ready to merge?" must be answered Yes, No, or With fixes. **One exception:** a round voided under Step 4b-void answers it not at all — there was no review to draw a verdict from, and "No" would assert findings that do not exist. Step 4b-void owns the trigger; do not restate it here. Two consequences of it that are easy to get backwards: an all-dark **selected set** is not a void on its own when the lead pass completed, and a dark `scope-completeness-reviewer` is a hard **No**, never a void
- Repo-local domain reviewer findings about domain correctness take precedence over complexity reviewer suggestions to simplify domain logic
- Pipeline reviewer findings about contract integrity take precedence over performance suggestions to change worker data flow
- **Confidence is king** — a finding at confidence 95 from one reviewer outweighs three findings at confidence 80 from others. Prioritize by confidence × severity, not by count
- **Scope Completeness is non-negotiable** — a FAIL/BLOCKED from that gate forces the merge verdict to "No" regardless of confidence weighting elsewhere
