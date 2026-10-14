---
name: interviewing-baseline
description: Shared interviewing protocol for every interviewing surface (the /intake stages, plan-interview, grill-me). Provides the interview loop rules and the Decision Ledger contract — schema, provenance enum, explicit-empty form, and the intake receipt.
---

# Interviewing Baseline Protocol

This skill defines the shared protocol that ALL interviewing/elicitation skills follow, the same way `review-toolkit:reviewer-baseline` unifies the reviewer agents. It exists so loop rules and the Decision Ledger contract live in exactly one place.

**Canonical source notice:** this file is the single source of truth for the Decision Ledger schema, the provenance enum, and the intake-receipt contract below it (Kind axis, open regions, surface inventory, checks, design frames, fan-out, knowledge source, receipt versions, intake steps, departures). Every other site that restates them (`plan-interview/tools/ledger-lint.sh`, this plugin's `hooks/exitplan-ledger-gate.sh` via that lint, `review-toolkit:plan-reviewer`) carries a mirror marker and must be updated in lockstep when this section changes.

## Interview Loop Rules

Rules for every interviewing turn, regardless of which skill is running:

1. **Explore first.** If a question can be answered by reading the codebase, the repo's docs, or ADRs (Grep/Glob/Read, or the impact map `/intake`'s Split stage made when it ran), answer it yourself instead of asking. Asking the user a codebase-answerable question is a protocol violation.
2. **At most 2 questions per turn.** The user disengages otherwise. Related sub-choices may share one `AskUserQuestion` call, but the material decisions per turn stay ≤ 2.
3. **Attach a recommendation only when it's grounded** in the user's input, the codebase, or the repo's docs — cite the grounding. If nothing grounds an answer, ask plain — do not guess. (Reporter-owned facts — environment, frequency, business intent — are rarely groundable; design decisions almost always are.)
4. **Recommended answer goes first.** When using `AskUserQuestion`, the grounded recommendation is the first option, labeled `(Recommended)`.
5. **Never re-ask.** A question answered earlier in the session — or already resolved in the artifact under discussion — is settled. If the user declines to answer, record it (`TBD` in a ticket draft; `deferred` in a Decision Ledger) and move on.
6. **"Your call" is a valid answer.** When the user delegates a decision, record the recommendation as the resolution with provenance `user-delegated` — do not re-open it later.
7. **Disambiguate domain nouns before drafting.** A noun with >1 plausible schema referent (`git grep` over the repo's data-schema definitions, plus adjacent service interfaces) is forced to a choice by question — never picked by word-similarity.
8. **No draft-first (P8).** Never present a finished artifact ahead of the decisions it encodes. Nobody holds a complete picture of what they want until something concrete pushes back, and a full draft pushes back on everything at once: the human is reduced to correcting a fait accompli, and the decisions they would have made differently arrive as edits instead of choices. So: **the agent proposes per decision, the human disposes per decision**, and the artifact is *assembled from ledger rows* once they exist. A draft is legitimate as the residue of decided rows — never as the opening move, and never as a way to "give them something to react to."

   **Batch-blessing is the same violation wearing an interview's clothes**, and it is named here because it does not look like a draft: collapsing N open decisions into a table of agent-chosen defaults and asking for one blanket approval. It reads as a turn — there are options on the screen, the human answers — while being the exact inverse of one, because a single "looks fine" cannot distinguish the rows they actually considered from the rows they skimmed. It *manufactures* agreement instead of reaching it. Presenting many resolved rows for the record is fine; presenting many *unresolved* ones for one approval is not. If a batch is genuinely uncontroversial, that is a claim the rows are immaterial — drop them from the register (rule: don't pad it) rather than blessing them wholesale.

9. **Repeated clarification requests mean WIDEN, not narrow.** When the user pushes back on a question round — "you're one-shotting this", "that's not what I asked", a second request to clarify — the reading is that the register is wrong or too shallow, not that the user is tired of questions. The move is to slow down and widen the surface under discussion; shrinking the question set, or answering the pushback with a defaults table, is the failure this rule exists to name. Fatigue looks different: the user answers, briefly, and asks you to get on with it.

## The Decision Ledger

