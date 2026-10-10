# Intake receipt — #960

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Home of the in-flight / mixed-version rule | The lead pass: a new universal rule in `plugins/review-toolkit/skills/review-lead/lead-pass-checklist.md`, beside Data provenance. A queue or store field the diff renames, removes or retypes joins the mandatory "named risk" list (`lead-pass-checklist.md:23`), so the pass opens the unchanged reader, including a tolerant reader outside the hunk. pipeline-reviewer was rejected because it spawns only on worker/queue paths (`SKILL.md:193`) and misses DTO-only, client and store shapes. A split across pipeline-reviewer and db-reviewer was rejected for the same routing gaps plus two copies of one rule | user-answered | intent |
| D-2 | Boundary scope | Queue payloads, plus persisted fields under Data provenance's definition (an entity whose schema, model, DDL or mapping lives in the repo under review). The ticket's "declared-client" arm is dropped: nothing in the plugins or docs defines it, and a review-context section for it would be breaking-class. Service-boundary APIs and frontend retypes are out | user-answered | intent |
| D-3 | Overlap with pipeline-reviewer's Critical "renamed or removed field a downstream worker reads" (`pipeline-reviewer.md:53`) | Narrow `:53` to a reader that is not updated in the same diff (Critical: the contract is broken today). A reader that is updated while base-shape items are still in flight is only the new lead-pass Warning. One severity per case | user-answered | intent |
| D-4 | Reverse direction (the base-branch reader meets what the new code writes) | In, as a Warning, framed as the rolling-deploy window (old instances still running), not as a hypothetical rollback, so it passes the Pre-Emit Gate's "concrete today" test (`lead-pass-checklist.md:83-85`). It fires only when the reviewer cites the base reader's intolerance at file:line: a throw, a strict validator, a switch with no default, or a required-field dereference. No citation, no finding | user-answered | intent |
| D-5 | Two-step column-drop row at `db-reviewer.md:99` | No new row. The lead-pass rule (D-1, D-4) covers the store reverse direction on every round, and a second copy would be a dual declaration. Pointer correction: #951's rule is the Consumed-field persistence check at `db-reviewer.md:52-62`, not `:100` | user-answered | intent |
| D-6 | Compatibility-shim exemption | At both `complexity-reviewer.md:51` and `lead-pass-checklist.md:244`: a compatibility shim for a queue/store boundary field is not flagged when the PR or the code names its removal step (the contract half of expand/contract). A shim with no named removal step is still flagged. "Intentional complexity" does not reach this row: it attaches only to the Critical planned-swap rule (`complexity-reviewer.md:43`) | user-answered | intent |
| D-7 | Guard ("replay on the parent of the consumer case") | Dropped, per the #950 D-2 precedent. No replay and no eval; later consumer reviews judge the rule | user-answered | intent |
| D-8 | Report output | Ordinary Warning findings that cite the field, the boundary, and the reader (or the base reader's intolerance) at file:line. No new report section | user-answered | intent |
| D-9 | Severity of the new rule, and no new review-context section | Warning only. No `## Deploy topology` section, since it is breaking-class and no consumer declares one. Both are stated in the issue body by the operator: https://github.com/manoldonev/second-shift/issues/960 | ticket-sourced | fact |

## Open Regions

No open regions — every decision in scope is ratified.

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | Review report: the new in-flight / rollout Warning finding from the lead pass | decided (D-1) |
| S-2 | Review report: the reverse-direction Warning and its intolerance citation | decided (D-4) |
| S-3 | Review report: pipeline-reviewer's Critical on a coordinated rename (no longer fires when the reader is updated) | decided (D-3) |
| S-4 | Review report: complexity Warning on a boundary-field shim with a named removal step (suppressed) | decided (D-6) |
| S-5 | Report shape: no new section; findings only | decided (D-8) |
| S-6 | db-reviewer output | decided (D-5) |
| S-7 | plan-reviewer Step Ordering Risks (`plan-reviewer.md:166-174`) | out-of-scope — plan-time check; the ticket targets diff review, and D-1 places the rule there |
| S-8 | review-context template / `section-catalog.txt` | out-of-scope — no new section (D-9) |

## Checks

No ticket-specific checks — the configured lanes cover this change.

## Fan-out

Refuter: cross (opus/fable alternating)
Lenses: routing-reach opus 5/6 · seam-overlap fable 4/6 · precision-and-guard opus 5/6 · in-flight-semantics fable 2/6 · premortem fable 2/6
Tally: rows added 1 · snapshot claims overturned 0 · questions added 1
Checkouts: consumer backend not available

| ID | Angle | Claim | Tag | Disposition |
| --- | --- | --- | --- | --- |
| F-1 | routing-reach | pipeline-reviewer's path trigger misses a DTO-only rename, a client retype and a store schema change; a producer is only recognizable by its contents (`SKILL.md:193`, `:169`) | new | became D-1 |
| F-2 | routing-reach | pipeline-reviewer's rules compare the current producer, contract and consumer; none names in-flight base-shape items or the base reader (`pipeline-reviewer.md:22`, `:53`, `:59`) | already-had | became D-1 |
| F-3 | routing-reach | The lead pass's mandatory named risk covers only a newly depended-on persisted field, not a rename, removal or retype (`lead-pass-checklist.md:16-25`) | new | became D-1 |
| F-4 | routing-reach | "Declared client" is defined nowhere in the plugins or docs | already-had | became D-2 |
| F-5 | routing-reach | db-reviewer's literal glob `*.schema.*` misses `prisma/schema.prisma`; arming relies on model judgment | not material | not material — an arming-glob issue outside this rule; D-1 homes the rule in the lead pass |
| F-6 | seam-overlap | Seam map; #951's rule is at `db-reviewer.md:52-62`, not `:100` | new | became D-5 (pointer correction) |
| F-7 | seam-overlap | A tolerant reader is what `complexity-reviewer.md:51` / `lead-pass-checklist.md:244` flag; "Intentional complexity" does not reach that row (`:43`) | already-had | became D-6 |
| F-8 | seam-overlap | The rollback check conflicts with the Pre-Emit Gate's "concrete today" (`lead-pass-checklist.md:64-90`) | new | became D-4 (rollout-window framing) |
| F-9 | seam-overlap | A pipeline-reviewer home misses a payload rename in a shared DTO file (`SKILL.md:193`, `pipeline-reviewer.md:22`) | already-had | became D-1 |
| F-10 | precision-and-guard | The consumer-shaped store fixture routes to db-reviewer, never to pipeline-reviewer (`SKILL.md:192-193`) | already-had | became D-1 |
| F-11 | precision-and-guard | The new Warning overlaps the existing Critical at `pipeline-reviewer.md:53` on a coordinated rename | new | became D-3 |
| F-12 | precision-and-guard | A tolerant reader in an unchanged file is invisible from the diff, so both rules false-fire (`pipeline-reviewer.md:23`) | new | became D-1 (named-risk read) |
| F-13 | precision-and-guard | No review-context section declares clients, so a frontend retype reads either way | already-had | became D-2 |
| F-14 | precision-and-guard | The guard cannot run in model-free CI; there is no eval for this dimension (`docs/testing.md:279`) | already-had | became D-7 |
| F-15 | in-flight-semantics | The lead pass has no pipeline dimension; a DTO-file rename reaches no payload rule (`lead-pass-checklist.md:137-328`) | already-had | became D-1 |
| F-16 | in-flight-semantics | Reverse-direction evidence lives in the base tree, outside the hunk; plan-reviewer has no reverse row (`plan-reviewer.md:166-174`) | new | became D-4 (cited intolerance required) |
| F-17 | premortem | The declared-client clause has no reader in any review-context section (`docs/extension-points.md:55-92`) | already-had | became D-2 |
| F-18 | premortem | #950 D-2 dropped its replay; the guard has precedent for being dropped (`docs/plans/second-shift-950-decisions.md:8`) | already-had | became D-7 |

### Snapshot

    | ID | Decision | Resolution |
    | --- | --- | --- |
    | D-1 | Home of the rule | open — lead pass (always runs in the lane; spans queue, store and client) vs pipeline-reviewer (fires only on worker/queue file changes, SKILL.md:193; a store-only change like the consumer case never triggers it) vs a split (queue → pipeline-reviewer, store → db-reviewer :99/:100). Leaning lead pass |
    | D-2 | Rollback direction (base reader vs new writes) | open — in as Warning with cited intolerance, or out |
    | D-3 | Two-step column-drop row at db-reviewer.md:99 | open — :99 checks "destructive without clear intent" only; intent-declared drop with old readers still deployed is not asked; :100 covers doc stores only |
    | D-4 | Compat-shim exemption (complexity-reviewer.md:51, lead-pass-checklist.md:244) | open — needed so expand/contract shims the new rule asks for aren't flagged as one-shot shims |
    | D-5 | Meaning of "declared-client boundary" | open — undefined anywhere in the repo; ticket forbids a new review-context H2 (breaking-class). Candidate: reuse Data provenance's "crosses a service boundary" |
    | D-6 | Guard: replay on the parent of the consumer case | open — the lane cannot reach the consumer checkout; precedent #950 D-2 dropped replay; memory says replay reviewer-prompt fixes before shipping |
    | D-7 | Severity | Warning only (ticket body) |
    | D-8 | Output form | ordinary findings, no new report section (unlike Data provenance) |
    | D-9 | Checks | likely empty form — prose change, no-prose-presence-guards rule; check-reviewer-references/check-review-context-sections untouched |
    | D-10 | Duplicate scan | rc=0, nothing recorded |
