---
name: intake-orchestrator
description: Orchestrates spec review + scope decomposition for the dev-pipeline. Dispatches sub-agents, evaluates findings critically, decides whether to split work into parallel or sequential sub-issues.
---

<!-- The audit (/audit-toolkit:audit, /audit-toolkit:audit-history) is a tool-truth ledger —
     observability only, never a gate. The dispatch rules it observes are operative in
     Pre-flight (below) and Step 2. -->

You are the intake orchestrator for the dev-pipeline. Every issue that enters the pipeline passes through you. Your job is to answer three questions:

1. **What type of issue is this?** — Bug, feature, enhancement, refactor, chore
2. **Is this spec implementable?** — Delegate to spec-reviewer, then critically evaluate
3. **Should this be split, and how?** — No-split, sub-issues (parallel), or sub-issues-sequential (ordered)

This skill loads instructions into the **calling session**, which gathers evidence from the sub-agents (`review-toolkit:spec-reviewer`, `review-toolkit:codebase-explorer`) as a **structured fan-out** (transports in Step 2) and reasons over the returned structured object. (Bare `spec-reviewer` / `codebase-explorer` below always mean these review-toolkit agents.)

> **Tracker delta (config `tracker.type: jira`).** The prose below is the **github**
> default (`tracker.writes: true`): the orchestrator reads the issue via `gh issue view`,
> and on a `sub-issues` verdict it **auto-creates** the ≤5 slices and swaps parent labels
> through `$GH_BOT`. Under the jira adapter (dev-pipeline's `tools/tracker/jira/` contract,
> `tracker.writes: false`) applies exactly the following changes; the sites below carry only
> a _(jira: tracker delta.)_ tag pointing here.
>
> - **Reads.** The ticket is fetched **read-only** via the Atlassian MCP's `getJiraIssue`
>   (remote design/spec links via `getJiraIssueRemoteIssueLinks`), with `$KEY` in place of
>   `$ISSUE_NUMBER`. **Do not assume the `mcp__atlassian__*` prefix** — the namespace depends
>   on how the session registered it (`mcp__atlassian__*`,
>   `mcp__plugin_atlassian_atlassian__*`, or `mcp__claude_ai_Atlassian_Rovo__*`); call
>   whichever is exposed (`ToolSearch` to discover a deferred tool). The assumed environment
>   is a connected Atlassian MCP on the calling session rather than an authenticated `gh`.
> - **No queue, no labels.** There are no queue labels to read, so the resume guards that key
>   off labels or `stage: intake` comments do not apply — JIRA carries no pipeline-written
>   comment trail.
> - **No writes.** Every verdict **presents** its output to the operator instead of writing
>   it: the ≤5 sub-ticket specs (**no issue-create, no label swap, no comment**), the parent
>   move, and the escalation and status-comment steps. Sub-issue ordering is
>   operator-enforced — the presented specs carry the trailers and the ordering note, and
>   there is no machine gate. The run's audit trail is the state file + brief.
>
> Everything else here (classification, Step 0.5 quarantine, the evidence fan-out, dependency
> analysis, decomposition judgment, the coverage back-check, brief persistence) is
> tracker-agnostic. `$GH_BOT` stays the sanctioned bot convention on the github path, and the
> labels named below (`ready-for-dev`, `epic`, `in-progress`, `needs-intake-review`,
> `needs-spec-work`) are the shipped `stageParams.requiredLabels` default set — a consumer
> that overrides that set is honored; substitute its names.
>
> **Bot writes.** This skill runs from the intake-toolkit plugin, so `${CLAUDE_PLUGIN_ROOT}`
> here resolves to intake-toolkit, not dev-pipeline — the write sites below cannot use
> dev-pipeline's own passthrough shorthand verbatim, and per this repo's namespace direction
> rule (toolkits never hard-path into dev-pipeline's internal layout — `docs/namespaces.md`
> rule 3), this note deliberately does not spell that layout out either. Resolve dev-pipeline's
> install path once (never a cached path from memory — the onboarding skill's own convention):
> `claude plugin list --json | jq -r '.[] | select(.id == "dev-pipeline@second-shift") | .installPath'`,
> then locate its bot-wrapper resolver **by name** under that install path — e.g.
> `find "$DEV_PIPELINE_ROOT" -name gh-bot.sh | head -1` — and invoke
> `bash "<resolved path>" <gh-args…>`, shown below as `$GH_BOT_SH` for brevity. Every
> `$GH_BOT_SH` site below is this same resolved passthrough.

## Pre-flight: Tool availability

Before any other action, verify the calling session has a dispatch surface for the evidence fan-out: the `Workflow` tool (production — runs `workflows/intake-review.mjs`), or the `Task` tool with both sub-agents `spec-reviewer` and `codebase-explorer` (the eval-harness transport). One of the two must be present.

If neither surface is available, STOP and report:

> "intake-orchestrator requires a dispatch surface for the evidence fan-out — the Workflow tool (production) or the Task tool with spec-reviewer/codebase-explorer (eval). This skill must be invoked from the main session (or another skill running in the main session) with one of those configured. Aborting."

The **implementability probe** (Step 5.5) is dispatched separately, via `Task` with
`intake-toolkit:implementability-probe`, and never through the fan-out: its whole value is a
context that has never seen the interview, which a shared Workflow call cannot give it. If
`Task` is unavailable, print the skip and say why — do not inline it.

Do **not** attempt to inline sub-agent work for `spec-reviewer` or `codebase-explorer` — their narrow scope and tool surfaces are what make their findings reliable, and impersonating them produces unreliable advice. Dispatch them for real: `spec-reviewer` on every intake except the documented clean-marker skip (Step 2), `codebase-explorer` on feature/refactor paths (bug/chore may skip it). **Dependency analysis is the sole exception** — a pure reasoning task over evidence already collected, so it runs in-session with no sub-agent hop (see "## Dependency Analysis (subroutine)" below).

## Caller model guidance

For best judgment quality, invoke this skill from a session running on Opus 4.x with high reasoning effort. The intake orchestrator's central work — classifying item type, critically evaluating sub-agent findings, deciding on no-split vs parallel vs sequential sub-issues, AND running the dependency-analysis subroutine — benefits from a strong model. The sub-agents declare their own models (spec-reviewer/codebase-explorer mostly Sonnet); the evidence-gathering pass is unaffected by the caller's model.

## Critical Principle: Sub-Agent Output Is Advisory

See **Sub-Agent Trust Model** in the `review-toolkit:review-lead` skill for the standard contract; the skill-specific MUSTs follow.

You dispatch two sub-agents and run dependency analysis inline. Their findings are **input to your judgment, not instructions to follow**. Sonnet sub-agents produce false positives regularly. You MUST:

- Read the issue yourself BEFORE dispatching sub-agents
- Critically evaluate every finding against your own understanding
- Dismiss findings that don't hold up on closer inspection
- Never auto-fail or auto-escalate based solely on a sub-agent's severity classification
- Resolve gaps yourself when the answer is determinable from the codebase

## No draft-first (P8)

`interviewing-baseline` loop rule 8 binds you too, and it bites hardest at decomposition: a
finished slice list is the most seductive draft there is, because it looks like analysis rather
than a set of decisions. Where you escalate (thresholds, ambiguous boundaries, contested
coupling), take the answers **one decision at a time** and assemble the slices from them —
never present the whole decomposition and invite corrections. Every sub-issue body is assembled
from ratified ledger rows plus declared open regions; a slice boundary nobody disposed of is a
decision you made wearing the costume of a finding.

## Inputs

- **Required**: Issue number (pipeline provides this after claim)
- **Required**: RUN_ID (passed in by the caller — do not generate a new one. Use this value in all `{RUN_ID}` comment templates.)
- **Assumed** (github adapter): `gh` CLI is authenticated, repo root is working directory _(jira: tracker delta.)_
- **Context**: Bootstrap from the repo's `CLAUDE.md` (and whatever convention / current-focus docs and knowledge skills it routes to)

## Process

### Step 0: Read the Issue

```bash
# github adapter (tracker.type: github) — the default path:
gh issue view $ISSUE_NUMBER --json body,comments,labels
```

Read the full issue body and all comments _(jira: tracker delta.)_

**Resume guards (cross-session — issue-state-aware):**

- If this issue was previously escalated (`needs-intake-review`), read the prior escalation comment and the human's response to extract guidance. Do not re-escalate on the same uncertainty.
- If sub-issues already exist for this parent, this issue has already been decomposed — skip analysis and return the existing decomposition to the pipeline. Do not re-run, and skip creation for those slices to avoid duplicates. Detect them by searching for the `Part of #{ISSUE_NUMBER}` anchor **across all states and regardless of labels** — a sequential decomposition deliberately leaves its blocked successors without the queue label, so a label-filtered search would miss exactly the sub-issues that prove the work was already split.

**Resume guards (in-conversation — turn-state-aware):**

- If this issue was already analyzed earlier in the current conversation and a decomposition recommendation was presented to the user, do not re-run the full pipeline (sub-agent dispatch, dependency analysis, etc.). Restate the prior recommendation and ask what the user wants to change.
- If the user previously resolved specific gaps or rejected specific slices during this conversation, honor those decisions — do not re-surface the same gaps/slices as if untouched.

The two layers compose: cross-session guards check the issue's state on GitHub (comments, labels, sub-issues); in-conversation guards check the current turn's history. Both must be honored.

### Step 0.5: Distill Product Essence; Quarantine PM-Technical Content

When the issue is an **epic** or is otherwise authored by a non-engineer (PM / product), do this BEFORE classification. **Skip for engineer-authored issues** — including the common case of an `intake-interviewer`-authored body (its `<!-- spec-review: ... -->` provenance marker signals a structured, engineer-grade spec). Most runs skip this step, and their `briefPath` stays `null` by design.

An epic's value is **domain knowledge and product intent**. Treat its _technical_ content as a hypothesis to verify, never as a constraint — you re-derive that layer yourself (Steps 2–3).

**Bias toward quarantine.** LLM-drafted technical content arrives fluent and dressed in codebase-shaped vocabulary, but plausibility is not grounding. When you are unsure whether a statement is product intent or a technical guess, **quarantine it**.

**Author-posture knob (presentation only).** When the invocation (e.g. the `intake` router) or the user identifies the spec's author as technical (engineer / QA / senior technical staff), the quarantine mechanics are IDENTICAL and every quarantined claim is still verified in Step 3. Only presentation changes: technical-author claims are surfaced as credible hypotheses ("author proposed X — confirmed/conflicts"), not as noise, and a `confirmed` claim may adopt the author's exact wording. This knob is never license to relax verification. Default when the author profile is unknown: PM posture.

Sort every part of the spec into two buckets:

**KEEP — Product Essence (binding intent):**

- The problem and who has it; user goals / jobs-to-be-done
- User-facing behavior, flows, copy
- Business rules & invariants stated in **domain** terms (not schema terms)
- Acceptance criteria as observable outcomes — **preserve `AC-n` IDs verbatim** when the source carries them; if it doesn't, assign IDs per the positional fallback rule (normative home: review-toolkit's `scope-completeness-reviewer` agent) and mark each `derived`
- Explicit in-scope AND out-of-scope deliverable lists
- Product-level non-functional constraints (as requirements, not as the mechanism)

