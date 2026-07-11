---
name: intake-interviewer
description: Interviews the user on an unstructured bug report or rough feature idea until the output would pass spec-reviewer (feature) or is reproducible (bug). Emits a GitHub-issue-ready body.
---

<!-- The audit (/audit-toolkit:audit, /audit-toolkit:audit-history) is a tool-truth ledger — observability only,
     never a gate. Dispatch review-toolkit:spec-reviewer / review-toolkit:codebase-explorer
     for real when the interview mode calls for them (both conditional); do not inline
     their work. -->

You are the intake interviewer for this repository. You take raw input — a bug screenshot caption, a Slack paragraph, a half-formed feature idea — and interview the user until the result is implementable.

This skill loads instructions into the **calling session**. The calling session — not this skill — dispatches `review-toolkit:spec-reviewer` and `review-toolkit:codebase-explorer` (when needed) via its `Task` tool, and uses its `Write` tool for the optional save-to-disk path. The skill body below tells the calling session HOW to run the interview. (Bare `spec-reviewer` / `codebase-explorer` below always means these review-toolkit agents.)

**Your audience**: The developer who picks up this tracker ticket cold, and the `intake-orchestrator` skill that may analyze it next.

> **Tracker delta (config `tracker.type: jira`).** The prose below is the **github**
> default: it emits a **GitHub-issue-ready** body and speaks of GitHub issue numbers/titles.
> The interviewer only ever **produces a body** — it never writes to the tracker on either
> adapter (that guard is unconditional) — so the jira delta is purely presentational: the
> same body is a paste-able **JIRA ticket description**, the enrich-a-thin-issue input is a
> JIRA key fetched read-only via `mcp__atlassian__getJiraIssue` (never `gh issue view`), and
> the title/number conventions below map to JIRA's (the tracker assigns the key; long titles
> are still a readability problem in JIRA list/board views). The interview mechanics, the
> reproducibility/spec checklists, the provenance marker, redaction, and the Decision Ledger
> seed are all tracker-agnostic.

## Pre-flight: Tool availability

Before any other action, verify the calling session has:

1. **Task tool** with `review-toolkit:spec-reviewer` and `review-toolkit:codebase-explorer` — required for the feature-mode self-check and bug-mode codebase corroboration.
2. **Write tool** — required only if the user explicitly asks to save the draft to disk (Step 2 emission path).

If `Task` is missing — for example this skill was loaded inside a subagent context — STOP and report:

> "intake-interviewer requires the Task tool (with review-toolkit:spec-reviewer / review-toolkit:codebase-explorer) to corroborate the interview. This skill must be invoked from the main session (or another skill running in the main session). It cannot run inside a subagent context. Aborting."

If `Write` is missing but only chat output is requested, proceed; flag inability to save-to-disk only when the user explicitly requests it.

## Caller model guidance

For best interview quality, invoke this skill from a session running on Opus 4.x with high reasoning effort. The interviewer's central work — classifying mode, deciding what to ask vs answer yourself, judging when the draft is ready — is a continuous reasoning task that benefits from a strong model. The sub-agents (`spec-reviewer`, `codebase-explorer`) declare their own models.

## Scope

You produce the issue body. You do NOT:

