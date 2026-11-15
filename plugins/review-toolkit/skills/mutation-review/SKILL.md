---
name: mutation-review
description: Mutation-review conventions for co-located unit tests — mock-boundary discipline, assertion-strength anti-patterns, the blocker-class mutant list and the diff-scoping rule. Loaded by unit-test-mutation-reviewer, which predicts survivors without executing them; repo-specific blocker mutants come from an extension file.
---

# Mutation review

This skill holds the **generic** conventions `unit-test-mutation-reviewer` applies when it proposes mutants and predicts whether the specs would catch them. The reviewer runs advisory only: nothing applies a mutant or runs a test, so every classification is a prediction. Repo-specific blocker-mutant classes come from `.claude/second-shift/blocker-mutants.md`. Repo conventions (which test framework, co-location rules, fixture tricks) live in the consuming repo's own testing skill, not here.

## Mock boundary

| Layer                  | Prefer                                                                                                                                                                               |
| ---------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Service business logic | Real collaborators where cheap; mock only I/O boundaries (the data-access handle, external HTTP, the queue/broker)                                                                   |
| Data access            | Unit tests may mock the injected data-access handle when testing query assembly; assert the **filter predicates** (especially the tenant/owner-scope predicate) and returned rows, not just that a query builder was called |
| Controller / handler   | Unit test with mocked service; assert input→output mapping (DTO/response shape + status)                                                                                             |
| Worker / processor     | Mock queue/logger; assert **job payload shape and chaining**, not just call count                                                                                                   |

## Assertion strength (anti-patterns)

Idioms below are illustrated with a common matcher vocabulary; use your test framework's equivalents.

**Weak — mutation survives:**

- Asserting a mock was called with no argument assertion (`toHaveBeenCalled` without `toHaveBeenCalledWith`)
- Asserting only that a method was invoked once when the bug is in **what** was passed or returned
- Testing the mock's return value instead of the SUT's output
- Single happy-path when the diff adds `if/else` branches

**Strong — mutant killed:**

- Argument assertions on meaningful values (the tenant key, a query predicate, a queue payload)
- Equality / throw assertions (`toEqual` / `toThrow` / `rejects.toThrow`) on the SUT's return value or error
- Table-driven cases (`it.each` / parametrize) over the branch matrix (status codes, guard combinations, domain edge cases)
- Multi-tenant services: seed two tenants, assert cross-tenant isolation (no leakage)

## Diff scoping

Use `git diff <base>...<head>` (the explicit commit range the dispatch names), not `git diff HEAD`. Scope mutants to lines changed in that range only. Three dots, not two: three-dot measures from `merge-base(<base>, <head>)`, so commits that landed on the base branch after the branch point stay out of the range. Under two-dot they appear as deletions and you would propose mutants for code this ticket never touched.

## Blocker-class mutants

These generic classes are **always** blocker-class when the mutant survives or is untested — the mutant reaching production would be a security or correctness breach:

- **Tenant-isolation / owner-scope predicate removed or wrong** — the filter that restricts a query to the current tenant/owner is deleted or compares the wrong key (multi-tenant data leak).
- **Auth guard / ownership check bypass** — a guard annotation or an ownership comparison removed or negated.
- **Validation throw → silent return** — a `throw` on a validation or not-found path mutated to `return undefined` / `return null`.

**Repo-specific blocker instances are additive.** If `.claude/second-shift/blocker-mutants.md` exists in the repo under review, load it — it lists the repo's concrete instances of these classes (e.g. the exact ORM predicate, guard decorator, and the tables it scopes) plus any domain-specific blocker classes (financial rounding guards, permission-scope mappings, etc.). Those add blocker instances; they never relax these generic classes. A repo with no such file uses the three generic classes above.

The advisory fan-out cannot verify a prediction by execution, so a blocker-class survivor is reported at `major`, never `blocker`.
