# Lead-pass checklist

The calibration content for the review dimensions `review-lead` reviews **in-session** rather than
dispatching: performance, maintainability, complexity, test coverage, and — on the rounds its
conditional did not fire — security. Read this before the pass; apply it dimension by dimension.

It is folded from the five agent contracts of the same names, which still ship and are still
dispatchable. Where a rule below is thinner than you need, the agent file is the long form.

## How to run the pass

**One read of the diff, then per-dimension sections.** Read `git diff origin/<base>...HEAD` once,
end to end, and hold it. Then walk the dimensions below in order, against that one read. Do not
re-read the diff per dimension; do not review a dimension by skimming for its keywords.

**Out-of-diff reads only against a named risk.** Open an unchanged file when a specific finding
you are forming has to cite it — the schema behind a claimed missing index, the sibling that
establishes the pattern you are about to call a deviation, the test file you are about to call
absent. Do not open files to prove a negative across the diff: that is what exhausts the pass, and
a fast honest "nothing here in this dimension" is a complete review of it. The depth per change
size is in the SKILL's Review Depth Routing table.

**Findings out are ordinary findings.** They go into Synthesis Step 1 with the subagents' and are
deduplicated, confidence-filtered and triaged identically. Being found in-session buys a finding
nothing.

## Universal rules (every dimension)

### Confidence, and what stays visible

Score every finding 0-100 — 90-100 certain, 80-89 high, 60-79 moderate, below 60 speculative.
**Report only ≥ 80** in the main report sections. Everything you considered and scored below 80
goes into the report's `## Suppressed` section as a one-line bullet (`file:line — Confidence: N —
description`), so what you filtered is visible rather than invisible. `[Pre-existing]` findings are
reported regardless of confidence, in the pre-existing section.

A populated Suppressed section with no Critical findings is a strong review, not a weak one: it
says the dimension was read and consciously cleared. Do not manufacture a Warning to prove the
pass happened.

### New vs pre-existing

For each finding, decide which it is before you decide its severity:

1. Does the same pattern exist in unchanged files — siblings in the same directory or module?
2. If the diff follows an existing imperfect pattern, label it `[Pre-existing]`. It informs
   triage; it never blocks.
3. If the diff introduces a pattern that exists nowhere else, it is **new**.

**A change that follows existing codebase patterns is CONSISTENT, not broken.**

### The two-condition Critical trigger

A finding is Critical only when **both** hold:

1. The diff **introduces** it — a new risk, regression, or rule violation, not an inherited one; and
2. It **would be worse if shipped as-is today** — a concrete failure, exploit, or breach you can
   describe, not a shape that becomes a problem under a hypothetical future change.

One condition without the other is a Warning at most. "The PR makes an existing weakness slightly
more visible" is neither.

### Pre-Emit Gate

Before emitting any Critical or Warning, answer three questions to yourself. A finding that fails
**any one** of them is dropped or demoted to Suppressed:

1. **Anchored?** Does it cite a specific file path AND a line, symbol, or snippet **from the
   diff** — not from imagined or hypothetical future code?
2. **Concrete today?** Can you describe a concrete failure that happens, or a concrete protection
   the diff removes or fails to apply, **as the code stands**? "If X ever happens" reasoning fails
   this gate.
3. **Distinct from the surrounding pattern?** If every sibling does the same thing, the diff doing
   it is consistent — `[Pre-existing]` at most, never a new Critical.

### Grounding

Before issuing a finding — or claiming a dimension is clean — open and cite the artifact that
defines the concept you are judging. Filenames, method names and `--stat` line counts are not
evidence. Behavioral claims need case enumeration: for `A && B`, name all four cases; bugs hide in
the single-true ones. If the canonical artifact cannot be opened, the output is a question
(`unable to verify — pointer needed: <file or fact>`), not a verdict.

### Extension surface

Repo calibration lives in `.claude/second-shift/review-context.md` (shared) plus
`.claude/second-shift/review-context/<reviewer-name>.md` per dimension. Load what is present; it
is **additive** and never weakens a rule below. A section that exists as a heading but is empty or
a TODO counts as **absent** — infer conservatively from the diff and say that you did. Never quote
an empty section back as an exemption.

---

## Performance

Stack-agnostic. Apply each rule in the vocabulary of the repo's actual stack (`## Stack`,
`## Performance budgets`), and never flag the absence of a mechanic the stack does not have.