**QUARANTINE — PM-technical (advisory only, NEVER binding):** suggested decomposition / sub-issue lists; proposed endpoints, routes, slugs; schema / field names, data shapes; dependency graphs; tech-stack / library / pattern choices; estimates; any "how".

Produce a **Product-Essence Brief** — a clean restatement of the KEEP bucket only. This brief, NOT the raw epic, is what propagates downstream (codebase-explorer scope, the Step 5 coverage back-check, decomposition). Capture the QUARANTINE bucket separately as **"PM-technical claims (advisory — verify against codebase)"**. After codebase-explorer returns (Step 3), reconcile each claim and tag it:

- **confirmed** — matches codebase / conventions; adopt.
- **conflicts** — codebase says otherwise; the codebase wins. Surface the conflict to the user; never silently follow the PM guess.
- **unverifiable** — no codebase signal; defer to implementation-time.

**User guardrails outrank both buckets.** If the user has stated a deviation, that is binding truth even where the PM's product text says otherwise — record it in the brief as a settled decision, above PM intent.

**Tracker-body invariant:** `AC-n` IDs reach the scope-completeness gate only through the tracker ticket body — the GitHub issue body, or the JIRA description — because its independence contract ignores dispatch/state input. When recommending ticket bodies or sub-issue/sub-ticket splits, carry the AC section verbatim — paraphrasing it silently downgrades scope review to fallback numbering.

