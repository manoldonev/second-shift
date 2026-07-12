---
name: interviewing-baseline
description: Shared interviewing protocol for all intake-role skills (intake-interviewer, plan-interview, grill-me, intake-orchestrator escalations). Provides the interview loop rules and the Decision Ledger contract — schema, provenance enum, explicit-empty form.
---

# Interviewing Baseline Protocol

This skill defines the shared protocol that ALL interviewing/elicitation skills follow, the same way `review-toolkit:reviewer-baseline` unifies the reviewer agents. It exists so loop rules and the Decision Ledger contract live in exactly one place.

**Canonical source notice:** this file is the single source of truth for the Decision Ledger schema and provenance enum. Every other site that restates them (`plan-interview/tools/ledger-lint.sh`, this plugin's `hooks/exitplan-ledger-gate.sh` via that lint, `review-toolkit:plan-reviewer`) carries a mirror marker and must be updated in lockstep when this section changes.

## Interview Loop Rules

Rules for every interviewing turn, regardless of which skill is running:

1. **Explore first.** If a question can be answered by reading the codebase, the repo's docs, or ADRs (Grep/Glob/Read, or dispatching `review-toolkit:codebase-explorer` where the calling skill supports it), answer it yourself instead of asking. Asking the user a codebase-answerable question is a protocol violation.
2. **At most 2 questions per turn.** The user disengages otherwise. Related sub-choices may share one `AskUserQuestion` call, but the material decisions per turn stay ≤ 2.
3. **Attach a recommendation only when it's grounded** in the user's input, the codebase, or the repo's docs — cite the grounding. If nothing grounds an answer, ask plain — do not guess. (Reporter-owned facts — environment, frequency, business intent — are rarely groundable; design decisions almost always are.)
4. **Recommended answer goes first.** When using `AskUserQuestion`, the grounded recommendation is the first option, labeled `(Recommended)`.
5. **Never re-ask.** A question answered earlier in the session — or already resolved in the artifact under discussion — is settled. If the user declines to answer, record it (`TBD` in a ticket draft; `deferred` in a Decision Ledger) and move on.
6. **"Your call" is a valid answer.** When the user delegates a decision, record the recommendation as the resolution with provenance `user-delegated` — do not re-open it later.
7. **Disambiguate domain nouns before drafting.** A noun with >1 plausible schema referent (`git grep` over the repo's data-schema definitions, plus adjacent service interfaces) is forced to a choice by question — never picked by word-similarity.

## The Decision Ledger

<!-- canonical: interviewing-baseline provenance enum — all mirrors keep verbatim -->

The machine-checkable residue every elicitation leaves behind. It is a mandated `## Decision Ledger` section in the implementation plan (or, pre-flight for a pipeline ticket, a standalone `.claude/pipeline-state/{issue}-ledger.md`):

```
| ID  | Decision | Resolution | Provenance |
| --- | -------- | ---------- | ---------- |
| D-1 | Uniqueness of document fingerprint per user | Partial unique index on (userId, fingerprint) | user-answered |
| D-2 | 404 vs 409 on duplicate import | 409 | user-delegated |
| D-3 | DTO validation library | class-validator (repo convention, CLAUDE.md) | codebase-derived |
| D-4 | Backfill order for historical records | deferred to next milestone (owner: reporter) | deferred |
```

**Provenance closed enum** — exactly these four values:

- `user-answered` — the engineer made the call in the interview.
- `user-delegated` — the engineer said "your call"; the grounded recommendation is recorded as the resolution.
- `codebase-derived` — grounded in code, an ADR, the repo's CLAUDE.md, or the Product-Essence Brief; the Resolution cites the source.
- `deferred` — explicitly parked, with owner and when it must be resolved in the Resolution cell.

`assumed` is **not** a legal value. An assumption either gets asked, grounded, or deferred explicitly — the ledger makes a silent assumption a lint error instead of a style problem.

**Rules:**

- IDs are stable `D-1..n` and never reused after retirement (same discipline as `AC-n` IDs).
- Resolution is never empty.
- **Explicit empty form** for trivial work — the section must still exist, containing exactly this line instead of a table:

  ```
  No material decisions — all choices codebase-derived.
  ```

## Who emits what

Each intake-role skill keeps its own purpose and trigger; what unifies them is the ledger:

| Skill                                            | Elicits                                      | Ledger role                                                       |
| ------------------------------------------------ | -------------------------------------------- | ----------------------------------------------------------------- |
| `intake-interviewer`                             | requirements from a reporter                 | emits a ledger seeded with requirement-level decisions            |
| `intake-orchestrator` / `decomposition-reviewer` | escalation-point choices                     | escalation answers → `user-answered`; open questions → `deferred` |
| `plan-interview`                                 | the engineer's load-bearing design decisions | primary author of the ledger                                      |
| `grill-me`                                       | challenges to an existing plan/design        | resolutions recorded back into the ledger as `user-answered`      |
| `design-toolkit:design-faithful-spec`            | ambiguous states/transitions in a handoff    | Open Questions double as `deferred` rows                          |

Routing between these skills lives in the `intake` front-door skill — see its scenario roadmap; do not restate routing here.

## What all interviewers must avoid

- Quizzing the engineer — questions elicit decisions; they never test comprehension.
- Asking codebase-answerable questions.
- Ungrounded recommendations dressed as grounded ones.
- Re-litigating a decision the user already made (in this session or in the ledger).
