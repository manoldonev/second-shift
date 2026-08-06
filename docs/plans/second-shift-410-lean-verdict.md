# lean review verdict — #410

verdict=approve
run_id: review-410-1
session_id: eeaffb6a-f0d6-4a65-9279-38de4b5ef866
rounds: 1
pr: #411
reviewed_head: d428a33893d33dd0c47f026856fc9310a4550ae8
reviewed_patch_id: 1634e854a3fa223b3f3a4cb0906b94fa08d5fc4b
inherited_patch_id: none
inherited_from_verdict: none
model: unknown

## Review Summary

Round 1, full branch range (`a74af10..d428a33`) — nothing to inherit. Seven reviewers dispatched
via `code-review.mjs`; all seven returned, none dark. Six `approve`, one `approve-with-nits`.

All ten ACs are satisfied. The change does what the spec says and does it in the shape the spec
names: the new axis is mechanically capped at Warning (`mockAuditFindings[]`'s `warning | note`
enum, and `mutation-gate.mjs` computes `overall` from `executions[]` only, so a decorative finding
is structurally incapable of reaching a blocking verdict). The issue's binding constraint — "a
second axis, not a discount on the first" — therefore holds by construction rather than by prose.

The one substantive finding is a false-positive path the criterion carries by design, contained to
advisory severity and to tests the same run just added. It does not block.

## Verification performed (this review, not inherited from the PR body)

- **Killing probe on every one of the six new assertions.** Five production mutations, each run
  against the whole suite:

  | Probe | Mutation | Result |
  | --- | --- | --- |
  | A | drop the decorative clause from the mutation-review prompt | `69 passed, 2 failed` — both P2 legs, nothing else moved |
  | B | leak the clause onto the plan-review branch | `70 passed, 1 failed` — P3's scoped leg only |
  | C | mutation branch dispatches `unit-test-plan-reviewer` | `70 passed, 1 failed` — P1 leg 1 only |
  | D | `MUTATION_REVIEW_SCHEMA.required` gains an absent key | `70 passed, 1 failed` — P1 leg 2 only |
  | E | rename the plan-review prompt opening | `70 passed, 1 failed` — P3's anti-vacuity leg only |

  Every new assertion is uniquely killable, and no two share a killer. By this PR's own new rule,
  none of them is decorative. The worktree was restored from a byte copy after each probe and
  verified clean with `git status --short` (never `git checkout`).
- **Full selftest sweep**, `-P 4`, **without** `SKIP_STRESS`, under `env -u CLAUDE_CODE_SESSION_ID`
  — `rc=0`. `runtime-shim-selftest.mjs`: 71 passed, 0 failed.
- `shellcheck -e SC1091,SC2015,SC2181` over every `*.sh`: `rc=0`. `jq empty` over every `*.json`:
  `rc=0`.
- `prose-budget.sh --report`: the three edited files read `ok`; the diff moves exactly three
  baseline rows and no others.
- `check-review-context.sh`: clean. `scripts/lockstep-manifest.tsv`: no row covers these files.
- Base drift: `git diff a74af10 origin/main` over every file this PR touches is empty, so the two
  commits main gained since the branch point (`#404`, the v4.0.0 release) do not collide here.

## Findings

| # | Severity | Where | Finding |
| --- | --- | --- | --- |
| 1 | Warning | `mutation-review/SKILL.md:54`, `unit-test-mutation-reviewer.md:40` | The criterion is "the only killer of no **proposed** mutant", and the proposed set is a sample (5–15 per module, scoped to diff hunks in changed *production* files). A test guarding behavior the reviewer did not sample — or covering code outside the changed hunks, i.e. a coverage backfill — is the only killer of no proposed mutant and is therefore reported decorative, with a **destructive** remedy ("delete it"). Nothing in the added text hedges this. Contained, and that containment is why it is not a blocker: the finding is capped at `warning`/`minor`, it is bounded to tests added in the same range (the pre-existing suite is never a target), Stage 5 dispositions it inline rather than gating, and Stage 8's Critical Coverage Intents run afterward on the resulting diff. One clause would close it — require the reviewer to *propose* the mutant the test would kill before concluding none exists, so "I did not sample it" cannot be read as "it kills nothing". |
| 2 | Suggestion | `unit-tests.mjs:305` | The trailing routing clause `— report those on mockAuditFindings with the remedy.` is unasserted. **Reproduced:** dropping only that clause (leaving both P2 regexes matching) leaves the suite at `71 passed, 0 failed`. `/on mockAuditFindings/` would be a killable assertion — the substring appears nowhere else in the prompt, which is the distinction from the bare `mockAuditFindings` token the build correctly deleted for matching the trailing `Return {…}` line. Low impact: the JSON contract is independently held by the epilogue template and `validateShape`. (Raised by `unit-test-mutation-reviewer`, confidence 82; reproduced here.) |
| 3 | Suggestion | `unit-test-mutation-reviewer.md:40` | The new cross-file citation `` (`mutation-review` step 6) `` is keyed on a **list ordinal**. Inserting a step into `mutation-review/SKILL.md`'s propose list silently retargets it, and no lane can red on that — there is no lockstep row for the pair and the coupling is prose-only. Citing the step by its name ("the decorative-tests step") would be ordinal-free. Pre-existing shape (the file already cites its own step 4 intra-file), so this is a nit, not a regression. |

