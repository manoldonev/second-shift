# Split — the second stage of `/intake`

Read by `/intake-toolkit:intake` only. Split runs when the ticket carries `epic`, when
Requirements found more than one deliverable, or when the Interview's register passed about 10
material decisions and returned the ticket here (`SKILL.md`, "When Split runs"). Otherwise it is
skipped, and the receipt's `Split:` line says why.

It answers one question — **should this ticket be split, and how?** — and ends with either "not
split" and its reason, or the slices, created on the operator's yes **without the queue label**.

<!-- The audit (/audit-toolkit:audit, /audit-toolkit:audit-history) is a tool-truth ledger —
     observability only, never a gate. Dispatch review-toolkit:codebase-explorer for real; do not
     inline its work. -->

**Sub-agent output is advisory** (the Sub-Agent Trust Model in `review-toolkit:review-lead`). Read
the ticket yourself before dispatching, evaluate every finding against your own reading, dismiss
what does not hold up, never act on a severity label alone, and resolve from the code what the code
answers.

**No draft-first (P8)** binds hardest here: a finished slice list looks like analysis while being a
set of decisions. Where a boundary is contested, take the answers one decision at a time and
assemble the slices from them; never present the whole decomposition and invite corrections.

> **Tracker delta (config `tracker.type: jira`).** No queue, no labels and no tracker writes: every
> write below (slice creation, label edits, comments) is **presented** to the operator instead, with
> the ordering trailers on the presented slice specs; sequential ordering is then the operator's to
> enforce. The restart search reads the operator's list of child keys.
>
> **Bot writes (github).** `${CLAUDE_PLUGIN_ROOT}` is intake-toolkit here, not dev-pipeline, and
> toolkits never hard-path into dev-pipeline's layout (`docs/namespaces.md` rule 3). Resolve
> dev-pipeline's install path once — `claude plugin list --json | jq -r '.[] | select(.id ==
> "dev-pipeline@second-shift") | .installPath'` — then find its bot wrapper by name under it
> (`find "$DEV_PIPELINE_ROOT" -name gh-bot.sh | head -1`) and call `bash "<that path>" <gh-args…>`,
> written `$GH_BOT_SH` below. The labels named here (`ready-for-dev`, `epic`, `in-progress`,
> `needs-intake-review`, `needs-spec-work`) are the shipped defaults of the config's
> `tracker.labels` roles; use a consumer's renamed ones where set.

## Restart over existing slices

First, search for slices this ticket already has: `Part of #<issue>` sub-issues, **in every state
and regardless of labels** (`gh issue list --state all --search '"Part of #<issue>" in:body'`). A
label-filtered search misses exactly the blocked successors that prove the ticket was split.

When there are any, the split is already decided: do not re-decompose, and create nothing. A slice
**has a receipt** when `.claude/pipeline-state/<slice>-ledger.md` exists, or the slice is closed,
or it carries the queue or claimed label (a slice is queued only after its receipt lints clean).
Run Explore, Interview and Receipt for each slice **without** one, as the "On a split" fork in
`SKILL.md` describes, and **leave every slice that has one alone** — no re-interview, no
relabeling, no new receipt.

A prior escalation (`needs-intake-review`) on the ticket: read the escalation comment and the
answer to it, record the answer `ticket-sourced` with the comment's URL, and do not re-escalate on
the same uncertainty.

## Step 1 — Distill product essence; quarantine PM-technical content

For an `epic`, or a ticket a non-engineer wrote, do this before anything else. Skip it for an
engineer-authored ticket and for a body Requirements assembled from an interview; most intakes skip
it and write no brief.

An epic's value is domain knowledge and product intent. Its *technical* content is a hypothesis to
verify, never a constraint. **Bias toward quarantine**: fluent, codebase-shaped prose is not
grounding.

