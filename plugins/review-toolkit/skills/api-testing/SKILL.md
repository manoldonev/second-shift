---
name: api-testing
description: Generic conventions for black-box API tests (default home tests/api/). Loaded by api-test-coder, api-test-plan-reviewer, and api-test-reviewer. Repo-specific harness details load from the repo's API-testing extension.
---

# API Testing Conventions

The generic, repo-agnostic discipline for black-box API tests. Gated by config
`gates.apiTests` — only active in repos that enable the tier. The **repo-specific
harness** (base service class, fixtures, managers, path aliases, auth/session setup,
surface split, verification commands, example specs) is NOT here — it lives in the
consumer repo and loads via the extension point below. This skill is the shared
source of truth for `api-test-coder`, `api-test-plan-reviewer`, and `api-test-reviewer`.

## Repo harness reference (extension point — read FIRST)

Load the repo's API-test harness reference from
**`.claude/second-shift/api-testing/*.md`** (and/or the repo's own `API_TESTING_GUIDE`
that it points to). It declares: the test project root (default `tests/api/`), the base
service class + how routes/auth are wired, the fixtures/managers registration files, the
path aliases, any surface split (e.g. admin vs portal), the seeded/staging data model, and
1–2 canonical example specs to mirror. If the extension is absent, discover conservatively
(find the API-test project, read a couple of existing specs, infer the harness) and say so
in your output — do not invent harness details.

**Verification commands come from config** (`commands.<repo>.apiTest` for the behavioral
run; the repo's `commands.<repo>.lint`/`typecheck` cover static checks) — never hardcode a
`yarn …` invocation; read the truth table.

## Ownership boundary

Dev agents own white-box unit/supertest specs co-located in the source tree (`*.spec.ts`
next to the code); API/QA agents own black-box specs under the API-test project root. Keep
the two surfaces separate — don't reach into source internals from a black-box spec, and
don't black-box from a co-located unit spec.

## Pipeline ownership (dev-pipeline Stage 5) — WRITE-ONLY

When dispatched by the dev-pipeline (`api-tests.mjs`, `kind: "implement"`), `api-test-coder`
is **write-only**: it writes specs under the API-test project root and stops. The Stage-5
orchestrator owns the dirty-state scope-check (reverting anything outside the API-test
root), the static + behavioral verification runs, and the scoped `test:` commit. Don't run
the verification suite or commit from inside the coder dispatch. Static verification is
fail-closed in the inner loop; behavioral verification is advisory under autonomous default
(warn + `verifySummary`, CI authoritative post-push) and fail-closed under
`DEV_PIPELINE_MODE=interactive`.

## Test structure and coverage

- Group by endpoint or workflow.
- Endpoint-appropriate coverage (not blindly CRUD-shaped): for CRUD endpoints —
  list/get/count/create/update/delete where supported, plus filters, sort, pagination; for
  workflow endpoints — state transitions, validation, payment/summary behavior.
- Negative cases: DTO validation, invalid IDs, not-found, business-rule failures.
- Use the harness's setup/teardown helpers only for out-of-band setup/cleanup/restoration —
  not to bypass the endpoint under test.
- Use polling (`expect.poll` or the harness equivalent) for asynchronous backend state
  instead of arbitrary sleeps.
- No `test.skip` placeholders.
- When a test covers a ticket acceptance criterion, suffix its title with `(AC-n)` where it
  reads naturally — never forced onto infra tests that map to no AC.

## Data isolation (critical)

Every new test must survive **multiple parallel runs** of the same spec:

- Run-scoped generated data for every created entity (emails, names, codes, slugs, windows).
- Cleanup in `afterAll`, filtered by the current run's identifier — never broad filters that
  delete another run's data.
- Restore mutated seeded / external state in `afterAll`.
- Async assertions/polling scoped to the current run's data — not global counts.

## Payloads and constants

- Add request/response types under the harness's payloads location when shapes are reused or
  non-trivial.
- Add constants for seeded IDs, expected baseline objects, org identifiers, status codes, and
  shared timeouts — don't inline magic values.