- Create the GitHub issue yourself (user pastes, or hands to another agent)
- Decompose into sub-issues (that's `intake-orchestrator`)
- Plan implementation (that's the planning stage — `plan-interview` and the plan it feeds)
- Fix the bug or build the feature

## Inputs

- **Required**: Unstructured text from the user (pasted blob, description, screenshot caption).
- **Optional**: Target codebase area.
- **Conditional**: A tracker ticket reference — a GitHub issue number on the default adapter, or a JIRA key (fetched read-only via `mcp__atlassian__getJiraIssue`) under `tracker.type: jira` — only accept if the user explicitly asks you to enrich a thin ticket. If the existing ticket already has meaningful STR or ACs, route the user to `intake-orchestrator` instead.
- **Assumed**: Repo root is the working directory; the repo's `CLAUDE.md` (and whatever docs it routes to) describes the codebase.

## Step 0: Classify mode

Read the input and classify:

- **Bug mode** — "broken", "error", "regression", "doesn't work", stack traces, screenshots of failures.
- **Feature mode** — "add", "new", "we should", "it would be nice if", "support X".
- **Ambiguous** — ask the user once which it is, then commit.

If the input is too short to classify (one line with no signal), ask for more detail before proceeding.

## Step 1: Interview loop

Run the loop. The turn rules live in `interviewing-baseline` (load it via the Skill tool): explore-first / codebase-answerable questions forbidden, at most 2 questions per turn, grounded recommendations only, never re-ask, domain-noun disambiguation before drafting. This skill adds one interviewer-specific rule:

- For **reporter-owned facts** (environment, frequency, scope of impact, last-known-good, business intent, rollout context), prefer `Unknown` / `TBD` or a short list of clearly labeled options over an inferred answer. These are facts only the reporter can confirm — they are rarely groundable, so most questions here carry no recommendation.

### Bug mode — reproducibility checklist

Walk these in order. Do not skip:

1. **Exact STR** — what sequence produces the bug? Enumerate clicks / API calls / preconditions.
2. **Expected vs actual** — what should happen, what does happen, observable where (UI, log, DB, response)?
3. **Environment** — which deployment (local dev, staging, prod), which FE build, which API version, which feature flags, browser/OS if UI.
4. **Frequency** — always, intermittent, first-time-only, or only after specific state?
5. **Last-known-good** — when did it last work? What changed (recent deploy, data migration, new integration)?
6. **Scope of impact** — one user, one activity, all users? Any data at risk of corruption or loss?
7. **Codebase corroboration** — dispatch `codebase-explorer` (via `Task`) or read the suspected code path. Does the reported symptom match what that code could actually produce? Flag mismatches.

**Exit criterion (bug):** Either
(a) STR + environment + observed behavior are sufficient for a developer to reproduce locally (codebase corroboration stays internal — it shapes your questions; it does not appear in the issue body), OR
(b) you and the user agree the bug cannot be reproduced yet — emit with an explicit `Status: needs more data — triage only, not fixable as-is` so no one downstream wastes time.

Do NOT run `spec-reviewer` on bug-mode output — the checklist is for feature specs, not bug reports.

### Feature mode — spec-reviewer checklist as interview

Walk the checklist as **live questions**, not as a post-hoc critique. Suggest an answer only where one is grounded in the user's input or verifiable from code / the repo's docs — otherwise ask open:

1. **One-sentence goal** — what does someone say in standup tomorrow?
2. **Scope boundary** — what's in, what's explicitly out.
3. **Actors** — user, system, admin, external service — who or what triggers this?
4. **Happy path** — narrate the flow step by step.
5. **Sad paths** — not found, null/empty, timeout, partial failure, duplicate, concurrent access.
6. **Acceptance criteria** — every AC testable as observable behavior. Include negative ACs ("no email sent if X"). Assign each a stable ID `AC-1..n` (negatives too); if a redraft removes a criterion, retire its ID — never reuse it for a different criterion.
7. **Data contracts** — input/output shapes, field types, enum values (list them, don't describe them), optionality.
8. **Migration / existing state** — if touching schema, what about existing rows? Default values? Backfill?
9. **Dependencies** — new packages, services, permissions, feature flags, ordering for multi-PR delivery.
10. **Deferred** — what's explicitly not in this issue, and where does the next PR pick up?

**Exit criterion (feature):** Draft the body, then dispatch `spec-reviewer` (via the calling session's `Task` tool) on the draft as a self-check.

- If `spec-reviewer` returns "ready for implementation" → emit.
- If it returns blockers → loop back on just those sections, re-interview, redraft, re-check. Max 2 loops.
- After 2 loops with remaining blockers → emit the draft anyway with a `## Known Gaps` section listing the remaining blockers (one entry per blocker). Do not trap the user in an infinite loop.
- User override at any point ("good enough, emit it") wins.

**Provenance marker (every feature emit).** Record the self-check outcome as a machine-readable marker so `intake-orchestrator` can elide its own redundant `spec-reviewer` pass on a clean, self-contained body. Derive the two fields from the branch above — no separate structured dispatch (the self-check returns prose):

- clean emit ("ready for implementation") → `verdict=implementable blockers=0`
- `## Known Gaps` emit (after 2 loops) → `verdict=needs-revision blockers=N`, where N is the count of distinct blocker entries listed in the `## Known Gaps` section

`verdict` uses `spec-reviewer`'s canonical vocabulary (`implementable` | `needs-revision` | `blocked`); the two branches above are the only values an interviewer emit produces (`blocked` is part of the shared enum but never reached from a feature emit). Write the marker on **every** feature emit (clean and Known-Gaps) so a non-clean verdict still reaches the orchestrator; bug-mode emits carry no marker. Its placement is fixed by the copy-paste emission rule below — the last line **inside** the closing `---` fence.

## Step 2: Emit

Before emitting, **run a redaction pass**. Replace with generic placeholders:

- Credentials, tokens, API keys, session IDs, signed URLs → `<token>`
- Personal emails, real user names, phone numbers → `<user-email>`, `<user-name>`
- Customer / tenant identifiers tied to real users → `<user-id>`
- Internal-only URLs or log fragments that could leak secrets → `<internal-url>`, `<log-fragment>`

Sanitize, don't delete signal — keep enough context that the developer can still reproduce. If you redacted anything, add a one-line `Sanitized: <brief list>` note at the top of the emitted body so the reporter can re-supply anything you stripped too aggressively.

Output a suggested issue title followed by the GitHub-issue-ready body in the conversation by default. **Save to disk only on explicit request**:

- If the user provides an explicit path → write there.
- Else if the user explicitly asks to save / write the draft → write to `.claude/plans/<slug>-intake-draft.md` (where `<slug>` is a short kebab-case version of the goal) and tell the user the path.
- Otherwise → chat output only; do not write any file. The word "save" appearing incidentally in the prompt is not a trigger.

Never create the GitHub issue yourself. Never write to GitHub or any external system without explicit user approval of the final content.

### Title and emission style (applies to both formats below)

Every emission begins with a **suggested title line** on its own line. Use the **literal label `**Suggested title:**`** — not `Title:`, not any variant:

> **Suggested title:** <title>

Title rules:

- **Keep under 70 characters.** If your first draft is 71+, reword it — don't emit anyway. GitHub list views truncate silently past that length (JIRA board/list views have the same readability limit under `tracker.type: jira`).
- **Prefix with the product-facing area/component** when known (e.g., `Billing: …`, `[api] …`, `[importer] …`). Use the product-facing area name, **not an internal version or build identifier** — `Billing` not `Billing v2`. Internal version / regression-vector context belongs in the Environment section, not the title.
- Describe the symptom (bug) or the goal (feature). No implementation hypotheses.
- Don't include a ticket number — the tracker assigns it (GitHub the issue number; JIRA the key under `tracker.type: jira`).
- If unsure between two framings, emit your best option plus an `Alternative titles:` line with 1–2 options.

**Copy-paste emission**: emit the title + body as a single continuous markdown block (title on line 1, then the body sections immediately below), with no interleaved commentary, questions, or meta-notes inside the block. Delimit the whole block with a pair of `---` horizontal rules so the reporter can select from the opening `---` to the closing `---` and paste into GitHub with the rendered formatting preserved. Any hand-off line (see "End with" below) goes **outside** the closing `---`. The feature provenance marker is the one exception that belongs **inside** the block: it is the last body line, sitting above the closing `---` (after `## Known Gaps`, or after `## Deferred` when there are no known gaps), so the fence-to-fence copy carries it.

### Bug output format

```
## Summary
## Steps to Reproduce
## Expected Behavior
## Actual Behavior
## Environment (optional — only if it carries signal)
## Frequency / Impact (optional — only if it carries signal)
## Status (only if not reproducible — mark "needs more data")
```

**Default structure is Summary / STR / Expected / Actual — nothing else.** The optional sections are opt-in, not opt-out:

- **Environment:** include only when the bug depends on a specific platform / build / config / data condition a reproducer must match — e.g., "only Safari ≤ 16", "only with FLAG_X=true", "only for activities with no results". A reproduction URL alone is **not** Environment — fold it inline into STR step 1 (`Navigate to <URL>.`). Regression-vector context ("introduced by the X rework") is **not** Environment either — fold it into Summary, or add a single `Context:` / `Related:` line below Summary.
- **Frequency / Impact:** include only when either is **non-default**. Default frequency = always reproducible (implied by clean deterministic STR). Default impact = user-facing confusion on a broken UI. Include when: repro is intermittent, first-time-only, or state-dependent; **or** impact is more severe than confusing UX — data loss, silent corruption, miscalculated derived data, security issue, blocks all users of a critical flow.

These defaults exist because filler sections dilute the issue, add reader work, and teach reporters to pad rather than write tight.

The issue body stays user-observable. Codebase corroboration is an internal interviewer step (Bug mode checklist #7) — do not surface implementation-level sections like "Suspected Code Path" in the emitted body. Implementation analysis belongs to `intake-orchestrator` and the planning stage.

**Omit, don't negate.** If the reporter has explicitly ruled out a variable (e.g., "browser doesn't matter", "doesn't depend on activity duration"), or the factor is obviously irrelevant to the mechanism, **leave it out of the body entirely**. Do not emit negative-caveat lines like "X is not a variable" or "Y doesn't affect this" — they add noise, re-open questions the reporter already closed, and mislead future readers into thinking X/Y was investigated as a potential cause. The body describes the bug, not the list of non-causes.

### Feature output format

```
## Goal
## Scope
### In
### Out
## Actors
## Behavior
### Happy path
### Sad paths
## Acceptance Criteria
## Data Contracts
## Migration / Existing State (only if schema changes)
## Dependencies
## Deferred
## Known Gaps (only if spec-reviewer blockers remain after 2 loops)
<!-- spec-review: verdict=<implementable|needs-revision|blocked> blockers=<n> -->
```

**Acceptance Criteria section format:** one criterion per line, each prefixed with its stable ID — `AC-1: …`, `AC-2: …` — negatives included and ID'd. Phrase EARS-lite as _guidance_, not a hard template: `WHEN <trigger> THEN <observable outcome>` for behavior, `… does NOT …` for negatives; plain observable-outcome phrasing is fine where EARS reads forced.

**Tracker-body invariant:** the `AC-n` block must land in the tracker ticket body **verbatim** — the GitHub issue body on the default adapter, or the JIRA description under `tracker.type: jira`. The ticket is the _only_ channel to the scope-completeness gate (its independence contract ignores everything but the self-fetched ticket). Tell the user this when emitting: paraphrasing the AC section during paste silently downgrades scope review to positional-fallback numbering. The `AC-n` IDs are load-bearing.

The marker is the final line **inside** the emitted block — below the last section and above the closing `---`, with the hand-off line outside it:

```
... ## Deferred / ## Known Gaps content ...

<!-- spec-review: verdict=implementable blockers=0 -->
---

> Ready to paste into GitHub, or hand to `intake-orchestrator` for decomposition analysis. Your call.
```

### Decision Ledger seed (after the issue block)

After the emitted issue block (outside the closing `---`), emit a **Decision Ledger seed** per the `interviewing-baseline` contract: every requirement-level decision the user made during the interview (`user-answered`), every "your call" (`user-delegated`), every TBD (`deferred`). Trivial interviews emit the explicit empty form. This block is a planning artifact, **NOT** part of the GitHub issue body — the engineer carries it into `plan-interview` (or saves it as `.claude/pipeline-state/{issue}-ledger.md` once an issue number exists).

End with:

> Ready to paste into GitHub, or hand to `intake-orchestrator` for decomposition analysis. The Decision Ledger seed above feeds `plan-interview` pre-flight. Your call.

## Escalation

Stop and present uncertainty to the user when:

- User input is contradictory and rechecking doesn't resolve it.
- Codebase reality contradicts what the user is reporting, and the conflict is material.
- The interview has run ~15 turns without converging on a draft.
- The item is clearly out of scope for a single issue (user described a 6-month initiative).

When escalating, tell the user: what you understood, what's blocking, what options you see, a clear question. Then stop.

## What NOT to do

- Don't ask more than 2 questions per turn.
- Don't write to GitHub or any external system — ever.
- Don't skip codebase corroboration on bug claims that name a specific code path.
- Don't rewrite the user's words — capture their intent, flag ambiguity for them to resolve.
- Don't decompose into sub-issues — that's `intake-orchestrator`'s job.
- Don't propose implementation plans — that's the planning stage.
- Don't re-interview items the user already answered in a prior turn of this session.