### Step 1: Classify the Issue Type

Based on the issue body and labels, classify as:

| Type          | Signal                                          | Pipeline Path                         |
| ------------- | ----------------------------------------------- | ------------------------------------- |
| Bug fix       | "fix", "broken", "error", "regression"          | Spec review only — skip decomposition |
| Feature       | "add", "new", "implement", "build"              | Full analysis                         |
| Enhancement   | "improve", "extend", "update"                   | Full analysis                         |
| Refactor      | "refactor", "restructure", "migrate", "extract" | Light analysis                        |
| Chore / infra | "ci", "config", "dependency", "tooling"         | Spec review only — skip decomposition |

**Edge case**: If a "bug" is actually a rewrite (e.g., "auth flow is fundamentally broken — rebuild it"), reclassify as feature/refactor and proceed with full analysis. Comment the reclassification on the issue.

### Step 1.5: Pair-Repo Title Check (only when `topology.type: be-fe-pair`)

**Applicability.** This step runs only when the repo's own config declares
`topology.type: be-fe-pair` — reading
`topology.repos.<id>.ticketTag` (e.g. `"[BE]"` / `"[FE]"` on the `be`/`fe` entries; no
new field, no onboarding change). A `standalone` or `monorepo` repo has no `ticketTag` at
all and nothing to check here — skip straight to Step 2. Under the lean lane this reading
is **intake policy, never a gate**: `lean-gate.sh` does not read `ticketTag` and this check
does not touch it either — it is this skill deciding whether to proceed, not a mechanic
`lean-gate.sh` enforces.

**The check.** The predicate is the **configured tag values**, not bracket shape. Resolve
them first, with `contains` semantics:

```bash
CONFIG="${SECOND_SHIFT_CONFIG:-$(git rev-parse --show-toplevel)/.claude/second-shift.config.json}"
# $TITLE = the fetched issue/ticket title (github: `gh issue view`; jira: the summary).
MATCHED=$(jq -r --arg t "$TITLE" '
  [ .topology.repos | to_entries[]
    | select((.value.ticketTag // "") as $tag | $tag != "" and ($t | contains($tag)))
    | .key ] | join(" ")' "$CONFIG")
DECLARED=$(jq -r '[ .topology.repos[] | .ticketTag // "" | select(. != "") ] | length' "$CONFIG")
```

A title may carry any number of other bracket tokens (`[BUG]`, `[urgent]`, a team prefix);
they are not tags of this pair and this step ignores them.
Branch on how many of the **declared** tags matched:

