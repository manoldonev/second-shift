# Intake record — #959

A unique constraint's scope (key columns, partial/filtered predicate, ORM-only) checked against a new lookup's or upsert's predicate on identity paths. Pre-flight interview with the operator, 2026-10-10. The ticket body is the operator's own; rows citing it as `user-answered` are decisions the operator wrote there. No design handoff (a reviewer-prompt change, nothing rendered). Duplicate scan: rc 0.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Home of the check, and how it reaches the lane | db-reviewer only, as a new section in `plugins/review-toolkit/agents/db-reviewer.md` (beside the Consumed-field persistence check) plus a pointer from Review Process step 3. No lead-pass rule. The db-reviewer routing row (`review-lead/SKILL.md:192`) gains an arm: the diff adds a lookup or upsert keyed on a non-PK field on an identity path (D-2), using a verb named under `Database stack` (D-8) or the engine's native verbs. It is a surface trigger, so it fires under the pipeline default panel too (`SKILL.md:219`); the "Every other row is untouched" paragraph names it beside the standalone-only newly-read arm. Reopened at intake: the first answer rested on an unverified claim that a new lookup always counts as query code, and the row's examples (`*.schema.*`, a migrations dir) do not guarantee that | user-answered | intent |
| D-2 | Scope: which paths | Identity paths only: auth, dedup, restore/upsert, cross-tenant admin. A new lookup or upsert keyed on a non-PK field on one of those paths (ticket, Proposal) | user-answered | intent |
| D-3 | What is compared | The constraint's key columns, its partial/filtered predicate (partial unique index, sparse index, `partialFilterExpression`), and whether it is ORM-only (declared on the model but not enforced by the store), each against the new predicate. The finding cites the constraint's `file:line` | user-answered | intent |
| D-4 | Upsert arms | In: a read (`findOne` / `LIMIT 1`) or document-store upsert whose filter is narrower or wider than the constraint, and PostgreSQL `ON CONFLICT DO NOTHING` with no conflict target. Out: `ON CONFLICT (cols)` with no matching constraint, because PostgreSQL raises on it (ticket, Evidence). The existing `Upserts use proper conflict targets` line (`db-reviewer.md:91`) is unchanged | user-answered | intent |
| D-5 | Emission bar | Emit only on a verified mismatch. When the constraint cannot be located within budget, report `unable to verify — pointer needed: <constraint for entity.field>`, the same form as the Consumed-field check (`db-reviewer.md:61`) | user-answered | intent |
| D-6 | Severity | Warning by default. Critical when the lookup authenticates or resolves a principal, or when the column the lookup omits is the tenant key, so it resolves across tenants | user-answered | intent |
| D-7 | Overlap with the missing-tenancy-key rule | When the existing two-condition tenancy Critical (`db-reviewer.md:70-77`) fires on the same call site, emit one finding: the tenancy Critical, citing the constraint's scope as evidence. No second finding | codebase-derived | fact |
| D-8 | Trigger vocabulary | One line added to the existing `## Database stack` template entry in `docs/extension-points.md:63`: list the repo's lookup and upsert verbs and wrappers; review-lead's routing arm (D-1) and the check both read it. No new catalog row (`section-catalog.txt:31` already covers the section), so no migration. When the line is absent, db-reviewer matches the engine's native verbs | user-answered | intent |
| D-9 | Collation mismatch | Out of scope. No measured hit; it gets its own ticket if a consumer defect shows one | user-answered | intent |
| D-10 | Replay guard (ticket `## Guard`) | Dropped, as #950 D-2 and #958 D-5 dropped it. This departs from the ticket's Guard section on the operator's call | user-answered | intent |
| D-11 | Intake-side mirror (plan-interview, plan-reviewer, spec-reviewer) | Out of scope. It gets its own ticket if wanted | user-answered | intent |
| D-12 | Tests | No prose-presence selftest (CLAUDE.md, the writing-tests rules). No catalog change, so `check-review-context-sections-selftest.sh` is untouched | codebase-derived | fact |
| D-13 | PR form | `feat(review-toolkit): ...` title, a `Changelog:` trailer (`Migration: none`), no version or CHANGELOG edits (CLAUDE.md) | codebase-derived | fact |

## Open Regions

No open regions — every decision in scope is ratified.

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | The db-reviewer finding for a verified scope mismatch: what it cites, its severity | decided (D-3) |
| S-2 | Severity on auth and cross-tenant paths | decided (D-6) |
| S-3 | The `unable to verify — pointer needed` output when the constraint is not found | decided (D-5) |
| S-4 | A single finding where the tenancy rule also fires | decided (D-7) |
| S-5 | The consumer-authored `Database stack` template prose in `docs/extension-points.md` | decided (D-8) |
| S-6 | Release notes: the `Changelog:` trailer | decided (D-13) |
| S-7 | Collation findings | out-of-scope — the operator scoped collation out (D-9) |
| S-9 | review-lead routing: db-reviewer selected on a new identity-path lookup, in the lane and standalone | decided (D-1) |
| S-8 | Intake-side surfaces (plan-interview, plan-reviewer, spec-reviewer) | out-of-scope — the operator scoped the intake mirror out (D-11) |

## Checks

No ticket-specific checks — the configured lanes cover this change.

## Fan-out

Fan-out: skipped — by the operator at the pre-flight notice: no reason given
