---
name: mutation-review
description: Propose→execute mutation-review protocol for co-located unit tests — mock-boundary discipline, assertion-strength anti-patterns, the propose/execute split, the (AC-n) test-title convention, and the blocker-mutant emission contract. Runner commands and repo-specific blocker mutants come from the consumer config and extension files.
---

# Mutation review (propose → execute)

This skill defines the **generic** mutation-review protocol shared by `unit-test-mutation-reviewer` (proposes) and the pipeline's mutation-gate sequencer (executes). It is repo-agnostic: the test-runner command comes from the consumer config, and any repo-specific blocker-mutant classes come from `.claude/second-shift/blocker-mutants.md`. Repo conventions (which test framework, co-location rules, fixture tricks) live in the consuming repo's own testing skill, not here.

**Runner commands come from config.** The executor runs the repo's configured `test` command (from `<repo-root>/.claude/second-shift.config.json` `commands.<host>.test`, env override `SECOND_SHIFT_CONFIG`) scoped to the spec path — this skill never hardcodes a package manager or command. Where a step below says "run the spec", it means: invoke the configured `test` command against that spec file.

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

**`(AC-n)` traceability convention.** When a test verifies a specific acceptance criterion, attach the literal `(AC-n)` token where the framework can carry it: suffix the test title where the framework has one — e.g. `it('credits the record on upload (AC-1)', …)` — or put it in an adjacent comment where it does not, e.g. pytest: `def test_credits_record_on_upload():  # (AC-1)`. Convention-based and best-effort: never forced on infra/refactor tests, and nothing hard-gates it. It lets a plan traceability table name a concrete test and lets an AC-coverage audit grep the PR diff for coverage. A covered-but-unlabeled test still counts (a diff-hunk audit leg catches it) — the token just makes coverage cheaply auditable.

## Mutation review process (propose → execute split — no full-matrix mutation tool)

The reviewer **proposes**; the sequencer **executes**. The mutation reviewer agent does NOT apply mutants or run the test command — keeping execution out of the schema-forced agent turn is what prevents a StructuredOutput staller. The agent emits machine-applicable patches; the sequencer executes each blocker patch via a sequential **schema-free** executor agent (apply via Edit → run the spec → revert → emit a plain-text `MUTANT_RESULT` line parsed in JS) and computes the verdict deterministically — the pipeline session never applies/runs/reverts mutants itself.

The mutation stage runs after all commits land, so the worktree is clean — use `git diff <base>...<head>` (an explicit commit range from the dispatching stage), not `git diff HEAD`. Scope mutants to lines changed in that range only. Three dots, not two: three-dot measures from `merge-base(<base>, <head>)`, so commits that landed on the base branch after the branch point stay out of the range. Under two-dot they appear as deletions and you would propose mutants for code this ticket never touched.

For each changed production file in the diff (the **reviewer's** job, propose-only):

1. List mutation targets: conditionals, operators, filters, early returns, thrown errors, tenant/owner-scope predicates.
2. Propose 5–15 concrete mutants (e.g. "remove the tenant-scope predicate from the `where`", "`&&` → `||`", "delete the throw branch").
3. Trace each mutant against the spec: **killed** (assertion fails), **survived** (tests still pass), **untested** (no path reaches code).
4. For each **blocker-class** mutant predicted survived/untested, emit a uniquely-matching `{ originalSnippet, mutatedSnippet }` patch + the `specPath` — so the executor can verify it. If you cannot produce a unique snippet, downgrade to `warning` (an unverifiable mutant must never block).
5. Flag mock-only specs where every assertion is call-count without argument inspection.

The **sequencer's executor agent** then, per blocker-class patch: apply → run the configured `test` command against `<specPath>` → test failure means **killed** (drop) / all pass means **survived** (keep blocker) → revert (always, even on error). A handful of targeted runs — not a full mutation matrix.

Non-blocker mutants (logic branches, error paths, operators on low-risk paths) stay LLM-predicted and advisory.

## Blocker-class mutants (always Blocker if survived/untested)

These generic classes are **always** blocker-class when the mutant survives or is untested — the mutant reaching production would be a security or correctness breach:

- **Tenant-isolation / owner-scope predicate removed or wrong** — the filter that restricts a query to the current tenant/owner is deleted or compares the wrong key (multi-tenant data leak).
- **Auth guard / ownership check bypass** — a guard annotation or an ownership comparison removed or negated.
- **Validation throw → silent return** — a `throw` on a validation or not-found path mutated to `return undefined` / `return null`.

**Repo-specific blocker instances are additive.** If `.claude/second-shift/blocker-mutants.md` exists in the repo under review, load it — it lists the repo's concrete instances of these classes (e.g. the exact ORM predicate, guard decorator, and the tables it scopes) plus any domain-specific blocker classes (financial rounding guards, permission-scope mappings, etc.). Those add blocker instances; they never relax these generic classes. A repo with no such file uses the three generic classes above.