**Critical**

- **N+1 access.** A per-item query/fetch inside a loop over a collection, where a single batched
  load (join, set lookup, batch API) would do. Any data-access layer.
- **Missing index.** A new field added to a filter, a sort, or a join/lookup that is not indexed
  in the schema, in whatever form the store expresses indexes.
- **Unbounded result sets.** A data-access call that can return a large collection with no
  limit/pagination on a user-facing path. Internal workers are exempt where review-context says so.
- **O(n²) on large arrays**, at any layer. Sliding-window aggregations must be O(n); a known
  complexity bound regressing to O(n²) when pruning logic changes is the same finding.

**Warning**

- Background-job / queue concerns, in the repo's own queue vocabulary: elevated worker concurrency
  contending on data-store connections; retained completed/failed jobs growing the broker
  unboundedly; jobs with no timeout that can block the queue; multi-stage pipelines re-reading
  large data between stages.
- Specialized-index queries that do not actually use the intended index; operations with no
  pre-filter (tenant/partition key) scanning the whole set; an operator that is not index-backed.
- Batchable or init-once work done per item or per request — expensive model/resource loading
  belongs at startup.
- Frontend/rendering, where the framework has the mechanic: data fetched at the wrong layer and
  re-fetched client-side; large payloads shipped across the server→client boundary for
  interactivity that does not need them; an interactivity boundary widened past the leaf that
  needs it; heavy client-only components not code-split; per-frame JS animation where a CSS
  transition suffices.
- Synchronous CPU-bound parsing on the request/event loop.

**Do NOT flag**

- Startup/initialization code that runs once.
- Test files — test performance is irrelevant.
- Code processing a single record.
- Small bounded collections (fixed-size domain enumerations).
- Internal algorithm detail that does not change algorithmic complexity.

---

## Maintainability

Stack-neutral, and the reader is as often an AI assistant as a human: intent must be parseable
without ambiguity. Apply in the repo's declared conventions (`## Convention-required structure`,
`## Naming & structure conventions`).

**Critical**

- **Naming that needs context to decode** — `res`, `flag`, `proc(r, cfg)`, `calc(d, p)`. Names
  convey intent, in the casing convention of their language, with the language's boolean and
  collection conventions honored.
- **Dead code** — commented-out code, unused imports, unreachable branches. It actively misleads.
- **Function signatures past ~3 parameters** where the language has an options object, dataclass,
  or struct.

**Warning**

- **Magic numbers** — domain thresholds must be named constants with the reason attached.
- **A second way to do the same thing** — new code diverging from the repo's prevailing pattern
  for its language: throwing where the codebase returns a not-found sentinel, an ad-hoc import
  order where one is declared, a raw container where a typed model exists, casual error-swallowing
  in a layer that handles errors deliberately. Judge against the surrounding code, never against a
  pattern imported from a different stack.
- **Non-obvious domain logic with no "why" comment.** Simple CRUD needs none.
- **Cross-language naming drift** — the same concept named differently per language, beyond
  casing.
- **Contract-coupled ordering** — a feature-vector or serialized-shape order that must match
  another artifact needs the dependency commented, and version strings updated with it.
- **Frontend**, where the framework has the mechanic: an unclear rendering-environment boundary;
  client types drifting from the backend contract they mirror; impure formatting/conversion
  utilities; styling that bypasses the repo's declared class-merge helper, variant mechanism, or
  design tokens.
- **Formatting/lint compliance** against the repo's *declared* formatter and linter — quote style,
  indent width, trailing commas, line length. Defer the tool names to review-context; do not
  assume a formatter the repo never declared.

**Do NOT flag**

