# Doc Update (Stage 7)

Structured in-session pass — no Task hop. Scans the repo's declared documentation roots (and `CLAUDE.md`, `.claude/agents/`) for references to files or APIs touched in Stage 5, identifies stale documentation, and applies surgical diffs.

**Why this matters:** In an AI-native repo the knowledge docs are load-bearing — downstream Claude Code sessions and reviewer agents read them before writing code, so a stale doc produces wrong code or missed findings:

- Stale ADR about a mapping → AI rewrites code matching the doc, contradicting the decision's intent
- Stale convention doc → AI follows outdated patterns and reviewers fail to flag them
- Stale architecture doc → AI misunderstands the repo's service boundaries

**Where the repo's docs live — read the router, never assume `.project/`.** This is a layer-0 plugin protocol; it must not hardcode any one repo's doc layout. Two sources declare it, in priority order:

1. **The repo's `CLAUDE.md` context router** (the harness loads it) — it declares where the repo's architecture / decisions / reference / framework docs live and their read-priority (the proven order: code > decisions > architecture > reference > plans). This is the authoritative source for the repo's doc roots.
2. **The optional extension `.claude/second-shift/doc-routing.md`** — a change-category → doc-path map the repo maintains. If present, load it and use its rows as the Step 7.B routing table.

If neither supplies a category→doc map, fall back to grepping the repo's declared doc roots for the literal basenames of changed files (Step 7.C) and reason over the hits — and say so in your output, since you routed conservatively rather than from a declared map. Everything acme-specific in this protocol is consolidated into the **"Example (acme's map)"** block below; it is an illustrative instance of the generic mechanism, not the contract.

## Step 7.A: Identify changed code areas

Run `git diff "$BASE_REF...HEAD" --stat` (or `git diff --stat` for uncommitted), where `$BASE_REF` is the **configured base branch** resolved as in Step 7.C (the host repo's `topology.repos.<host>.baseBranch`, default `main`) — a hardcoded `main` silently yields an empty candidate set on a develop/alpha-based repo. Classify each changed path into a **conceptual code-area category** — API endpoints / DTOs, business logic, database schema, background workers, ML / algorithm services, frontend, shared types, decision / domain-constant docs, and so on. Derive the path → category mapping from the repo's own layout as declared in its `CLAUDE.md` (its stack / module / directory sections); do not assume a fixed directory tree. The **"Example (acme's map)"** block below shows one repo's concrete path → category table.

## Step 7.B: Look up affected docs

Map each code-area category from 7.A to the docs that document it, in priority order:

1. **`.claude/second-shift/doc-routing.md`** (if present) — its category → doc-path rows are the authoritative map. Use them directly.
2. **The repo's `CLAUDE.md` routing** — the doc roots it declares for architecture / decisions / reference / framework knowledge. Route each category to the matching declared root (e.g. an API change → the repo's architecture doc; a schema change → its DB-convention doc).
3. **Fallback** — if neither supplies a mapping for a category, defer that category to the Step 7.C basename grep over the declared doc roots, and note in your output that the routing was conservative.

Whatever the source, the output of this step is a set of candidate doc paths keyed by the conceptual category. 7.B exists to catch _conceptual_ matches — a doc that describes a pattern without naming the changed file, which a basename grep can never find. When a change touches domain constants / decisions, also re-check any repo-registered domain reviewers (config `reviewers.add`) and reviewer agents that restate those constants — see Step 7.E. The **"Example (acme's map)"** block below shows a fully worked category → doc map.

## Step 7.C: Pre-compute candidate-doc set (filesystem-level)

Before dispatching LLM reasoning in Step 7.D, narrow the candidate-doc set with a filesystem grep on the basenames of files changed in Stage 5. This shrinks the set the model reasons over to the docs that textually reference touched files.