<!-- canonical: interviewing-baseline provenance enum — all mirrors keep verbatim -->

The machine-checkable residue every elicitation leaves behind. It is a mandated `## Decision Ledger` section in the implementation plan (or, for a pipeline ticket, in the intake receipt `/intake-toolkit:intake` writes to `.claude/pipeline-state/{issue}-ledger.md`):

```
| ID  | Decision | Resolution | Provenance |
| --- | -------- | ---------- | ---------- |
| D-1 | Uniqueness of document fingerprint per user | Partial unique index on (userId, fingerprint) | user-answered |
| D-2 | 404 vs 409 on duplicate import | 409 | user-delegated |
| D-3 | DTO validation library | class-validator (repo convention, CLAUDE.md) | codebase-derived |
| D-4 | Backfill order for historical records | deferred to next milestone (owner: reporter) | deferred |
| D-5 | Max import size | 50 MB, per the operator's comment https://github.com/acme/repo/issues/42#issuecomment-1234567 | ticket-sourced |
```

**Provenance closed enum** — exactly these five values:

- `user-answered` — the engineer made the call in the interview.
- `user-delegated` — the engineer said "your call"; the grounded recommendation is recorded as the resolution.
- `codebase-derived` — grounded in code, an ADR, the repo's CLAUDE.md, the Product-Essence Brief, or the consumer's knowledge source; the Resolution cites the source. In a receipt it states its evidence in one of three forms: ``run: `<command>` → <decisive output>`` for a fact you checked, `cited (convention|adr): <path:line>` for one no command can check, or `cited (kb): <kb-page>` for one adopted from the knowledge source's answer (see "Evidence" under "The intake receipt"). A row that records a choice rather than a fact is not `codebase-derived`: ask it.
- `deferred` — explicitly parked, with owner and when it must be resolved in the Resolution cell.
- `ticket-sourced` — the operator resolved it **in a ticket comment** and the run adopted that resolution. The Resolution cell MUST cite the comment by URL (`https://…`) — an uncited row is an assumption wearing a label, and the lint rejects it. This is the one user-provenance value an autonomous run may originate, precisely because the citation is independently verifiable without a local pre-flight artifact.

`assumed` is **not** a legal value. An assumption either gets asked, grounded, or deferred explicitly — the ledger makes a silent assumption a lint error instead of a style problem.

**Rules:**

- IDs are stable `D-1..n` and never reused after retirement (same discipline as `AC-n` IDs).
- Resolution is never empty.
- **Precedence when sources disagree:** a row hydrated from a pre-flight `.claude/pipeline-state/{issue}-ledger.md` wins over a ticket comment covering the same decision. Two comments that conflict, or one that is ambiguous, resolve to `deferred` naming the conflict in the Resolution cell — never to a `ticket-sourced` row that picks a side.
- **Explicit empty form** for trivial work — the section must still exist, containing exactly this line instead of a table:

  ```
  No material decisions — all choices codebase-derived.
  ```

## The intake receipt

The ledger above is what an interview leaves behind. The **receipt** is what INTAKE hands to
BUILD, and it carries one thing the in-plan ledger does not: a claim about *which* rows a human
actually settled. Run `ledger-lint.sh --receipt <path>` over it.

### The Kind axis

Provenance alone cannot express the bar a receipt needs. The failure mode is a row that resolves
intent while wearing a `codebase-derived` label, so any rule keyed on provenance is circular.
Receipt rows therefore carry a fifth `Kind` cell:

```
| ID  | Decision | Resolution | Provenance | Kind |
| --- | -------- | ---------- | ---------- | ---- |
| D-1 | 404 vs 409 on duplicate import | 409 | user-answered | intent |
| D-2 | DTO validation library | class-validator — run: `grep -rl "from 'class-validator'" src \| wc -l` → 41 | codebase-derived | fact |
| D-3 | Backfill ordering | parked under OR-1 (owner: reporter) | deferred | open |
```

| Kind | Legal provenance | Meaning |
| --- | --- | --- |
| `intent` | `user-answered`, `user-delegated` | the human resolved it |
| `fact` | `codebase-derived`, `ticket-sourced` | derived from code or a cited comment |
| `open` | `deferred` | parked, and mapped to a declared open region |

