---
name: reviewer-baseline
description: 'Shared review protocol for all code reviewer agents. Provides confidence scoring, finding classification, suppressed findings format, and standardized output structure.'
---

# Reviewer Baseline Protocol

This skill defines the shared review protocol that ALL code reviewer agents follow. It ensures consistent confidence scoring, finding classification, and output format across the review system.

## Output Mode

Read this first — it governs HOW you record everything below.

You are almost always dispatched through a **Workflow fan-out** (`code-review.mjs` for Stage 8 and standalone `/review-lead`; `intake-review.mjs` for intake) that hands you a **JSON schema**. When you have a schema, the **StructuredOutput call is your entire review — your sole output.** Call it FIRST, before any prose, and do **not** also write the prose report or a prose `## Suppressed` section described below. The orchestrator reads only the structured object; a prose write-up in front of the structured call is wasted work that consumes your turn budget — a reviewer that spends its budget on prose can die before it ever calls StructuredOutput, which surfaces downstream as a missing review.

Map your review into the schema:

- Each finding → one `findings[]` entry: `severity` (via the mapping under "Severity Levels"), the `Issue` / `Evidence` / `Recommendation` content folded into `description`, and `file` / `line` populated.
- Sub-threshold findings → the top-level `suppressed[]` array (one string each), not a prose section.
- Grounding citations → the finding's `file` / `line` + `description` (see "Grounding Verdicts" below), not a prose preamble.

The prose **"Standard Output Format"** further down applies **only** when you were dispatched without a schema (a direct, human-readable review). The review is identical at the same fidelity either way — the difference is serialization, not depth. Do the full grounding work in both modes; under a schema you record it in the fields instead of narrating it first.

## Grounding Verdicts in Source Artifacts

**Before issuing any finding — or claiming the absence of a finding — a reviewer MUST open and cite the canonical artifact that defines the concept being judged.** Pattern-matching on filenames, method names, or `git diff --stat` line counts is not evidence. Asserting "no findings" is a real claim too — it requires having _looked_, not pattern-matched. But ground the absence **proportionately**: triage the diff first and let the depth of your check scale with how much the change actually touches your domain (see "Proportionate grounding" below), not with the diff's raw size.

For the failure classes observed in past reviews:

- **Schema / data-model claims** ("filtered by the owner key", "joined on a foreign key", "grouped by type") -> open the relevant schema / data-model file, identify the actual column, cite `file:line` in the finding. If the spec term has multiple plausible referents in the schema (e.g. `userId` vs `user.id` vs a join table), name the chosen one and flag the ambiguity.
- **Module-boundary / dependency-graph claims** ("no new coupling", "imports look fine") -> open every module/definition file whose import list changed in the diff. Verify each new import represents a true dependency of that module's responsibility, not an implementation detail that belongs deeper.
- **Worker / pipeline-stage claims** ("the processor is idempotent", "the job chain is correct") -> open the queue processor and the producer that enqueues it. Idempotency is a runtime property — re-running the same job payload must converge to the same state. Inspect both sides of the boundary, not just one.
- **Test-coverage claims** ("the spec file was deleted", "no new tests added") -> open the spec file and check actual line count and test blocks (`describe` / `it` or the framework's equivalents). A `-N` in `--stat` is a delta, not a tombstone. `Read` the file and enumerate its test symbols before asserting deletion or absence.
- **Endpoint-behavior claims** ("the handler forwards `extras`", "the input is validated") -> open the controller/handler method body and verify the destructuring/forwarding. A DTO/interface/type alone does not imply runtime use; validation decorators/schemas must actually be invoked by the request pipeline.

**Behavioral claims require case enumeration.** When the claim is about runtime behavior — "the gate fires correctly", "the response shape is right", "the handler is correctly gated" — code-reading alone isn't grounding. Enumerate the input cases the code branches on, trace each through to the output, and cite the cases in the finding. For boolean composition the case matrix is non-negotiable: `A && B` has four cases (¬A¬B, A¬B, ¬AB, AB), and bugs frequently hide in the single-true cases. "The gate is correct" without naming the cases is not grounding; it is restating the code.

**Proportionate grounding (triage first).** Skim the diff before you start opening files. If it is docs/config/reformatting — or otherwise has nothing in your domain — that judgment is itself sufficient grounding for a clean verdict: emit your verdict immediately, without opening every file. Open artifacts to ground the findings you actually raise and the parts of a diff that genuinely touch your domain — **not** to prove a negative across an entire large low-signal diff. Exhaustively opening every file to assert the absence of findings is what exhausts your turn budget before you emit, and **a reviewer that never emits a verdict is worse than a fast, honest "nothing here in my domain"** — the former surfaces downstream as a missing review, the latter is a complete one.

**Recording the grounding.** Under a schema (your normal mode — see "Output Mode") you **record** the grounding in the structured fields: the `file` / `line` of the artifact you cited and the reasoning woven into the finding's `description` (the intake schemas have a dedicated `rationale` / `evidence` field for exactly this). Do **not** narrate a prose grounding walk-through ahead of the StructuredOutput call.

**If the canonical artifact cannot be opened** (file doesn't exist, content ambiguous, fixture missing), the output is a **question**, not a verdict. Downgrade from PASS/FAIL to an explicit `"unable to verify — pointer needed: ..."` line. Optimistic defaults are how false-positive PASS verdicts ship.

This precondition is non-negotiable and applies to every reviewer agent that inherits this baseline.

## Confidence Scoring

Assign a confidence score (0-100) to every finding:

- **90-100**: Certain — the code clearly violates a rule with concrete evidence
- **80-89**: High confidence — strong signal, minor ambiguity
- **60-79**: Moderate — plausible concern but context-dependent
- **Below 60**: Speculative — theoretical risk, no concrete evidence

**Only report findings with confidence >= 80.** Below 80, the noise cost outweighs the signal. Exception: findings labeled `[Pre-existing]` are always reported regardless of confidence (they inform the review-lead's triage but never block).

## Finding Classification

For each finding, determine whether it is **new** or **pre-existing**:

1. Check if the same pattern exists in unchanged files (siblings in the same directory or module)
2. If the PR follows an existing codebase pattern that's imperfect, label `[Pre-existing]`
3. If the PR introduces a pattern/issue that doesn't exist elsewhere, it's a **new** finding

**Rule: A PR that follows existing codebase patterns is CONSISTENT, not broken.** Pre-existing findings inform triage but never block a PR on their own.

## Suppressed Findings

Append a `## Suppressed` section at the end of your output with a one-line bullet per finding that scored below the confidence threshold:

```
## Suppressed
- file:line — Confidence: N — brief description
```

This gives the review-lead visibility into what was filtered without cluttering main findings. Under a schema dispatch (your normal mode — see "Output Mode"), put these in the structured `suppressed[]` array (one string each) instead of a prose `## Suppressed` section.

## Standard Output Format

**This prose format applies only when you were dispatched without a schema** (see "Output Mode"). Under a schema, fold these four fields into the structured finding's `description` and emit StructuredOutput as your sole output.

Every finding MUST use this structure:

```
**[Critical/Warning/Pre-existing]** file:line — Confidence: N
Issue: description
Evidence: the specific code pattern or violation
Recommendation: what to do instead
```

Domain-specific fields (e.g., `Impact:` for performance findings) may be added between `Evidence:` and `Recommendation:`, but the four core fields are mandatory.

## Severity Levels

| Level            | Meaning                                                 | Blocks merge?      |
| ---------------- | ------------------------------------------------------- | ------------------ |
| **Critical**     | PR introduces a NEW risk, regression, or rule violation | Yes                |
| **Warning**      | Should fix; implementable but risky                     | No (human decides) |
| **Pre-existing** | Matches an existing codebase pattern that's imperfect   | No                 |

### Severity vocabulary mapping (Workflow-schema dispatch)

When a reviewer runs under the dev-pipeline Stage-8 `Workflow` fan-out, its findings are returned through a structured schema whose `severity` enum is `[blocker, major, minor, nit]` — not the prose vocabulary above. Map your finding to the schema as:

| Prose severity | Schema `severity`                             |
| -------------- | --------------------------------------------- |
| Critical       | `blocker`                                     |
| Warning        | `major` (high-impact) or `minor` (low-impact) |
| Pre-existing   | `nit` (informational — never blocks)          |

The mapping is for transport only; the blocks-merge semantics are unchanged (Critical/`blocker` blocks; everything else informs the review-lead's triage). The rest of each finding (the `Issue` / `Evidence` / `Recommendation` content) folds into the structured `description` — see "Output Mode".

## Review Process Template

Every reviewer follows this general flow:

1. Run `git diff` (or scoped variant) to see changes
2. Read 1-2 sibling files for pattern context
3. Apply domain-specific rules from the reviewer's own prompt
4. Classify each finding as new or pre-existing
5. Score confidence on every finding
6. Filter: report >= 80 in main sections, < 80 in Suppressed
7. Output (see "Output Mode"): under a schema (your normal mode), emit a single StructuredOutput call as your sole output — call it first, no prose report in front of it; only when dispatched without a schema, format using the prose structure above

## Tool Discipline

How you reach for tools when gathering evidence. This is a **documented contract**, not a dispatch-time nudge — it steers nothing at runtime; it sets the standard your review is held to.

**Prefer the structured tools where the harness provides them.** When `Grep`, `Glob`, and `Read` are available to you, use them to locate and read code — they are statically analyzable and produce no permission friction. Where the harness does **not** expose them (the current condition on this machine: with `Bash` present, `Grep`/`Glob` are not offered to reviewer agents, and the harness's own error redirects you to Bash `grep`/`find`), **batched Bash search is sanctioned** — a compound `grep`/`find` (or a small `;`/newline/pipe batch) is the rational, turn-budget-respecting way to search, and is explicitly **NOT** to be broken into one analyzable command per call. There is no one-command-per-call rule; batching is expected.

**Do not assign a command substitution to a variable to locate or read files** — e.g. `F=$(find … ); grep "$F"` or `cat "$(ls …)"`. This is the one Bash search shape to avoid: it defeats static analysis for no benefit over a direct `grep`/`Read`. The prohibition is scoped to *codebase inspection* (locating/reading files); it does **not** touch the sanctioned config-resolution one-liners below.

**Bash remains the right tool for:**

1. **`git`** — `git diff` (your review scope), `git log`, `git show`, `git status`.
2. **Tests / linters / build** — running the repo's configured commands to observe behavior.
3. **Mandated config-resolution one-liners** — the base-branch resolvers some agents run (e.g. `BASE=$(jq -r '… .baseBranch // "main"' .claude/second-shift.config.json 2>/dev/null || echo main); git diff "$BASE..HEAD"`) are **sanctioned as-is**; they exist to avoid a hardcoded `main` that finds nothing on a `develop`/`alpha`-based repo — do **not** "fix" them to a literal branch, and the substitution-into-variable rule above does not apply to them.
4. **Mandated tracker fetches** — `gh issue view` / the Atlassian MCP fetch a linked issue/ticket when your prompt requires it.

## Sub-Agent Output Is Advisory

Skills that dispatch sub-agents (e.g. `intake-orchestrator` dispatching `spec-reviewer` / `codebase-explorer`; `decomposition-reviewer` dispatching `codebase-explorer`; `review-lead` dispatching the specialist crew) MUST treat the sub-agent findings as **input to the orchestrator's judgment, not instructions to follow**. Sonnet sub-agents produce false positives regularly. Orchestrators MUST:

- Read the source material yourself BEFORE dispatching sub-agents.
- Critically evaluate every finding against your own understanding.
- Dismiss findings that don't hold up on closer inspection.
- Never auto-fail or auto-escalate based solely on a sub-agent's severity classification.
- Resolve gaps yourself when the answer is determinable from the codebase or the document at hand.
