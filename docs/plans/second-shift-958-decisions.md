# Intake record — #958

A new delivery source or concurrent writer around a write the store does not deduplicate. Pre-flight interview with the operator, 2026-10-09. The ticket body is the operator's own; rows citing it as `user-answered` are decisions the operator wrote there. No design handoff (a reviewer-prompt change, nothing rendered). Duplicate scan: rc 0.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Home of the rule | The lead pass only: a universal rule beside rule 4 in `plugins/review-toolkit/skills/review-lead/lead-pass-checklist.md`. It runs every round, both in the lane and standalone. No routing arm: the pipeline-reviewer row at `review-lead/SKILL.md:193` is unchanged, so nothing has to dedupe two holders | user-answered | intent |
| D-2 | Severity, and how it fits rule 4 | The finding is new (rule 4). It is a Warning by default and Critical only when cross-tenant or money/quota, even on the critical path. This is written as an explicit carve-out from rule 4's last sentence (`lead-pass-checklist.md:58-60`), so the two do not contradict | user-answered | intent |
| D-3 | Where the delivery model and the trigger vocabulary come from | A new active catalog row `Async processing \| all` in `plugins/review-toolkit/scripts/section-catalog.txt`, changed in lockstep with the `docs/extension-points.md` template (`check-review-context-sections-selftest.sh` enforces this). It carries the delivery model (at-least-once / at-most-once, retries) and the consumer's registration, enqueue and schedule vocabulary. The pointer at `pipeline-reviewer.md:14` names this section. The addition is breaking-class, so the release lists it under What-breaks | user-answered | intent |
| D-4 | A money retry whose idempotency contract lives in another repo | It stays Critical. The finding carries `unable to verify — pointer needed: <callee idempotency contract>` as the way to clear it | user-answered | intent |
| D-5 | Replay guard (ticket `## Guard`) | Dropped, as #950 D-2 dropped it. This departs from the ticket's Guard section on the operator's call | user-answered | intent |
| D-6 | Intake-side mirror (plan-interview, plan-reviewer, spec-reviewer, as #954 did) | Out of scope. It gets its own ticket if wanted | user-answered | intent |
| D-7 | Clearing the benign case | The rule's first step names the write pattern (the `pipeline-reviewer.md:79-84` list) and the at-most-once / uniqueness / balance invariant it threatens. A write with no invariant to name, such as an overwrite by primary key, is cleared by that named pattern, not by silence | user-answered | intent |
| D-8 | Report surface | An ordinary finding only, with no standing report section | user-answered | intent |
| D-9 | Trigger set | The diff adds or raises a retry wrapper or an attempts / delivery-semantics change, a new event or webhook handler that writes, a second consumer registration or enqueue / schedule site, or raised worker concurrency, around a write on an existing entity with no store-level enforcement in the cited schema. Also the kept arm: a new write inside an already-redelivered handler. Source: ticket items 1-2, the operator's 2026-10-09 decisions | user-answered | intent |
| D-10 | Escape list and what the finding names | A replay is a no-op only when deduplicated where the write commits: (1) the callee enforces an idempotency key; (2) a unique constraint or processed-ID table in the same transaction; (3) a conditional write or upsert keyed on the job/event id; (4) a Kafka produce inside the same exactly-once transaction. Producer- or broker-side dedup does not clear it. The finding names the delivery model and the Async processing section that declares it (ticket items 3, 5) | user-answered | intent |
| D-11 | pipeline-reviewer `What NOT to Flag` | At `pipeline-reviewer.md:123`, an attempts or delivery-semantics change triggers the `:75` idempotency check instead of being excluded (ticket item 6). Routing and the rest of the agent are unchanged | user-answered | intent |
| D-12 | How the finding passes Pre-Emit gate 2 | Through gate 2's branch "a concrete protection the diff ... fails to apply" (`lead-pass-checklist.md:83-85`) when Async processing declares at-least-once delivery. With no declared delivery model, the output is `unable to verify — pointer needed: delivery model` under the Grounding rule (`lead-pass-checklist.md:91-97`) | codebase-derived | fact |
| D-13 | Gate 3 for the kept arm | The defective write in the kept arm sits in the diff (rule 3, not rule 4), and gate 3's exemption (`lead-pass-checklist.md:86-89`) covers only a first consumer. Gate 3 gets a carve-out so that sibling handlers without commit-point dedup do not demote the kept arm, as D-2 and ticket item 4 require | codebase-derived | fact |
| D-14 | Re-downgrade at synthesis, which also repairs #951's shipped rule 4 | The Step 3 Pre-existing row and the dismissal rule (`review-lead/SKILL.md:430,433`) carry the rule-4 exception, including this class, so citing a sibling cannot downgrade the finding again. This lands in #958, and the PR's `Changelog:` trailer gives the #951 repair its own line (rule-4 findings are no longer re-downgraded at synthesis) | user-answered | intent |
| D-15 | Out-of-diff reads | The named-risk sentence (precedent: `lead-pass-checklist.md:23-25`) extends to the write's schema and its handler for this class. Opening them is the minimum grounding read, not proving a negative | codebase-derived | fact |
| D-16 | Replica / read-your-writes arm | Out of scope (ticket, Open for intake) | user-answered | intent |
| D-17 | Tests | No prose-presence selftest (ticket Guard; CLAUDE.md, the writing-tests rules). D-3's catalog/template lockstep is held by the existing `check-review-context-sections-selftest.sh` | codebase-derived | fact |
| D-18 | PR form | `feat(review-toolkit): ...` title, a `Changelog:` trailer, no version or CHANGELOG edits (CLAUDE.md) | codebase-derived | fact |
| D-19 | What "cross-tenant" means for D-2 | parked under OR-1 | deferred | open |

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | Definition of a cross-tenant duplicate write for D-2's Critical. Security rule 1's shape (a query that omits the tenant key) does not match it (F-11) | reversible-default-and-flag |

OR-1 default: the duplicated effect lands on a record or counter scoped to a tenant other than the one the delivery belongs to, or on one shared across tenants. BUILD writes this into the rule and names it in the PR body. Reversing it later is a one-sentence prompt edit, with no data or contract behind it.

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | The review report finding for this class: wording, severity, the clear-path pointer | decided (D-8) |
| S-2 | The consumer-authored `Async processing` section in the review-context template | decided (D-3) |
| S-3 | `check-review-context-sections.sh` output for a consumer heading `Async processing` (it was a novel-heading WARN before the catalog row) | decided (D-3) |
| S-4 | Release notes: What-breaks entry for the new catalog section | decided (D-3) |
| S-5 | pipeline-reviewer output on an attempts / delivery-semantics change | decided (D-11) |
| S-6 | Intake-side surfaces (plan-interview, plan-reviewer, spec-reviewer) | out-of-scope — the operator scoped the intake mirror out (D-6) |

## Checks

No ticket-specific checks — the configured lanes cover this change.

## Fan-out

Refuter: cross (opus/fable alternating)
Lenses: routing-reach opus 6/6 · trigger-precision fable 3/6 · gate-composition opus 5/6 · verification-path fable 3/6 · premortem fable 1/6
Tally: rows added 6 · snapshot claims overturned 1 · questions added 3
Checkouts: consumer backend not available — not identified in the ticket; the operator kept the run without it

| ID | Angle | Claim | Tag | Disposition |
| --- | --- | --- | --- | --- |
| F-1 | routing-reach | The pipeline-reviewer row (`SKILL.md:193`) is a file-path trigger; read literally it misses retry wrappers, webhook and event handlers, and registration modules | already-had | informed D-1 |
| F-2 | routing-reach | Even when spawned, pipeline-reviewer never asks about writer or delivery count; concurrency is read only as connection contention (`lead-pass-checklist.md:155`) | new | informed D-1 |
| F-3 | routing-reach | Lead-pass home runs every round, lane included, but does not load `review-context/pipeline-reviewer.md` | already-had | became D-1, D-3 |
| F-4 | routing-reach | A routing arm keeps only surface triggers under the pipeline default panel (db-reviewer precedent, `SKILL.md:219-221`) | already-had | informed D-1 (no arm built) |
| F-5 | routing-reach | The pipeline / async-processing section `pipeline-reviewer.md:14` points at is not in `section-catalog.txt` | already-had | became D-3 |
| F-6 | routing-reach | Two holders need a deferral rule like security's (`lead-pass-checklist.md:330-331`) | new | not material — moot under D-1's single holder |
| F-7 | trigger-precision | Raised concurrency on an overwrite-by-PK handler matches the trigger as worded yet is benign | new | became D-7 |
| F-8 | trigger-precision | Ticket items 3 and 4 collide on a money retry with a remote callee | new | became D-4 |
| F-9 | trigger-precision | Concurrency appears nowhere in pipeline-reviewer; item 6 alone leaves a concurrency raise unhomed | new | became D-9 |
| F-10 | gate-composition | A redelivery-only duplicate passes gate 2 only via "a protection the diff fails to apply", with at-least-once declared | new | became D-12 |
| F-11 | gate-composition | The operator's severity split uses a different axis from rule 4's critical-path Critical | overturned (snapshot: "D-5 severity split stands as written") | became D-2, OR-1 |
| F-12 | gate-composition | The kept arm is rule 3, not rule 4; gate 3 demotes it when siblings lack dedup | new | became D-13 |
| F-13 | gate-composition | Synthesis triage (`SKILL.md:430,433`) can re-downgrade a rule-4 finding by citing a sibling | new | became D-14 |
| F-14 | gate-composition | Lead pass, pipeline-reviewer and db-reviewer can emit the same defect at different severities | new | not material — single holder under D-1; residual handled by D-14 |
| F-15 | verification-path | #951 shipped without the replay the ticket's guard requires | new | became D-5 |
| F-16 | verification-path | The rule's home decides what reaches the lane and at which model | new | informed D-1 |
| F-17 | verification-path | The replay cannot be recorded in the lane: consumer identity rule, and `## Checks` runs every round | already-had | became D-5 |
| F-18 | premortem | Budget: pipeline-reviewer at sonnet / maxTurns 15 goes dark; the lead pass limits out-of-diff reads | already-had | became D-15 |

### Snapshot

    | ID | Decision | Resolution |
    | --- | --- | --- |
    | D-1 | Home of the rule | Both, mirroring #951: a lead-pass row beside rule 4 (runs in lane and standalone) plus a pipeline-reviewer routing arm at review-lead SKILL.md:193 and a check body in pipeline-reviewer.md |
    | D-2 | Does the new pipeline-reviewer routing arm fire under the pipeline default panel | Standalone-only, as db-reviewer's newly-read arm (SKILL.md ~219, #950 D-16); the lead-pass row covers the lane |
    | D-3 | Where the trigger vocabulary (registration decorators, enqueue/schedule verbs) and delivery model come from | Open: section-catalog.txt has no pipeline section although pipeline-reviewer.md:15 points at a "pipeline / async-processing section"; candidate: new `Pipeline stack` catalog row (breaking-class) vs prose under an existing section vs model judgment only |
    | D-4 | Replay guard: who runs it, when, where recorded | Open: the lane cannot reach a consumer checkout and must not name it; candidate operator-side before/after replay before merge, capped per probe-before-scale |
    | D-5 | Keep the redelivered-handler arm; severity Warning default, Critical cross-tenant or money/quota | Operator decisions in the ticket body, 2026-10-09 |
    | D-6 | pipeline-reviewer.md:123 exclusion | An attempts or delivery-semantics change triggers the idempotency check instead of being excluded (ticket item 6) |
    | D-7 | Callee in another repo | `unable to verify — pointer needed` (ticket item 3) |
    | D-8 | Intake-side mirror (plan-interview / plan-reviewer / spec-reviewer, as #954 did for #951) | Open: recommend out of scope |
    | D-9 | Always-emitted report section like Data provenance | Open: recommend finding-only, no new section |
    | D-10 | pipeline-reviewer maxTurns 15 vs added schema read | Open |
    | D-11 | Replica / read-your-writes arm | Out of scope (ticket) |
    | D-12 | PR form | feat title, Changelog trailer, no version/CHANGELOG edits (CLAUDE.md) |