```bash
# Base ref: the host repo's configured base branch (topology.repos.<host>.baseBranch),
# NOT a hardcoded "main" — on a develop/alpha-based repo `main...HEAD` is empty and this
# step silently reports "0 candidates". (Advisory step; a mainline base over-reports
# harmlessly on stacked slices, whereas a wrong literal under-reports to nothing.)
CFG="${SECOND_SHIFT_CONFIG:-.claude/second-shift.config.json}"
BASE_REF="$(jq -r '(.topology.repos | to_entries[] | select(.value.path==".") | .key) as $h | .topology.repos[$h].baseBranch // "main"' "$CFG" 2>/dev/null || echo main)"

# 1. Extract basenames of changed files.
#    `while IFS= read -r` handles any path safely (including hypothetical whitespace);
#    `$BASE_REF...HEAD` matches Step 7.A's ref form so both steps see the same scope.
CHANGED_BASENAMES=$(
  git diff --name-only "$BASE_REF...HEAD" \
    | while IFS= read -r f; do basename "$f"; done \
    | sort -u
)

# 2. Determine the repo's doc roots to walk — do NOT hardcode `.project/`.
#    Read them from the repo's CLAUDE.md context router: the directories it declares
#    for architecture / decisions / reference / framework docs. The scope is always
#    `CLAUDE.md` itself + `.claude/agents/` + whatever doc dirs CLAUDE.md declares
#    (a `.claude/second-shift/doc-routing.md`, if present, may also name them).
#    Assemble them into DOC_ROOTS; fall back to just `CLAUDE.md .claude/agents/` if
#    the router declares no doc dirs (and say so in your output).
DOC_ROOTS="CLAUDE.md .claude/agents/ <doc dirs declared in the repo's CLAUDE.md>"

# 3. Single grep pass: pipe all basenames as fixed-string patterns via `-f -`
#    so every doc root is walked once regardless of N.
#    -l prints filenames-only; -r recursive; -F treats each pattern as a fixed string.
GREP_HITS=$(
  printf '%s\n' "$CHANGED_BASENAMES" \
    | grep -rlF -f - $DOC_ROOTS 2>/dev/null \
    | sort -u
)
```

**Candidate set = union of Step 7.B (routing-map outputs) and Step 7.C (grep hits)**, not a replacement. Step 7.B catches _conceptual_ matches where a doc describes a pattern without naming the changed file (e.g. a DB-schema change routing to the repo's schema-convention doc); the grep step catches _literal_ basename references that the routing map may miss. The two are complementary; Step 7.D reasons over the union.

**Scope notes:**

- Repo-local ephemeral session-state (if the repo defines any, per its CLAUDE.md) is intentionally excluded — it is ephemeral focus state, not authoritative truth, and decays with the milestone it belongs to.
- Generic basenames (`index.ts`, `types.ts`, `utils.ts`, `helpers.ts`) will produce false-positive hits. Filter them at the implementer's judgment for now; a noise-skip allowlist is a future hardening alongside symbol extraction from the diff.
- `.claude/skills/` is **not** in the grep scope — skill protocol files reference each other but are tracked separately from the repo's knowledge docs.

**Empty-set short-circuit:** If the union of Step 7.B's lookup-table outputs and the grep hits is empty, emit the "0 blockers, 0 warnings, 0 notes" verdict line directly (see "Output — Doc Update Report" below) and proceed. Steps 7.D and 7.E are skipped in that case.

## Step 7.D: Diff candidate docs against code

For each doc in the candidate set produced by Step 7.B ∪ Step 7.C:

1. Read the doc.
2. Read the relevant changed code.
3. Check if the doc's claims still match the code.
4. If stale, identify the specific section and line range.

**What counts as stale:**

- Doc describes an API endpoint that was added, removed, or whose signature changed.
- Doc states thresholds / constants that changed in code (e.g. numeric boundaries, retention windows, retry budgets).
- Doc describes a pattern that the new code doesn't follow.
- Doc lists module / service boundaries that shifted.
- Doc enumerates a supported set (stream kinds, categories, type variants) and the code added/removed one.

**What does NOT count as stale:**

- Doc describes a concept at a higher level than the code change.
- Code adds a new instance of an existing pattern (doc covers the pattern).
- Internal implementation changed but documented interface didn't.

## Step 7.E: Check reviewer agents

Step 7.C's grep already enumerates `.claude/agents/` files when changed-file basenames are referenced. This step adds **semantic guidance** — what each reviewer agent validates against — so the Step 7.D diff has the right invariants in mind for any reviewer-agent file in the candidate set. If the code change affects rules that reviewer agents validate against, diff the relevant reviewer-agent files in `.claude/agents/` plus any repo-registered domain reviewers (config `reviewers.add`).

Which reviewer agent carries which invariant is repo-specific — read each agent's own checklist rather than assuming a fixed roster. Pay particular attention to reviewers that **restate** domain constants or decision-record values (they mirror the repo's reference / decision docs and go stale in lockstep): when a change touches those constants, re-check that the restated values in the reviewer files still match the source doc. The **"Example (acme's map)"** block below shows one repo's reviewer → invariant map.