- Missing docstrings on every function — only on non-obvious logic.
- Declarative framework boilerplate (schema definitions, DI/route decorators, typed model fields).
- Short names in tight scopes (`i` in a 3-line loop).
- Code that follows existing patterns you would personally have written differently.
- Documented architectural decisions.

---

## Complexity

The right amount of complexity is the minimum the current task needs; three similar lines beat a
premature abstraction. Never flag structure the repo's framework, runtime, or convention
*mandates* (`## Convention-required structure`, `## Intentional complexity`).

**Critical**

- **Premature abstraction** — a helper, wrapper, or abstract/interface layer for something used
  exactly once. The tell is indirection with no second caller and no concrete plan for one.
- **Configuration creep** — values that will never vary hidden behind a config lookup. Values that
  genuinely differ per environment (URLs, credentials, deployment paths) are not this.
- **Unnecessary patterns** — factory / strategy / observer / builder, or a trait/interface seam
  over a single concrete type, where a plain function or a `switch` suffices. A layer over an
  interface with two or more real implementations is usually right; further layers on top are not.

**Warning**

- A feature flag or compatibility shim for a change that should just be made.
- A wrapper function whose whole body forwards its arguments with no transformation, validation,
  or error handling.
- A generic/parameterized construct only ever instantiated with one concrete type.
- UI over-engineering, in the repo's UI stack: premature component splitting; wrapper components
  that only forward props to one primitive; one-shot custom hooks around a single piece of local
  state; ad-hoc primitives reinventing a design-system component; a shared-state provider for
  state two adjacent components could pass as props.

**Do NOT flag**

- Framework-required scaffolding — module/service/controller/DTO/model structure, validation
  decorators, serialization layers. That is the cost of the framework.
- Convention-required domain objects — request/response models, value objects, typed data classes.
- An interface with two or more real implementations.
- Architectural separation between workspace packages or services.
- Inherent domain complexity — multi-stage pipelines, layered domain models, and any seam the
  repo declares as an intentional exemption.
- One file per background-job type.

---

## Test coverage

**Check for test infrastructure first.** If the affected workspace has no test runner configured
and no existing tests, missing tests are `[Pre-existing]` — "workspace has no test infrastructure;
recommend a runner before requiring coverage" — never Critical. This is what stops the false
positive that fails every PR in a workspace with zero tests.

Then, for each changed source file, find its tests using the repo's convention (declared, or
inferred from where existing tests live) and read them.

**Critical**

- **New public behavior needs a covering test**: a happy path asserting the real result (not that
  it ran), the documented failure mode, and the edge cases the unit's domain demands. For
  foundational shared code the blast radius makes an untested change Critical on its own.
- **Deferred/background work needs both outcomes**: the successful path and the failure/edge cases
  its domain demands (empty input, absent optional data, retry/failure handling).
- **Correctness-bearing computation needs correctness and boundary tests**: a known-input fixture
  with an expected output plus any error bounds; degenerate cases (too few samples, empty or
  single-element input, uniform data that should yield nothing); and the fallback path when a
  required resource is unavailable.

**Warning**

- **Coverage that cannot fail** — a second axis, never a discount on the Critical intents above:
  assertions differing from a sibling's only by fixture; asserting static copy no branch selects
  between; a presence-only inventory with no interaction and no state change; asserting the
  absence of code that does not exist; asserting what a library did with what we passed rather
  than what we passed; re-testing a pure function through an expensive integration render; a
  **mirror harness** re-declaring production logic and asserting on the copy, which no production
  edit can ever fail. A raised per-file timeout in the diff is a symptom, not a fix.
- **Composed contracts** — when the diff changes a contract several components compose against,
  require it to name the affected paths and say how the end-to-end test was extended for each.
- Changed behavior (new branch, different return, added parameter) with no test update.
- Missing edge cases: empty or single-element input, zero/negative/out-of-range values, inputs
  producing no result, missing optional fields, and values exactly at a decision threshold.
- Test-quality issues: existence-only assertions, mocking the unit under test, no meaningful
  assertion, duplicate paths, copy-pasted variations where the framework offers a table form.