The provenance enum is unchanged — this adds an axis, it does not fork the vocabulary. The Kind
cell is receipt-only: an in-plan Decision Ledger stays four columns, and the lint enforces the
arity of whichever artifact it was pointed at.

**The bar:** an `intent` row backed by `codebase-derived`, `ticket-sourced`, or `deferred` names
no human decision, and the lint rejects it. That is how comprehension debt becomes countable rather
than sensed.

### Evidence

A `codebase-derived` row is what BUILD trusts as settled fact, so a receipt row says how it was
settled. A `file:line` alone is a pointer, not a check: line numbers drift, and reading code is
not running it. Write one of three forms in the Resolution cell, after the decided value:

- ``run: `<command>` → <decisive output>`` — you ran it at intake. Run whatever can be run: a grep
  count, `ls`, `git cat-file`, a tool's `--help`. The output is the part that decides the row, not
  the whole dump.
- `cited (convention|adr): <path:line>` — the fact cannot be executed: a convention the repo
  states, or a recorded architecture decision.
- `cited (kb): <kb-page>` — a fact adopted from the knowledge source's answer (the receipt's
  `## Knowledge source`), with the same standing as the Product-Essence Brief: a curated document.
  `<kb-page>` is copied from the `Sources:` list in that answer. Only a fact the code does not
  contradict is adopted this way (see "Knowledge source" below).

```
| D-2 | DTO validation library | class-validator — run: `grep -rl "from 'class-validator'" src \| wc -l` → 41 | codebase-derived | fact |
| D-4 | Soft-delete semantics | a deletedAt timestamp, never a hard delete — cited (adr): docs/adr/0007-soft-delete.md:12 | codebase-derived | fact |
| D-5 | Audit rows on import | retained, never purged — cited (kb): <kb-page> | codebase-derived | fact |
```