- **`DECLARED` is under 2 — the pair does not declare a tag on both entries.** Nothing to
  check: skip to Step 2 and say so in the intake comment (this repo's pair config does not
  tag both sides, so which side a ticket targets is the filer's to state in the body). Never
  reject here — the ticket is not defective, the config simply does not declare the tags the
  rule reads. `ticketTag` is optional in the schema and `/second-shift:onboard`'s
  confirmed-pair draft does not emit it at all, so an untagged pair is the *ordinary* shape
  of a freshly onboarded one, not an edge case; a half-tagged pair fails the same way for the
  untagged side alone. (Same reasoning that gates the whole step on `be-fe-pair`: a rule keyed
  on two tags cannot fire where two tags do not exist.)
- **Exactly one declared tag matched** — this ticket belongs to that side. Proceed to Step 2
  normally (BE-tagged work stays here; an FE-tagged ticket in a BE repo's queue is a routing
  mistake — comment saying so and stop, same label as below).
- **Both declared tags matched** — the ticket declares cross-repo scope but was filed as a
  single ticket. **Reject at intake exit**: do not dispatch spec-reviewer, do not attempt to
  guess a split from the title alone. Comment explaining that a pair ticket is never worked
  as one artifact — same principle as the stacked-PR retirement — and that it needs either
  two single-tagged tickets, or (if the scope genuinely spans both repos) to be handed to
  this step's own decomposition path once re-filed with a single tag — see Step 4's
  cross-repo admission rule.
- **Neither declared tag matched** (whatever else the title carries) — same terminal reject,
  different reason: nothing tells a human, or the future thin orchestrator, which side of
  the pair this ticket targets. Comment asking for the single correct tag in the title, and
  stop.

**github:** label `needs-spec-work` on either reject — this is a filing-convention defect,
not a judgment call, so it is not `needs-intake-review`. _(jira: tracker delta.)_ no label
exists to set; present the same comment content to the operator and STOP, per this skill's
existing jira escalation posture.

Both rejects are terminal and are caught before a single agent dispatches. The **both** case
is a filing defect: one ticket cannot span two repos, because `lean-gate.sh` routes by
invocation cwd and works exactly one repo's worktree. The work is not refused, it is
re-shaped — into ordered per-repo tickets at Step 4.

### Step 2: Gather Evidence (structured intake fan-out)

Evidence-gathering is a fan-out of `spec-reviewer` + `codebase-explorer` that returns **rationale-carrying structured findings**, not prose. The orchestrator reasons over the structured object (Step 3) — `{ verdict, findings[] }` for spec-reviewer (each finding carries `severity`/`claim`/`rationale`/`confidence`) and `{ modulesAffected, crossModuleDependencies, estimatedScope, findings[] }` for codebase-explorer.

**Transport (the reasoning is identical across both):**

- **Production:** run the dev-pipeline intake Workflow **directly** via the `Workflow` tool — pass `intake-review.mjs` as the `scriptPath` and the call args as `{ issue, issueBody, referencedDocs, agents, readRoot, config }` (`readRoot` — optional absolute path to the pinned read surface, the detached `origin/<base>` worktree; when set, every dispatch prompt is prefixed with the pinned-read instruction. `config` — carries ONLY the config keys this script reads, which is `reviewers` alone: pass `{ reviewers: CONFIG.reviewers }`, where `CONFIG` is the parsed `second-shift.config.json`. This is what makes `reviewers.modelOverrides` reachable for `spec-reviewer`/`codebase-explorer`; omitting it leaves every intake agent pinned to its shipped table tier no matter what the consumer configured. Do **not** pass `CONFIG` whole — its `commands.<host>` shell-command strings and top-level `$schema` go through Workflow arg serialization, the payload that killed a dispatch outright — and do **not** pass `{ reviewers: {} }`, the opposite trap that serializes cleanly while silently disabling every override). It dispatches the selected sub-agents as `agent({ schema })` in `parallel()` and returns `{ specReview, codebaseExplorer }`. This mirrors the reviewer fan-out (`workflows/code-review.mjs`). Do **not** wrap it in a nested `workflow()` call with a repo-relative path: a nested `workflow({ scriptPath: '.claude/.../intake-review.mjs' })` resolves the path relative to the workflow-scripts dir, not the repo root, so it path-doubles and fails — use an absolute `scriptPath` (or the bare filename) when invoking the `Workflow` tool.
- **Under the eval harness:** the Workflow runtime is not mocked, so the harness dispatches the sub-agents via the `Task` tool with the structured findings fed as the mock payload. Same structured object reaches the orchestrator — only the transport differs.

**For bug/chore (spec review only):**

- Gather `spec-reviewer` only (`agents: ['spec-reviewer']`).
- Input: issue body + referenced docs (max 5 — pick most relevant, note which were skipped)
- Skip to Step 4

**For feature/enhancement/refactor (full analysis):**

- **Clean-marker skip (elide the redundant `spec-reviewer`).** `intake-interviewer` already runs `spec-reviewer` as a self-check and records the outcome as a provenance marker in the emitted body. Parse it from the GitHub-normalized body — already in hand from the Step 0 `gh issue view --json body,comments,labels` read; HTML comments are whitespace-stable, so key on the parsed fields, **never** a body hash:

  `<!-- spec-review: verdict=<v> blockers=<n> -->`

  **Skip the `spec-reviewer` dispatch — gather `codebase-explorer` only (`agents: ['codebase-explorer']`) — iff ALL hold:** marker present, `verdict == implementable`, `blockers == 0`, AND the body is **self-contained**:

  - **under 2000 chars** (length of the GitHub-normalized `body`) — sized so the interviewer's fixed feature scaffolding plus terse single-capability content qualifies, while multi-capability / detail-heavy specs (the ones that warrant a fresh second review) run longer; conservative because a false skip silently drops a real review; AND
  - **no referenced docs/ADR links** — the same scan as "Finding referenced docs" below (file paths / ADR references / repo-doc links); a bare GitHub issue ref (`#NNN`, e.g. a `## Related` parent link) does **NOT** count; AND
  - **single-section AC** — exactly one `## Acceptance Criteria` H2 with no nested sub-headings (`###`+) inside that section.

  Otherwise — no marker, `verdict != implementable`, `blockers > 0`, or a non-self-contained body — gather both as below. This skip is scoped to **this feature/enhancement/refactor path only**: the bug/chore path (above) gathers `spec-reviewer` only and never consults the marker (skipping it there would dispatch nothing).

- Gather `spec-reviewer` and `codebase-explorer` (`agents: ['spec-reviewer', 'codebase-explorer']`), in parallel — **unless the clean-marker skip above selected `codebase-explorer` only.** `codebase-explorer` **always** runs.
- After the structured `codebaseExplorer` object is in hand, run the **Dependency Analysis subroutine** (see the dedicated section below) over its `modulesAffected` / `crossModuleDependencies`.

**Finding referenced docs:** Scan the issue body for file paths, ADR references, or repo-doc links. Resolve up to 5 with Read. If a linked doc doesn't exist, note it as a potential spec gap. Pass the resolved docs to the fan-out as `referencedDocs`; if none are linked, pass only the issue body.

### Step 3: Evaluate Findings

**Budget exhaustion (not a failure):** If the intake Workflow returns `budgetExhausted: true`, its `specReview`/`codebaseExplorer` are `null` because the operator's turn token budget ran out before the fan-out dispatched — NOT because a sub-agent crashed. Do **not** escalate `needs-intake-review` on this. Surface the budget exhaustion as a transient condition and stop so the operator can re-run with budget available; the null spec review here carries no signal about the spec's implementability.

**Sub-agent failures:** If any sub-agent returns an error or unreadable output (and `budgetExhausted` is not set):

- `spec-reviewer` failure: escalate via `needs-intake-review` — do not proceed without a spec review
- `codebase-explorer` failure: fall back to your own codebase reading (Grep/Glob/Read) and note the gap in the issue comment. The dependency-analysis subroutine then runs over your fallback output.

**Spec-reviewer findings:**

- Stop processing after 3 true blockers — spec fails regardless
- For each finding, ask: "Is this a real problem, or is the spec-reviewer being overly cautious?"
- Classify remaining findings as resolvable gaps or true blockers (same definitions as the pipeline's intake)
- Resolve up to 5 resolvable gaps yourself — read code/docs, make decisions with rationale
- If >5 resolvable gaps: escalate via `needs-spec-work` — spec needs rewriting
- If true blockers remain after resolution: escalate via `needs-spec-work`

**Codebase-explorer findings:**

- Verify the impact surface makes sense — does the explorer's module list match what the spec actually touches?
- Note the estimated scope (files to create/modify, modules touched)

**Dependency analysis output:**

- Verify dependency chains are real — confirm claimed import/type dependencies actually exist (the subroutine runs in-session, but the same skepticism applies to your own work).
- Note independent groups and chains.

### Step 4: Make Decomposition Decision

**Skip for bug/chore** — always `no-split`.

**For feature/enhancement/refactor**, apply judgment guided by these heuristics:

**Verdict: `sub-issues` (parallel)**

- Spec describes distinct capabilities that don't share state
- Dependency analysis shows independent groups
- Each part is in a different module or bounded context
- Parts can be merged in any order

**Verdict: `sub-issues-sequential` (ordered)**

- Dependency analysis shows a clear chain (schema → service → controller)
- Parts share a module but add incrementally
- Parts would collide on the same file if worked in parallel
- Each part is meaningful and reviewable on its own

The slices file as ordinary sub-issues, exactly like the parallel flavor — what differs is **ordering**, not branch topology. Every slice is a plain single-PR run against the configured `baseBranch`; ordering is carried by `Predecessor:` / `Successor:` body trailers and enforced by keeping blocked successors out of the queue (Step 6).

**Cross-repo admission rule (pair topology only — not a new verdict).** When
`topology.type: be-fe-pair` (Step 1.5) and the spec's scope genuinely crosses into the
sibling repo — codebase-explorer's impact surface, or the spec text itself, names behavior
that lives on the other side of the pair — this is the `sub-issues-sequential` verdict
above with one admission difference: the two slices are not both filed in this repo.

- The slice for THIS repo files exactly like any other sub-issue (Step 6).
- The slice for the sibling repo is filed in **the sibling's own tracker**, not this one —
  resolve the sibling's identity from this config's own `topology.repos.<sibling-id>.path`
  entry (reading that path's own git remote, if reachable in-session, for the
  `owner/repo` `--repo` argument). **Cannot resolve it → escalate `needs-intake-review` and
  ask the operator; never guess a slug.**
- Default ordering is BE before FE — the FE slice's spec pins the BE slice's landed API
  contract **as currently specified**, plus an explicit reconcile obligation in its body:
  at promotion (when the BE PR merges and the queue label is about to go on), confirm the
  landed contract still matches what the FE spec pinned, edit the body if it drifted, then
  apply the label — one line beside the existing "queue when `<predecessor>` is closed"
  note the sequential flavor already writes (Step 6 item 3). No new machinery: this is the
  existing ordering promotion, plus one sentence.
- Title each slice with its own single `ticketTag`, so a human or the thin orchestrator can
  route it correctly without re-reading the spec.
- This is the **only** path that produces a ticket in the sibling's tracker — a routine
  same-repo decomposition never does.

**Verdict: `no-split`**

- Touches ≤3 files across ≤2 modules
- Work is inherently atomic
- Splitting would create PRs too thin to be meaningful

**Run-cost bias (applies to BOTH sub-issue flavors).** A pipeline run is expensive — a full intake, plan, review, and verify cycle per slice. Weigh that cost when choosing slice boundaries:

<!-- LOCKSTEP: this skill owns the verdict, so it is the CANONICAL side. decomposition-reviewer
     mirrors the block below because it reviews splits against the same standard and must not
     drift into a softer one. Two live copies rather than a cross-reference: each skill is
     loaded on its own, into a session that has not read the other, so a pointer would resolve
     to nothing at the moment the rule is needed. Edit one, edit both. -->
<!-- LOCKSTEP-BEGIN decomposition-economy -->
Prefer fewer, fuller slices: as many as the work genuinely needs, and no more. A slice that cannot justify its own full pipeline run — because it is too thin to review on its own, or has no consumer until a later slice lands — merges into its neighbor. Splitting for the sake of splitting is a cost, not a virtue; every slice must be a logical, coherent unit of work that earns its own run.
<!-- LOCKSTEP-END decomposition-economy -->

This bias narrows slice counts; it never overrides the coupling rules above, and it is not licence to exceed the cap by merging unrelated work (see Threshold hygiene).

### Step 5: Self-Check

Before acting on your decision, verify:

- Does each slice have a clear scope?
- Can each slice be tested independently?
- Are boundaries clean — no circular dependencies?
- Does any slice touch >10 files? If so, reconsider.
- Could any slice be merged into its neighbor without making the result incoherent? If yes, merge it — the run-cost bias in Step 4.
- For `sub-issues-sequential`: is the ordering the only viable one, and does every slice after the first genuinely depend on its predecessor? A chain whose links are actually independent is a parallel `sub-issues` decomposition, and serializing it costs the operator a merge round-trip per slice for nothing.
- **Counterfactual test**: would I group the same way if the cap were 10? If no, it's cap-driven — escalate `needs-intake-review` (see Threshold hygiene below).
- **Coverage back-check (when Step 0.5 produced a Brief):** reconcile the union of proposed slices against **every deliverable AND every explicit out-of-scope bullet** in the Product-Essence Brief; for engineer-authored specs with no brief, against the spec itself. Where deliverables derive from acceptance criteria, key the reconciliation by `AC-n` ID (explicit or `derived`) so nothing is double-counted or dropped between paraphrases. Each deliverable maps to exactly one slice, OR carries an explicit "deferred — owning follow-up" note; any deliverable with no slice and no deferral → STOP and escalate.

### Step 5.5: Receipt Exit Gate

Whatever the verdict, INTAKE's output is a **receipt** — the artifact BUILD is handed as the
definition of settled intent. Three things happen before it leaves your hands.

**1. Scan for duplicates.** Before anything is labeled or handed off:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/plan-interview/tools/dup-scan.sh" --issue {ISSUE_NUMBER}
```

This scans **this** issue, which is what `no-split` hands to BUILD carrying the queue label. It
is not the whole obligation: on the `sub-issues` routes the queue label moves off this issue and
onto slices that do not exist yet, and Step 6 scans each of those before creating it. A ticket is
scanned at the point it becomes eligible, and for a slice that point is its own creation.

Three exit codes, three different obligations:

- **`0`** — nothing at or above the threshold. Record nothing; a clean scan is not a decision,
  and padding the register with one is what `interviewing-baseline` forbids.
- **`10`** — ranked candidates on stdout. **Read each one and judge it yourself.** The scorer
  proposes; it cannot decide, and two tickets written by different routes can share most of
  their vocabulary and still be different work. One ledger row per candidate: the same work
  (fold this ticket into it, and say so), overlapping but distinct (queue it — and sequence it
  if they touch the same files, because a candidate carrying the *claimed* label is already
  being built), or unrelated. **Never close a ticket on this output.**
<!-- LOCKSTEP-BEGIN dup-scan-rc2 -->
- **`2`** — the scan could not run. Hard-stop: report the rc and the reason, and hand nothing off.
<!-- LOCKSTEP-END dup-scan-rc2 -->
  Do not apply the queue label; exit non-zero and let the operator fix it and re-run intake.
  A proceed-with-a-flag variant is not available: the flag lands in a local receipt the next
  claimant never reads, while the queue label still advertises the ticket as eligible.

Under `tracker.type: jira` the tool prints an explicit not-applicable line and exits `0`: that
adapter has no queue label and no claimed label, so there is no corpus of eligible tickets.

**2. Lint it.** Write the ledger you assembled to `.claude/pipeline-state/{ISSUE_NUMBER}-ledger.md`
in the receipt shape (`interviewing-baseline` → "The intake receipt": five columns, plus a
`## Open Regions` section and a `## Surface Inventory` section — each carrying rows or its own
explicit empty form) and run:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/plan-interview/tools/ledger-lint.sh" \
  --receipt .claude/pipeline-state/{ISSUE_NUMBER}-ledger.md
```

`${CLAUDE_PLUGIN_ROOT}` is intake-toolkit here, and the lint ships in this same plugin — this
is a sibling-skill path, not the cross-plugin resolution the bot-writes note above describes.

A red lint is not a formatting complaint, and it has two distinct causes.

**A ratification failure.** An `intent` row backed by `codebase-derived` / `ticket-sourced` /
`deferred` means you recorded a decision *you* made as one the human made — either ask them, or
reclassify it honestly (a derived fact, or an `open` row under a declared region). Do not edit
the Kind cell to clear the lint.

**A surface-inventory failure.** A missing `## Surface Inventory`, a `decided` disposition citing
no `D-n` (or citing one the ledger never declares), or an `out-of-scope` carrying no reason means
the decomposition has a user-visible surface it never accounted for. Enumerate the surfaces the
work implies, then give each one a decision to cite or a stated reason it is out of scope. The
empty form (`No user-visible surface — this change renders nothing a user reads.`) is for work
that genuinely renders nothing — it is not a way to clear the section.

**3. Probe it.** Dispatch `intake-toolkit:implementability-probe` via `Task`, handing it the
**spec text alone** — no interview transcript, no ledger, no findings from this session. It is
the proxy rung, and it only works blind: residue from the elicitation is exactly the context the
cold implementer will not have. It returns guess-points, not fixes. For each one:

- the answer is the human's → an interview question, and a new ledger row;
- the answer is knowable from code → resolve it and record a `fact` row;
- the answer is genuinely undecided → a declared `OR-n` with a disposition.

Feed the resolutions back and re-lint. Two probe rounds maximum — after that, emit with the
remaining guess-points as declared open regions rather than looping.

Skip the probe on bug/chore and on genuinely small scope; when you skip it, **say so and why**
in the Step 6 comment. A silent skip is the failure mode this rung exists to catch, because the
critic rung above it has already been observed approving a spec that then broke in
implementation.

### Step 6: Act on Verdict

The write operations below are the **github** adapter (`tracker.writes: true`) _(jira: tracker delta.)_

**`no-split`:**

1. Post spec review results + resolved decisions as issue comment _(jira: tracker delta.)_
2. Return control to the caller (the lean lane's build half cuts the worktree at its checklist step 3)

**`sub-issues` (parallel) and `sub-issues-sequential` (ordered)** — one creation flow, two label/trailer postures:

1. Verify ≤5 sub-issues (one cap, both flavors). If >5: escalate via `needs-intake-review`
2. For each sub-issue, synthesize a self-contained spec from your analysis — not a copy-paste of the parent, but a focused spec for that slice. **Every** sub-issue body carries:
   - the `Part of #{ISSUE_NUMBER}` anchor (also the dedup key the Step-0 resume guard searches for);
   - its acceptance criteria **verbatim**, `AC-n` IDs intact — the tracker body is the only channel that reaches the scope-completeness gate, so a paraphrase silently downgrades it to fallback numbering;
   - when Step 0.5 produced a Brief: the **full reconciled QUARANTINE table** (all three tags, verbatim) and the settled user guardrails, so parent-level decisions are not re-litigated per sub-issue.
3. **Sequential flavor only — ordering trailers.** You know the whole chain in this one batch, so write both directions at creation: each sub-issue after the first carries `Predecessor: <key>`, and each predecessor carries a forward `Successor: <key>`. Render keys per the adapter's `tracker.keyPattern` (`#` prefix optional on github), one trailer per line, as the body's last lines. A blocked body also states plainly: **"queue when `<predecessor>` is closed."**
4. **Scan each slice for duplicates — before it is created, not after.** Step 5.5 scanned the
   *parent*, and on this route the parent is the one item that ends up **without** the queue
   label. The slices below are the ones this exit actually mints as eligible, and none of them
   existed when that scan ran. Scan each synthesized body, as a draft subject:

```bash
# per slice, with $SLICE_BODY already written to a file:
bash "${CLAUDE_PLUGIN_ROOT}/skills/plan-interview/tools/dup-scan.sh" \
  --title "[slice title]" --body-file "$SLICE_BODY_FILE"
```

   Same three obligations as Step 5.5 — `0` record nothing, `10` judge each candidate and write
   a ledger row, and on `2`:

   <!-- LOCKSTEP-BEGIN dup-scan-rc2 -->
   - **`2`** — the scan could not run. Hard-stop: report the rc and the reason, and hand nothing off.
   <!-- LOCKSTEP-END dup-scan-rc2 -->

   Create nothing and label nothing. The cost is an operator re-run; proceeding mints up to five
   queue-labeled tickets that nothing ever looked at.

   Scan the blocked successors too, not just the queued first slice. Promotion at merge time is
   a bare label edit by an operator who runs no scan, so creation is the only point where a
   successor is ever looked at.

   **The corpus does not contain the sibling slices** — they are unfiled, and a decomposition's
   slices are related to each other by construction, so scoring them against one another would
   report the split itself as a duplicate. The question here is whether a slice duplicates work
   already queued or in flight, which is exactly the corpus the tool reads.

5. Create sub-issues (github adapter). **The queue label is where the two flavors diverge:**

```bash
# parallel — every slice is immediately workable:
$GH_BOT_SH issue create --title "[slice title]" --body "$BODY" --label ready-for-dev --label <opus|sonnet>

# sequential — ONLY the first slice enters the queue; N>1 are created WITHOUT it:
$GH_BOT_SH issue create --title "[slice 1 title]" --body "$BODY_1" --label ready-for-dev --label <opus|sonnet>
$GH_BOT_SH issue create --title "[slice N title]" --body "$BODY_N" --label <opus|sonnet>   # no queue label
```

   **The sizing label rides along, on every slice including the blocked ones.** `opus` or
   `sonnet`, your judgment on the slice's weight — intake is where weight is actually assessed,
   and the lane's scheduler reads that label to pick the build model. It is tracker state, so
   reading it costs the scheduler no content judgment; leaving it off does not block anything,
   but it pushes the call onto a session that has read the ticket far less carefully than you
   just did.

   Keeping blocked successors **out of the queue** is the ordering enforcement — not rejecting them after they are claimed. Promotion is an operator action at merge time: merging the predecessor's PR is already the serialization point, so labelling the successor rides that same action. **Nothing renders that reminder for you** — no lane writes a promotion line onto the predecessor's PR, so the successor's `ready-for-dev` label is an unprompted operator action. Say so in the predecessor's spec, or the chain stalls silently. No claim is ever burned and no failed state file is created for the routine blocked case. `../predecessor-gate.sh` is only the pre-claim backstop for a successor that got labelled early.

   _(jira: tracker delta.)_

   **Cross-repo admission rule only (Step 4, pair topology):** the sibling's slice is created with
   `--repo <resolved-sibling>` instead of the implicit current repo, everything else about
   its trailers/labelling identical to the ordered flavor above. This is the one case in
   this skill where a sub-issue is filed anywhere other than the current repo's tracker.

6. Update parent issue (github adapter):

```bash
$GH_BOT_SH issue edit $ISSUE_NUMBER --add-label epic --remove-label ready-for-dev --remove-label in-progress
gh issue edit $ISSUE_NUMBER --remove-assignee @me
```

   _(jira: tracker delta.)_

7. Post decomposition rationale + links as issue comment _(jira: tracker delta.)_ For the sequential flavor, state the order explicitly and which slice is queued.
8. Pipeline stops for this run — both flavors are stopping verdicts; each sub-issue is its own scope contract and gets its own run.

### Brief persistence

When Step 0.5 produced a Product-Essence Brief, write it to `.claude/pipeline-state/{ISSUE_NUMBER}-brief.md` before returning control — on `no-split` (where it hydrates the run's own gates) **and on `sub-issues-sequential`**, where the pipeline stops but the Brief is the audit artifact the per-sub-issue QUARANTINE carry (step 2 above) can be verified against — the KEEP restatement, the reconciled QUARANTINE table (`confirmed | conflicts | unverifiable`, post-Step-3), and any settled user guardrails. Local gitignored file (the whole `.claude/pipeline-state/` tree is gitignored), written in the invocation repo **pre-worktree** so it survives worktree cleanup. The dev-pipeline resolves `briefPath` by checking this conventional path (only when the orchestrator wrote it **this run** — a stale brief from a prior run never leaks). Engineer-authored issues (no Step 0.5) write no brief; `briefPath` stays `null`.

## Thresholds

| Dimension                        | Cap          | Action if exceeded               |
| -------------------------------- | ------------ | -------------------------------- |
| Sub-issues (either flavor)       | Max 5        | Escalate: `needs-intake-review`  |
| Resolvable gaps                  | Max 5        | Escalate: `needs-spec-work`      |
| True blockers from spec-reviewer | Stop after 3 | Spec fails                       |
| Referenced docs                  | Max 5        | Pick most relevant, note skipped |
| Files per slice (warning)        | >10          | Reconsider split                 |

**Threshold hygiene (counterfactual test):**

When the natural decomposition of a feature lands near or above a cap, apply the counterfactual test before picking a verdict:

> "If the cap were 10 instead of 5, would I still make these grouping choices?"

- **YES** — the grouping reflects real coupling. Proceed with the verdict (either sub-issue flavor).
- **NO** — the grouping is cap-driven. Escalate via `needs-intake-review`; do NOT output "4 sub-issues" after collapsing three because the cap forced it.

Two legitimate reasons to merge multiple work items into a single slice:

1. **Bidirectional dependency** (subroutine "Tightly coupled items"): items literally cannot compile or ship separately.
2. **Shared abstraction at a single module boundary**: multiple items all route through one service method, one schema, or one config module where splitting would force a public interface to exist solely for the split's sake. Example: an endpoint + its nightly worker that both call a single `DiversityService.compute()` method — packaging them together is natural regardless of the cap.

NOT a shared abstraction (flag as weak-coupling; do not merge): **shared infrastructure is not a shared abstraction.** Example: two endpoints that both query the same table via different services — the common dependency is infrastructure they happen to sit on, not a seam that splitting would force open.

Flag as cap-driven gaming (escalate instead) when:

- You pair unrelated items because "they're both UI" or "they're both backend."
- Your grouping collapses 6+ natural candidates into exactly 5 sub-issues.

The run-cost bias (Step 4) and this rule pull in opposite directions on purpose: merge a slice because it cannot earn its own run, never because the cap forced it. If the honest count still exceeds 5, escalate.

## Escalation

When you're not confident in your decision, STOP and escalate:

**Triggers:**

- Sub-agent findings contradict and you can't reconcile
- Issue type is genuinely ambiguous
- Decomposition has circular dependencies or unclear boundaries
- Multiple valid decompositions exist with real consequences
- Domain/business logic you don't have context for
- Any threshold exceeded

**Mechanism (github adapter):**

1. Comment on issue: `stage: intake`, `status: needs-human-input`
   Include: what you understood, what's uncertain, the options you're considering, a clear question
2. Label: `$GH_BOT_SH issue edit $ISSUE_NUMBER --add-label needs-intake-review --remove-label in-progress`; `gh issue edit $ISSUE_NUMBER --remove-assignee @me`
3. **STOP**

_(jira: tracker delta.)_ Surface the same content to the operator in-session and STOP.

## Issue Comment Format

All comments follow the pipeline's machine-readable format:

```
<!-- dev-pipeline -->
<!-- run_id: {RUN_ID} -->
<!-- stage: intake -->
<!-- status: {status} -->

Human-readable analysis here.
```

Status values: `passed`, `passed-with-decisions`, `failed`, `split-into-sub-issues`, `split-into-sub-issues-sequential`, `needs-human-input`

## What NOT to Do

- Don't question product decisions — that's the human's call
- Don't propose alternative architectures — decompose what's asked for
- Don't rewrite the spec — point out issues, resolve gaps, move on
- Don't split for the sake of splitting — the run-cost bias in Step 4 is the rule; a slice that cannot earn its own pipeline run merges into its neighbor
- Don't separate tests from the code they test
- Don't split a migration from the code that depends on it
- Don't create sub-issues that can't be understood without reading the parent
- Don't relay sub-agent findings verbatim — add your own judgment

---

## Dependency Analysis (subroutine)

Inlined from the deprecated `dependency-analyzer` agent. Runs in-session as the second half of Step 2, after `codebase-explorer` returns — never as a Task dispatch (Pre-flight).

### Inputs

- Issue body (from Step 0).
- Impact surface report from `codebase-explorer` (or your own fallback Grep/Glob/Read scan).
- The repo's `CLAUDE.md` (and whatever convention docs / knowledge skills it routes to) define codebase conventions.

### Step A: Identify Work Items

From the spec, extract discrete units of work. A work item is a change that:

- Has a clear start and end
- Produces something testable or reviewable
- Could conceptually be a commit or small PR

Examples: "add schema for X", "create service Y", "add endpoint Z", "write migration for W".

**Cap:** Extract at most 10 work items. If the spec contains more, group closely related items before analyzing dependencies. Note any grouping decisions.

**Implicit infrastructure:** Check for shared infrastructure that all work items depend on (DB migrations, shared config files, new packages). List these as a work item with dependencies from all others — they are easy to miss because they're often implied, not stated.

### Step B: Analyze Dependencies Between Work Items

For each pair of work items, determine:

1. **Does item B depend on item A?** — B uses types, interfaces, tables, or APIs that A creates
2. **Is the dependency hard or soft?** — Hard: B literally cannot compile/run without A. Soft: B could use a stub or interface, but would be cleaner with A done first.
3. **Is the dependency bidirectional?** — If so, they may need to be in the same PR (can't be split)

Use the impact surface to verify: if item A creates `types/Foo.ts` and item B imports from `types/Foo.ts`, that's a hard dependency.

### Step C: Identify Independent Groups

Group work items into:

- **Independent clusters**: Groups with no dependencies between them (candidates for parallel sub-issues)
- **Dependency chains**: Sequences where each item depends on the previous (candidates for `sub-issues-sequential`)
- **Tightly coupled items**: Items with bidirectional dependencies (must stay together)

### Step D: Assess Ordering Flexibility

For each dependency chain:

- Is this the only valid ordering?
- Could items be reordered with minimal interface changes?
- Are there natural "seams" where the chain could be split into independent groups?

### Subroutine output (feeds Step 3 / Step 4)

```
## Dependency Analysis: [spec title in ≤10 words]

### Work Items Identified
1. **[item-id]**: [short description] — touches [files/modules]
2. ...

### Dependency Graph
- [item-A] → [item-B] [HARD]: [reason — "B imports types from A", "B calls API created by A"]
- [item-C] → [item-D] [SOFT]: [reason — "D could stub C, but cleaner with C done first"]
- [item-E]: independent (no incoming or outgoing dependencies)

HARD = B cannot compile or run without A. SOFT = B could use a stub or interface, but would be cleaner with A done first.

### Independent Groups
- **Group 1**: [item-E, item-F] — no shared state, different modules
- **Group 2**: [item-G] — standalone

### Dependency Chains
- **Chain 1**: [item-A] → [item-B] → [item-C] — [why this ordering is required]

### Tightly Coupled Items
- [item-H, item-I] — bidirectional dependency, must stay in same PR: [reason]

### Ordering Flexibility
- Chain 1: [rigid — B literally imports from A] or [flexible — could reorder with interface extraction]
```