- Cross-boundary contract drift — a new field on one side of a service or language boundary that
  the other side neither sends nor exercises.
- **Silent-failure schema coupling** — where a producer and consumer must agree on the shape or
  *order* of a structure and a mismatch produces a wrong result rather than an error, the
  agreement must be tested. Skip entirely if the stack has no such coupling.

**Do NOT flag**

- Missing tests for declarative data shapes validated by a framework validator.
- Missing tests for wiring/module-definition files that only assemble dependencies.
- Missing tests for thin pass-through layers.
- Missing integration/e2e tests (a separate concern).
- Test files for unchanged code.
- Script-level smoke checks and "run this file directly" sanity checks.

---

## Security

**Run this section only when the security conditional did NOT fire.** When `security-reviewer` was
spawned, it owns the dimension and this section is skipped — running both manufactures duplicates.

**Diff-scope discipline.** Findings must be tied to code in the diff. Read siblings for pattern
context, but a concern that exists only in unchanged code is out of scope: a missing owner filter
on an untouched service, validation gaps on an untouched handler, guard coverage on an untouched
route.

**Maturity calibration.** If review-context declares a maturity stage (pre-auth, validation at the
API layer, no shared client), honor it. Where the repo uses a fenced `second-shift-claims` block,
do not honor a severity-downgrading claim past its `reverify-by` — treat it as absent and apply the
generic rules.

**Critical — these always, when introduced new**

1. **Tenant/owner isolation breach** on owner-scoped data: the tenant key is in scope at the call
   site (argument, decorator, request context) AND the query returning owned rows omits it. When
   the key is not in scope *at all* — a new surface in a codebase whose auth system does not yet
   exist — that is `[Pre-existing]`, a forward-compatibility note. When the **client** names the
   tenant key (path/query/body parameter), that is Critical regardless of pre-auth state.
2. **Injection** — a raw or interpolated query fragment carrying user-derived values, or string
   concatenation into a query body.
3. **Secret exposure** — tokens, API keys, OAuth secrets, JWT material, or connection strings
   written to a log, stdout, error message, or response body.
4. **Prototype pollution** — recursive merge or `Object.assign` over an unvalidated request body.
5. **Path traversal** — filesystem access whose path comes from a request parameter with no
   normalize-plus-containment check and no validator allowlist.
6. **CORS `origin: '*'` with `credentials: true`.** Routine CORS edits are not this; an actively
   introduced wildcard-plus-credentials is.
7. **Remote code execution** — `eval`, `Function()`, subprocess spawn with user-derived argv,
   deserialization of attacker-controlled bytes.
8. **Auth bypass on a user-facing endpoint** — including a verification call that accepts an
   unconstrained algorithm because no allowlist is set.

Also check, at Critical weight where the diff introduces the gap: external inputs bounded at a
trust boundary; upload type/extension allowlists and size bounds, signed URLs rather than exposed
credentials, and parsers that survive truncated input; response serialization that whitelists
fields rather than spreading a raw record.

**Warning** — a real defense-in-depth gap on a user-facing surface that is not directly
exploitable: a missing validation constraint on a typed parameter; a response field missing from
the whitelist; the sanitizer absent on a user-facing endpoint; an allowlist including a domain the
repo does not control.

**Suppressed** — real-but-low-confidence, or speculative/conformance-shaped: "if this token ever
lacks a subject claim"; auth-scheme case sensitivity; a missing per-response documentation string;
pattern-consistency drift on internal-only endpoints; pre-existing patterns reproduced
consistently.

**Do NOT flag**

- CSRF where the framework handles it globally.
- Centrally managed CORS configuration (the wildcard-plus-credentials case above excepted).
- Generic type safety — not security.
- Dependencies and supply chain — out of scope.
- Internal service-to-service calls on a trusted network.
- Header-parsing pedantry, request-object type augmentation, missing per-response doc strings.
- A missing response whitelist on an internal liveness/readiness probe returning a constant
  literal with no service or DB spread.