## Example (acme's map)

> **Illustration only — not the contract.** This is one repo's concrete instance of the generic 7.A → 7.B → 7.E mechanism above, for a repo whose knowledge base is `.project/`-shaped (`.project/frameworks/`, `.project/decisions/`, `.project/reference/`, `.project/architecture/`). A different repo declares a different layout in its `CLAUDE.md` / `doc-routing.md`, and the plugin routes to that instead. Read this as "here is what a filled-in `doc-routing.md` looks like," never as paths to hardcode.

**7.A — path → code-area category (this repo's layout):**

| Changed path pattern                                                          | Code area                                                       |
| ----------------------------------------------------------------------------- | -------------------------------------------------------------- |
| `apps/api/src/**/*.controller.ts`                                             | API endpoints / DTOs                                           |
| `apps/api/src/**/*.service.ts`                                                | Business logic                                                 |
| `packages/db/src/schema/**`                                                   | Database schemas                                               |
| `packages/db/src/migrations/**`                                               | Migration files                                               |
| `apps/api/src/workers/**/*.processor.ts`                                      | Background job workers                                         |
| `services/report-service/**`                                                  | Report generation service (aggregation, export rendering)     |
| `apps/web/src/**/*.tsx`                                                       | Frontend components / pages                                    |
| `apps/web/src/**/*.ts` (non-tsx)                                              | Frontend utilities / hooks                                     |
| `packages/core/src/types/**`                                                  | Shared type definitions                                        |
| `services/notification-service/**`                                            | Notification dispatch service                                  |
| `.project/decisions/ADR-0{09,10,11}*` (brace glob: ADR-009, ADR-010, ADR-011) | ADR / decision-constant changes (rate limits, pagination, retention) |

**7.B — code-area category → candidate docs (this repo's `doc-routing.md` map):**

- **API / endpoint changes** → `.project/architecture/system-overview.md`, `.project/frameworks/api-framework.md` (if exists)
- **DB schema changes** → `.project/frameworks/database.md`, `.project/reference/conventions.md` (multi-tenant `userId` filter rule)
- **Background job worker changes** → `.project/frameworks/job-queue.md` (if exists), `.project/architecture/system-overview.md` (pipeline diagram)
- **Report generation rules** → `.project/reference/report-rules.md`, `.project/frameworks/charts.md` (if export/visualization affected)
- **ADR / decision-constant changes** (ADR-009/010/011, or any rate-limit / pagination / retention boundary) → `.project/reference/decision-constants.md` (the canonical source) **and** its mirrors in any repo-registered domain reviewers (config `reviewers.add`, e.g. a billing-reviewer) and `.claude/agents/test-coverage-reviewer.md` — re-check that the restated values still match. (Belt-and-suspenders: `decision-constants.md` cites each ADR by full filename, so the Step 7.C basename grep also surfaces it when an ADR is in the diff.)
- **Frontend / chart changes** → `.project/frameworks/charts.md`, `.project/frameworks/frontend.md`, `.project/architecture/frontend-ux.md`
- **New architectural decisions** → `.project/decisions/` (may need a new ADR — append-only by convention)
- **New commands or root-level conventions** → `CLAUDE.md`
- **Reviewer agent rules** → `.claude/agents/security-reviewer.md`, `.claude/agents/db-reviewer.md`, `.claude/agents/plan-reviewer.md`, `.claude/agents/test-coverage-reviewer.md`, `.claude/agents/performance-reviewer.md`, plus any repo-registered domain reviewers (config `reviewers.add`, e.g. a billing-reviewer) (convention checklists; the domain reviewers + `test-coverage-reviewer` mirror repo-local decision-constant docs)

**7.E — reviewer agent → invariants it restates (this repo's roster):**

- `.claude/agents/security-reviewer.md` — auth patterns, `userId` filter rule, JWT/cookie posture
- `.claude/agents/db-reviewer.md` — DB conventions, index patterns, N+1 guards
- `.claude/agents/plan-reviewer.md` — convention checklists, file coverage tables
- Repo-registered domain reviewers (config `reviewers.add`) — e.g. a billing-reviewer carrying domain invariants that mirror repo-local knowledge docs (see the repo's CLAUDE.md); re-check them when the underlying decision constants change.
- `.claude/agents/test-coverage-reviewer.md` — edge-case boundaries (max page size 100, default page size 20, 5-item minimum batch, retention window in days). **Mirrors `.project/reference/decision-constants.md`** — same re-check on ADR/constant changes.
- `.claude/agents/performance-reviewer.md` — performance thresholds (result set sizes, query latencies, worker throughput)
- `.claude/agents/maintainability-reviewer.md` — readability heuristics
- `.claude/agents/pipeline-reviewer.md` — job payload shapes, idempotency rules

## Severity classification

| Level       | Meaning                                                                      | Example                                                                                                                       |
| ----------- | ---------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| **Blocker** | Doc actively contradicts code. AI will generate wrong code if it reads this. | `.project/reference/rate-limits.md` says default rate-limit=15 but `services/geo-service/src/limiter.rs` now uses 10                |
| **Warning** | Doc is incomplete. AI might miss something.                                  | New stream kind added to `packages/core/src/types/streams.ts` but `.project/reference/conventions.md` enumeration not updated |
| **Note**    | Doc could be improved. Not wrong, just missing new context.                  | New pattern not documented yet                                                                                                |

## Output — Doc Update Report

Produce the report in-session:

````markdown
## Doc Update Report

### Summary

[1-2 sentences: what changed in code, how many docs affected]

### Blockers (doc contradicts code)

**[file-path]** lines N-M

- Current: "what the doc says"
- Actual: "what the code now does"
- Suggested update:

```diff
- old text
+ new text
```

### Warnings (doc incomplete)

**[file-path]**

- Missing: "what should be added"
- Where: after line N / in section "X"

### Notes (nice to have)

### Verdict: [N blockers, N warnings, N notes]
````

If no docs are stale, emit the Verdict line only with `0 blockers, 0 warnings, 0 notes` and proceed.

## Pipeline-level handling

- **Blockers found** → apply doc fixes inline, commit on the same branch as the code change (`docs: update {doc-name} to match {feature}`), and surface in the Stage 7 checkpoint `docUpdaterFindings` field for Stage 8 code review.
- **Warnings / Notes only** → record findings in `docUpdaterFindings` (free-form markdown summary), proceed without commit.
- **No findings** → write `docUpdaterFindings: ""` and proceed immediately.
- **Pass fails partway through** (e.g., a doc file unexpectedly missing) → log warning to stage comment, proceed (doc updates are non-blocking).

**Surgical diffs only** — never rewrite sections that aren't stale. ADR / decision-record files (in the repo's decisions directory, wherever its CLAUDE.md declares) are append-only by convention — suggest a new ADR or addendum, do not modify existing ADR bodies.

## Where `docUpdaterFindings` lives

The free-form report from this stage (or its empty-state equivalent) is folded into `stageCheckpoint["7"].docUpdaterFindings` by the Stage 7 checkpoint write. Stage 8 review-toolkit:review-lead reads this field as part of its hydration context — stale-doc Blockers that were auto-fixed are signal for the review; Warnings / Notes are signal for the human reviewer.