Nothing else survived triage. `security-reviewer` suppressed one confidence-40 prompt-injection
note (the added text is a static literal; the interpolation sites are pre-existing and unchanged) —
correctly suppressed.

## Strengths

- The constraint is **mechanized, not asserted**. `mockAuditFindings[]`'s `warning | note` enum
  makes blocker severity unavailable to this class at the transport, and advisory mode maps
  decorative findings to `minor` **explicitly** rather than letting the default `warning → major`
  rule carry them into `request-changes`. That explicit override is the load-bearing line and it
  is present.
- **No new transport.** The change rides a channel Stage 5 already dispositions, adds no schema
  field, and touches no gate. `mutation-gate.mjs` needed no edit and got none — verified by reading
  its verdict computation, not by taking the PR body's word.
- The dispatch prompt was brought up to the agent contract (AC-8), so the Stage-5 seam is not
  weaker than the `.md` it dispatches — and that seam is the one place execution can see, so it is
  the one place a test was written. Case P asserts on an executed dispatch and pins both branches,
  which is what makes "scoped to the mutation-review branch" a real claim rather than a presence check.
- The build deleted one of its own new assertions after a probe showed it green under the mutation
  that killed its siblings. On a PR whose entire subject is coverage that cannot fail, that is the
  right instinct applied to itself.
- `Changelog:` hygiene is correct: one real trailer on the last commit, bare `Changelog: none.` on
  the spec commit — not the `none — <rationale>` shape that has shipped as a stray release bullet
  three times.

## AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | **satisfied** | Heading is `### Coverage That Cannot Fail (decorative tests)`; no clause scopes to pipeline-gate/contract-duplication changes. The lockstep-manifest remedy became "compare them mechanically"; the composed-contract rule names "a gate, a protocol, a shared schema" as examples, not preconditions. Nothing requires the repo to own gates, scenarios, fixtures, or a manifest. |
| AC-2 | **satisfied** | Seven table rows, one per issue shape (sibling-differs-by-fixture, static copy, existence inventory, absence of nonexistent code, asserting the library, pure function through an integration render) plus the retained mirror harness — each with its own "why it cannot fail" column. |
| AC-3 | **satisfied** | The section sits under `## Warning Rules` (`test-coverage-reviewer.md:74`), and its opening sentence reads "every rule here is a Warning and never downgrades a Critical Coverage Intent". `## Critical Coverage Intents (block merge if violated)` at line 39 is a real section, so the sentence names something that exists. |
| AC-4 | **satisfied** | "**Cost is the same signal.**" flags both an out-of-line wall-clock and a raised per-file test timeout, with "a raised ceiling is almost always a symptom, not a fix". |
| AC-5 | **satisfied** | Generalized, not deleted: a contract several components compose against must name its affected paths and say how the composed end-to-end test was extended for each. |
| AC-6 | **satisfied** | `mutation-review/SKILL.md` step 6 carries all three required properties explicitly — "added in the range", "`warning`/`note` only, never blocker-class", "report it on the propose-mode advisory channel" — plus the delete-or-fold remedy. |
| AC-7 | **satisfied** | Process step 8; severity table's `warning` row; propose-only mode (the `mockAuditFindings[]` advisory-channel paragraph); advisory mode (both the verdict line and the severity-mapping line). All four sites present. |
| AC-8 | **satisfied** | `unit-tests.mjs:304-305` names the decorative audit beside the mock-only audit and carries the criterion. |
| AC-9 | **satisfied** | Case P drives the real `unit-tests.mjs` under the shim with `kind: 'mutation-review'` and asserts on `calls[0].prompt`, following the H2a/H3a precedent; P1 is the anti-vacuity leg and probe C confirms it reds on a mis-routed dispatch. Probes A/B independently confirm P2 and P3 red on the mutations they claim to catch. |
| AC-10 | **satisfied** | The baseline diff is exactly three lines, all three the markdown files this PR edits; every other row is byte-identical (the 19 unrelated stale rows are untouched, as the spec's non-goal requires). `--report` returns all three to `ok`. |

**Verdict: approve.** No blockers. Findings 1–3 are advisory; finding 1 is worth a follow-up
ticket rather than a fix in this PR, since closing it means adding a clause the spec did not ask
for and the failure mode is contained by three independent mechanisms.