`run:` and `cited` take any case, the arrow is `→` or `->`, and a command holding its own
backticks goes in a double-backtick span (``` run: ``grep -c "`" README.md`` → 3 ```). A `|` in
the command or the output is escaped as `\|`, or it splits the row.

There is no fourth reason. A row that records a *choice* rather than a fact — a default the code
does not fix, the name of a new thing — is not `codebase-derived`: ask it, and record the answer as
`user-answered` or `user-delegated`. A row that mixes the two gives `run:` evidence for the fact
behind its choice.

`ledger-lint.sh --receipt` refuses a `codebase-derived` row with none of the forms, a `run:` with
an empty command or output, and a `cited` with no reason, a reason outside `convention`, `adr` and
`kb`, or no source after the colon. It checks the form only, never that the page exists. The
in-plan ledger is not linted for it.

### Open Regions

A receipt that declares nothing open is claiming it knows everything that matters. Make the
claim explicit: a mandated `## Open Regions` section, rows or the empty form.

```
| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | Ordering guarantees for the historical backfill | pause-and-ask |
| OR-2 | Retention window for import audit rows | reversible-default-and-flag |
```

Disposition is a closed two-value enum. `pause-and-ask` stops BUILD and routes the decision
back; `reversible-default-and-flag` takes a stated default and surfaces it — legitimate only
where reversing it later is cheap, and the receipt says why in prose below the table. Every
`open`-kind ledger row cites the `OR-n` it falls under; a citation the section does not declare
is worse than none, because it reads as an owned gap everywhere downstream.

Zero open regions is legal to the lint and a **finding** to `spec-reviewer` on non-trivial
scope — over-claimed completeness is a judgment about scope size, not something a script can
decide.

Explicit empty form, for genuinely trivial scope:

```
No open regions — every decision in scope is ratified.
```

**Put an `OR-n` on every region**, with its disposition token in the row. The scheduler does not
read this section; the build and review sessions do, from the record, and a region with no id or
a disposition stated in prose ("default **no**, flagged") is one neither can cite.

### The Surface Inventory

Open Regions makes the *known* gaps explicit. The inventory is for the other kind: the
surface nobody thought to ask about. A ledger's exit criterion — "the register is empty" —
grades the interview against a register the interview itself chose, so an interview that
never raised the empty state exits satisfied, with a clean lint. The inventory is the
independent axis, a mandated `## Surface Inventory` section on the receipt:

```
| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | First paint while the list is still loading | decided (D-1) |
| S-2 | Empty state when the user has imported nothing | decided (D-2) |
| S-3 | Print stylesheet for the report | out-of-scope — nothing here is printed |
```

Enumerate every screen, route, state and artifact a user or operator ends up looking at —
loading, empty, partial, error, not-found, first paint, the copy on each. Disposition is a
closed two-value enum: `decided` **must cite the `D-n` that decides it** (an uncited claim
that a decision exists is the inventory's version of a silent assumption), and
`out-of-scope` **must carry the reason**. A listed surface that is neither is the gap this
section exists to count.

What it buys is bounded and worth stating: it cannot tell you the enumeration was complete.
It turns a surface nobody thought about into a surface nobody *listed* — which a reader and
a script can both see, where the absence of a question is visible to neither.

Explicit empty form, for work with no user-visible surface at all (a lint, a CI change):

```
No user-visible surface — this change renders nothing a user reads.
```

### Checks

The scheduler runs the config's `commands.*` against the pushed head, plus the commands in the
receipt's mandated `## Checks` section — read from the record's **first** commit, never the head,
so a build cannot edit its own bar. One command per line, at the start of the line:

```
## Checks

- `bash plugins/intake-toolkit/skills/plan-interview/tools/ledger-lint-selftest.sh`
- yarn test --filter import
```

`- cmd` and `` - `cmd` `` are the two forms the scheduler reads. A bullet it cannot read as one
command — inner backticks, an indent, a `*` bullet — is dropped there without a word, so the lint
refuses it; it refuses a line the scheduler *would* run that is not that form (`---`, `-cmd`) as
well. An absent section is a silent claim that nothing beyond the configured lanes verifies
this change; make the claim explicitly instead:

```
No ticket-specific checks — the configured lanes cover this change.
```

### Design frames

On a repo whose config sets `design.provider`, the receipt carries a `## Design frames` section
(`## Design` is read the same way): one row per screen and state the ticket renders, taken from
the design handoff. The scheduler's route smoke renders each row's route in its state and
asserts the `must-show` value is on the screen — it is the record's **only** per-row assertion, so
it is chosen here, at intake: a data-test id or a copy string taken from the frame.

```
| RS | route | state | frame | must-show |
| --- | --- | --- | --- | --- |
| RS-1 | /imports | empty | 815:2201 | Nothing imported yet |
| RS-2 | /imports | loaded | 815:2240 | data-test=import-row |
```

Every cell is filled, and no cell carries a pipe, escaped or not — the scheduler splits the row on
every `|`. A ticket on a provider repo that renders nothing disarms instead, with its
reason — a disarm is a decision, and an undocumented one is indistinguishable from an omission:

```
Design: none — <reason>
```

Neither form on a provider repo, and the scheduler refuses the run (`env-design-undeclared`). The
lint reads the same config the scheduler does (`SECOND_SHIFT_CONFIG`, else
`<repo>/.claude/second-shift.config.json`). Without `design.provider` the section is optional, but
any `RS-n` row that is there is still checked: the smoke reads rows wherever they are.

**Headings, both sections:** the scheduler's rule — the exact title at any depth, any case; any
heading closes the section; the first such section decides. `## Checks to add later` is not the
section.

### Fan-out

The intake fan-out (`review-toolkit/workflows/intake-fanout.mjs`, run by `/intake`'s Explore
stage) hands the interviewer a pool of evidence items, each one kept only after a refuter
from the model family that did not make it failed to break it. The receipt's mandated `## Fan-out`
section shows what that pool achieved **over plain intake**, ticket by ticket, and which lens
produced it. It has four parts:

- **Tag every item against the snapshot.** Before reading the pool, the interviewer writes down
  its own explore-first register. That snapshot is what plain intake would have gone in with.
  Each pool item then gets one tag:
  - `new`: the snapshot lacked it;
  - `already-had`;
  - `overturned (<the snapshot claim>)`: it contradicted something the snapshot asserted;
  - `not material`: it does not pass the materiality bar.

  Its `Angle` cell names the lens that produced it, and its disposition cell says what became of
  it: the `D-n` it became, or why it did not.
- **Head the section with a tally,** the refuter family, and one `Lenses:` line giving every lens
  the run dispatched — its key, the model it ran on, and claims kept of claims made (or `failed`).
  A lens that produced nothing still appears there, so a seat that never moves an outcome shows up
  in the record:

  ```
  ## Fan-out

  Refuter: cross (opus/fable alternating)
  Lenses: retry-semantics opus 2/5 · storage-limits fable 1/4 · auth-scope opus 0/3 · audit-trail fable 0/2 · premortem fable 1/6
  Tally: rows added 1 · snapshot claims overturned 1 · questions added 1

  | ID | Angle | Claim | Tag | Disposition |
  | --- | --- | --- | --- | --- |
  | F-1 | retry-semantics | The import job retries a 409 without a limit (`jobs/import.ts:88`) | new | became D-1 |
  | F-2 | storage-limits | Uploads over 20 MB are cut at the proxy (`deploy/proxy.conf:12`) | overturned (snapshot: "no size limit applies") | became D-3 |
  | F-3 | premortem | The export list sorts client-side | not material | not material — capped at 50 rows |

  ### Snapshot

      | ID | Decision | Resolution |
      | --- | --- | --- |
      | D-1 | Import retry policy | retry until success |
  ```

- **Embed the snapshot verbatim, indented four spaces,** under `### Snapshot`. Indentation keeps
  it a code block: its rows are a register too, and unindented they would read as this receipt's
  own ledger, regions and surfaces.

A pool where nothing survived refutation states `Pool: empty — no claim survived refutation.` in
place of the rows; the tally, lenses line and snapshot stay. On a split the fan-out runs once for
the parent and its slices: each slice's receipt lists only the items that touch it, names the
shared run on a `Run:` line, and embeds the shared snapshot.

A receipt that ran no fan-out carries exactly one line instead of the section's parts:

```
Fan-out: skipped — by the operator <where, and why>
Fan-out: failed — <what failed>
```

Only the operator skips the fan-out: the skip names them, `by the operator` (any case, followed by
anything that is not a letter or digit — `by the operator;` and `by the operator's` both read so).
A skip in any other name is a stage or a session deciding on its own that the evidence was not
worth gathering, and the lint refuses it under its own violation.

An absent section reads exactly like a fan-out nobody ran and nobody recorded, so the lint
(`ledger-lint.sh --receipt`) refuses it, along with a skip or failure that names no reason, a skip
that does not name the operator, a missing `Lenses:` line, a row with no angle, a tag outside the four, an `overturned` that names no
claim, a disposition citing an undeclared `D-n`, and unindented snapshot rows. The section's
reader is the operator's consumer read: a later reversal of a decision the fan-out flagged, or of
one it never raised, is how its value is judged, and the angle and lens counts are how a lens that
never contributes is found.

### Knowledge source

A consumer may declare a knowledge provider in `.claude/second-shift/intake-context.md`: an agent
of its own that answers from its knowledge base, lists the pages it read under `Sources:` and
reports what the base does not say. `/intake` dispatches it once per intake, as Requirements'
last act (the `intake` skill owns where), and the receipt's mandated `## Knowledge source` section
records what came back. It carries exactly one of three forms:

```
## Knowledge source

Provider: <plugin>:<provider-agent>

    <the provider's whole answer, every line indented four spaces>

    Sources:
    - <kb-page>
```

```
Knowledge source: none declared
Knowledge source: failed — <the first line of the error, or what is malformed in the declaration>
```

- **The answer is opaque and whole.** `Provider:` names who answered; under it the answer goes in
  verbatim, indented four spaces, as the Fan-out snapshot is. Indented, its own headings, table
  rows and `Receipt:` lines are a code block that no reader of the record takes for this
  receipt's — unindented, a heading in it would end the section, and a `| D-n |` row in it would
  be read as a ledger row. `Sources:` is not required: the answer is the provider's, not a shape
  the lint imposes.
- **`none declared`** — the repo has no `intake-context.md`, or it has no `## Knowledge source`
  section. That is how a consumer opts out; there is no skip form.
- **`failed`** — the dispatch errored (the agent is not installed, disabled, or it failed): the
  section records only the **first line** of the tool's error, because an unresolved agent type's
  error goes on to list every installed agent, and that inventory does not belong in a committed
  record. A declared section that is malformed (no `Provider:` line, or two) is not dispatched and
  records what is malformed. Intake continues either way, and never reads the knowledge base's
  files itself as a workaround.

**Context, not law.** The section is evidence for the interview: only `D-n` rows bind the build.
A fact intake adopts from the answer becomes a `codebase-derived` row citing `cited (kb):
<kb-page>` ("Evidence" above). **An answer that contradicts the code is asked, never picked
silently**: the fact's row is `user-answered` — or `deferred` under a `pause-and-ask` region — and
never `codebase-derived` citing `kb`. The row says which side this ticket follows (a `deferred` row
says the question is parked) and carries a fixed marker naming the page and which side is behind:

- `kb-conflict: <kb-page> (kb stale)` — the page is out of date; the code is right;
- `kb-conflict: <kb-page> (kb ahead)` — the page states a direction the code has not reached.

```
| D-6 | Audit-row retention | 90 days, as the code does; the page is out of date — kb-conflict: <kb-page> (kb stale) | user-answered | intent |
```

`ledger-lint.sh --receipt` refuses an absent section from v3, an empty one, a line that is
neither one of the forms nor indented four spaces, a `Knowledge source:` line outside the two
forms, a `Provider:` that is not a namespaced `<plugin>:<agent>`, two `Provider:` lines, a
provider with no answer, and two forms in one section. On a split, each slice receipt carries the
whole answer the parent's dispatch got.

### Receipt versions

A receipt names its version once, on a line of its own before its first `##` heading:

```
# Intake receipt — #1039 <title>

Receipt: v4

## Intake steps
```

A receipt with no such line is v1. Each mandated section starts at a version, and the lint
mandates it only on a receipt at or above that version, so a section added later bumps the
version instead of failing every receipt written before it:

<!-- LOCKSTEP-BEGIN receipt-versions -->
| Section | Mandated from |
| --- | --- |
| Open Regions | v1 |
| Surface Inventory | v1 |
| Checks | v1 |
| Fan-out | v1 |
| Intake steps | v2 |
| Knowledge source | v3 |
| Test intent | v4 |
<!-- LOCKSTEP-END receipt-versions -->

The lint (`ledger-lint.sh`) holds the same table and is what enforces it. It refuses two
`Receipt:` lines, one inside a section, one not of the form `Receipt: v<N>`, and a version above
the highest it knows; `ledger-lint.sh --receipt-version` prints that version. The scheduler
lints a receipt before it claims the ticket, with the intake-toolkit the repo has enabled, and
refuses (`env-receipt-lint-unavailable`) when that lint knows fewer versions than the receipt.
Write the highest version, so every section it mandates is there.

A receipt also uses each section title once: every reader takes the first copy of a title, so a
second one is never read, and the lint refuses it.

### Intake steps

From v2 the receipt records what each intake step did, one line per step, in this order:

```
## Intake steps

Requirements: the ticket body as written — spec-reviewer: implementable
Split: not split — one PR's worth of work
Explore: done — the worker, its DTOs and the proxy config
Fan-out: ran — 4 items, see Fan-out
Dup-scan: no candidates at or above threshold 12
Post-merge scan: no post-merge AC
Sizing: opus
```

Each key appears exactly once, spelled as above (`Dup-scan`, not "Duplicate scan"), at the start
of its line: no bullet, no indent. Its outcome is what the step did, or why it did not run, never
empty and never a bare dash. No sub-heading inside the section: any heading ends it for every
reader. `Sizing:` records the weight intake decided; applying the label is a tracker write made
after the receipt lints clean, not a step of its own.

### Test intent

From v4 the receipt fixes, per acceptance criterion, the behavior its test must prove, so the
build plans a test for every AC before its code:

```
## Test intent

ACs: AC-1 AC-2 AC-3 AC-8

AC-1: a second import of one document answers 409 and writes no row
AC-2: an upload above 50 MB is refused before the worker runs
AC-3: exempt — the README's import section is prose; no test can prove it
AC-4: holds — an import under 50 MB still lands in one row
AC-5: unchecked — the black-box API tier needs the running app and live upstreams
AC-8: run.sh's checks phase runs the coverage check (a run-selftest case)
```

- **`ACs:` is the id set**, transcribed from the ticket's AC block exactly as labeled: holes stay
  holes (a slice keeps its parent's ids), and a `PM-n` item is never in it. A ticket with no AC
  block is `ACs: none — <reason>`. The harness never reads the ticket body; this line is what it
  holds the plan to.
- **One line per id**, at the start of the line, in one of four forms: the observable behavior;
  `exempt — <reason>` (no test can prove it); `holds — <the existing behavior its test keeps>`
  (an AC like "X still works": its test passes without the change, so the scheduler keeps its
  files off the fails-without-the-change check and the checks at the head prove it); or
  `unchecked — <tier and reason>` (its test sits on a tier the scheduler cannot run, such as a
  black-box API suite that needs the running app: its files are noted, not run). An exempt,
  holds or unchecked line is the operator's answer to a question, recorded as a `user-answered`
  row; a holds or unchecked AC must still be tagged on a test task.

`ledger-lint.sh --receipt` refuses an absent section from v4, an id on `ACs:` with no line, a
line for an id `ACs:` does not list, an exempt, holds or unchecked line with no reason, and any
other line. It is offline: an id dropped from `ACs:` is invisible to it. The scheduler reads the
section from the record's first commit and runs `plan-coverage.sh` (dev-pipeline) on the build's
plan at the head: every AC not exempt must be tagged on a test task that names its test files,
and no tag may name an id `ACs:` does not list. Where the config maps test runners
(`commands.<id>.testRunners`), it then applies the head's tagged test files onto the record
commit's tree and runs each: every file of a behavior AC must fail there. The holds and
unchecked forms are additive inside v4: no receipt version names them.

### Departures

A decision the receipt never covered will sometimes surface during BUILD. That is normal
operation (P9), not a failure — what must not happen is the run quietly making the call. The
record is the one place it is written: BUILD edits the row in place (a gap it covers nowhere gets
a new row) — new resolution, the provenance naming who decided, a one-line reason — and commits
the edit with the code. The review diffs the record at its first commit against the head and
scores every edited row `departed`, naming the decider from its provenance; a row the code leaves
without an edit is `honored` or `violated`.

A declared `pause-and-ask` region is a question for the human, so only `user-answered` clears it —
a `user-delegated` call has not asked the question the region exists to ask.

## Who emits what

Each interviewing surface keeps its own purpose; what unifies them is the ledger:

| Surface | Elicits | Ledger role |
| --- | --- | --- |
| `/intake` Requirements stage | requirements from a reporter; the one spec-reviewer pass; the knowledge source's answer | requirement-level rows, held in memory for the Interview; the answer, for the receipt's `## Knowledge source` |
| `/intake` Split stage | escalation-point choices on a decomposition | in the session → `user-answered`; in a ticket comment → `ticket-sourced`; open → `deferred` |
| `/intake` Interview stage | the engineer's load-bearing design decisions | primary author of the receipt's ledger |
| `/intake` Receipt stage | post-merge checks, duplicates, probe guess-points | the only writer of the receipt |
| `plan-interview` | the engineer's design decisions for a plan | the in-plan ledger; never a receipt |
| `grill-me` | challenges to an existing plan/design | resolutions recorded back into the ledger as `user-answered` |
| `design-toolkit:design-faithful-spec` | ambiguous states/transitions in a handoff (`/intake`'s Requirements on a handoff input) | Open Questions double as `deferred` rows |

The order of the `/intake` stages lives in the `intake` skill; do not restate it here.

## What all interviewers must avoid

- Leading with a finished draft, or with a decision set the human has not disposed of one at a time — including a table of agent-chosen defaults put up for one blanket approval.
- Reading repeated pushback as fatigue and narrowing in response.
- Quizzing the engineer — questions elicit decisions; they never test comprehension.
- Asking codebase-answerable questions.
- Ungrounded recommendations dressed as grounded ones.
- Re-litigating a decision the user already made (in this session or in the ledger).