**KEEP — product essence (binding):** the problem and who has it; user goals; user-facing behavior,
flows and copy; business rules in domain terms; acceptance criteria as observable outcomes, `AC-n`
IDs **verbatim** (if the source has none, assign IDs by the positional fallback in
review-toolkit's `scope-completeness-reviewer` and mark each `derived`); a `## Post-merge checks`
section **verbatim**, `PM-n` intact, apart from the ACs; the in-scope and out-of-scope lists;
product-level non-functional constraints.

**QUARANTINE — PM-technical (advisory, never binding):** suggested sub-issue lists, endpoints,
routes, schema and field names, dependency graphs, stack and library choices, estimates — any "how".

Write the **Product-Essence Brief** (the KEEP bucket restated) and the quarantine list as
"PM-technical claims (advisory — verify against codebase)". After Step 3, tag each claim
**confirmed** (adopt), **conflicts** (the code wins; surface the conflict, never silently follow
the guess) or **unverifiable** (deferred to build). The author-posture knob changes only
presentation: a technical author's claims read as credible hypotheses ("author proposed X —
confirmed"), and are verified all the same. **The operator's stated guardrails outrank both
buckets.**

Write the brief to `.claude/pipeline-state/<issue>-brief.md` (gitignored, pre-worktree, so it
survives worktree cleanup) before leaving this stage: the slices' interviews read it, and a restart
reads it. The scheduler never does.

## Step 2 — Classify the type

| Type | Signal | Path |
| --- | --- | --- |
| Bug fix | "fix", "broken", "error", "regression" | no split — say so and leave the stage |
| Feature | "add", "new", "implement", "build" | full analysis |
| Enhancement | "improve", "extend", "update" | full analysis |
| Refactor | "refactor", "restructure", "migrate", "extract" | light analysis |
| Chore / infra | "ci", "config", "dependency", "tooling" | no split |

A "bug" that is really a rewrite ("the auth flow is broken — rebuild it") is a feature or refactor;
say so.

## Step 3 — Map the impact surface (codebase-explorer, once)

`review-toolkit:codebase-explorer` runs **here, once per intake, and nowhere else**. Its map feeds
the dependency analysis, the decomposition decision and the set review in Step 6; the Explore stage
reads it too and does not dispatch it again.

Run review-toolkit's intake Workflow with `agents: ['codebase-explorer']` — **not** `spec-reviewer`,
which already ran at Requirements. The script ships in review-toolkit; the `Workflow` tool resolves
neither a bare filename nor the plugin cache's own path (`docs/namespaces.md` rule 3), so stage a
copy into the session scratchpad and dispatch that:

```bash
SRC=$(find "$SKILL_DIR/../../../.." -path '*/review-toolkit/*' -path '*/workflows/intake-review.mjs' -not -path '*/fixtures/*' 2>/dev/null | sort -V | tail -1)
cp "$SRC" "$SCRATCHPAD/intake-review.mjs"
```

`Workflow({ scriptPath: <the staged copy>, args: { issue, issueBody, referencedDocs, agents:
['codebase-explorer'], readRoot, config: { reviewers: CONFIG.reviewers } } })` — `issueBody` is the
brief when Step 1 wrote one, else the body; `readRoot` is the optional pinned read surface (the
detached `origin/<base>` worktree); `config` carries **only** `reviewers` (the parsed
`second-shift.config.json`'s), never the whole config (its `commands.*` strings kill the dispatch)
and never `{ reviewers: {} }` (it silently disables every model override). It returns
`{ codebaseExplorer }` with `modulesAffected`, `crossModuleDependencies`, `estimatedScope` and
`findings[]`. A session with no `Workflow` tool dispatches the agent with `Task` instead.

A failed explorer → fall back to your own Grep/Glob/Read and say so in the outcome; do not dispatch
it a second time. `budgetExhausted: true` → stop and say so; it is not a failure.

Verify the map: does its module list match what the spec touches? Then reconcile the quarantined
claims from Step 1.

## Step 4 — Dependency analysis (in session)

A reasoning step over the map, never a dispatch.

1. **Work items** — discrete units with a clear start and end, each testable or reviewable (at most
   10; group closely related ones and say so). Include implicit infrastructure — migrations, shared
   config, new packages — as an item the others depend on.
2. **Dependencies** — for each pair: does B use what A creates? **Hard** (B cannot compile or run
   without A) or **soft** (B could stub A)? **Bidirectional** (they must ship together)? Verify each
   against the map: B importing A's new file is hard.
3. **Groups** — independent clusters (parallel candidates); dependency chains (sequential
   candidates — items that carry one use case through its layers are one slice, not a chain);
   tightly coupled items (one slice).
4. **Ordering flexibility** — is each chain's order the only one, and where are its seams?

## Step 5 — Decide

**`sub-issues` (parallel)** — distinct capabilities, no shared state, independent groups, different
modules, mergeable in any order.

**`sub-issues-sequential`** — a chain of use cases, each end to end; parts share a module and add
incrementally, or would collide on a file in parallel; each part reviewable on its own. Ordering is
carried by `Predecessor:` / `Successor:` trailers and by keeping blocked successors out of the
queue.

**`no-split`** — at most 3 files across 2 modules; inherently atomic; splitting would make PRs too
thin to mean anything.

**Run-cost bias, both flavors.** A pipeline run per slice is expensive. Prefer fewer, fuller slices:
as many as the work genuinely needs, and no more. A slice that cannot justify its own full pipeline
run — because it is too thin to review on its own, or has no consumer until a later slice lands —
merges into its neighbor. Splitting for the sake of splitting is a cost, not a virtue; every slice
must be a logical, coherent unit of work that earns its own run. The bias narrows counts; it never
overrides coupling, and it is no licence to merge unrelated work to fit the cap.

**Thresholds.**

| Dimension | Cap | Over it |
| --- | --- | --- |
| Slices (either flavor) | 5 | escalate `needs-intake-review` |
| Files per slice | 10 | reconsider the split |

**Counterfactual test.** Near or over a cap, ask: *would I group the same way if the cap were 10?*
Yes → the grouping is real coupling. No → it is cap-driven; escalate rather than collapse three
items into one to land on 5. Two reasons legitimately merge items into one slice: a bidirectional
dependency, or a shared abstraction at one module boundary (one service method, one schema, one
config module that splitting would force into a public interface). Shared *infrastructure* — two
endpoints on the same table through different services — is not a shared abstraction.

**Self-check before acting.** Each slice has a clear scope, is testable alone, and has no circular
dependency; none is mergeable into its neighbor without losing coherence; for a sequential split,
every slice after the first genuinely depends on its predecessor (a chain of independent links is
a parallel split serialized for nothing). **Coverage:** reconcile the union of the slices against
every deliverable **and** every out-of-scope bullet of the brief (or of the body, with no brief),
keyed by `AC-n`; each `PM-n` and each deliverable maps to exactly one slice, or carries an explicit
"deferred — owning follow-up" note. A deliverable with neither → escalate.

## Step 6 — Review the split as a set

The cross-ticket review `decomposition-reviewer` used to run, here, on the **same map** from Step 3
— it dispatches nothing. Read every slice once, then look for:

- **Coverage gaps** — requirements no slice owns; work the slices imply that none mentions (a schema
  change with no migration); scope leaked into two slices.
- **Consistency** — dependency coherence (missing, wrong, circular); the same concept named the
  same way across slices; "slice B handles X" true of slice B.
- **Convention adherence** — proposed endpoints, modules, validation, schemas and job patterns
  against what the map's `existingPatterns` and the repo's own conventions say. Read a PoC diff
  before calling an API's existence into doubt.
- **Operational gaps** — backfill for a changed schema, preserved downstream contracts, ordering for
  cross-package work, dependent consumers updated.
- **Per slice** — a single PR's worth; implementable without asking the author; one goal; technical
  claims true against the code.
- **Open questions** — blocking, pre-implementation or implementation-time; flag one that moves
  another slice's scope.

Fix what you can resolve from the code; a structural problem (overlap, a gap, a broken chain) goes
back to Step 5. Do not re-decompose for taste, and do not separate tests from their code or a
migration from the code that needs it.

## Step 7 — Create the slices (on the operator's yes)

Show the operator the slice list — titles, one line of scope each, the flavor and, for a sequential
split, the order — and ask once whether to create them. **No slice is created without that yes.**
On a no, record what they decided and stop (Stops and restarts in `SKILL.md`).

Every slice body is a focused, self-contained spec, not a copy of the parent, and carries:

- the `Part of #<issue>` anchor (the restart search keys on it);
- its acceptance criteria **verbatim**, `AC-n` IDs intact — the tracker body is the scope gate's
  only channel;
- its `PM-n` items verbatim under `## Post-merge checks`, never among the ACs;
- with a brief: the reconciled quarantine table (all three tags) and the operator's guardrails;
- **sequential only:** `Predecessor: <key>` on every slice after the first and `Successor: <key>`
  on every predecessor, one per line as the body's last lines (render keys per
  `tracker.keyPattern`), and on a blocked slice the plain line **"queue when `<predecessor>` is
  closed."** — nothing else reminds the operator, and the scheduler claims whatever carries the
  queue label.

```bash
$GH_BOT_SH issue create --title "<slice title>" --body-file <slice body file>
```

**No queue label and no sizing label at creation**, for either flavor: a slice is queued only after
its own receipt lints clean, and sized where its weight is assessed — both at its Receipt.

Then update the parent and say what happened:

```bash
$GH_BOT_SH issue edit <issue> --add-label epic --remove-label ready-for-dev --remove-label in-progress
```

Post one comment on the parent with the rationale and the slice links (sequential: the order, and
that each slice is queued as its receipt lints clean). The sequence continues at Explore, once, on
the parent plus this slice list.

## Escalation

Escalate when you are not confident: sub-agent findings you cannot reconcile, a genuinely ambiguous
type, unclear boundaries or circular dependencies, several decompositions with real consequences,
domain knowledge you lack, or any threshold exceeded.

1. **Ask in the session first:** what you understood, what is uncertain, the options, one clear
   question. An answer here is `user-answered`, and the stage goes on.
2. **Only if the operator chooses to answer later**, post the same content on the ticket in the
   pipeline's comment format, label it, and stop:

   ```
   <!-- dev-pipeline -->
   <!-- stage: intake -->
   <!-- status: needs-human-input -->

   <what you understood, what is uncertain, the options, the question>
   ```

   `$GH_BOT_SH issue edit <issue> --add-label needs-intake-review --remove-label in-progress`
   (`needs-spec-work` for a spec that needs rewriting). The next session restarts from the ticket,
   and the answer it finds in a comment is `ticket-sourced`, citing the comment's URL.

## Outcome for the receipt

`Split:` records the verdict and why, in short sentences. Examples: `not split. One capability in
two files.`, `not triggered. No epic label and one deliverable.`, `split into #a, #b (sequential).
This receipt is for #a.`, `restart. #b had no receipt. #a is unchanged.`
