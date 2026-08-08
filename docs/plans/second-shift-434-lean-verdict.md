# lean review verdict — #434

verdict=approve
run_id: review-434-1
session_id: eca0c0fb-a094-4395-b76b-03b920012f83
rounds: 1
pr: #437
reviewed_head: 4147030a041fbeedaa55c620c871d9a78f0b1c54
reviewed_patch_id: 5fae635ea01dac2c1c7f851d87780d0abb46e1aa
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown

## Review Summary

Round 1, full branch range `6bea3bd..HEAD` (nothing to inherit — chain root), 20 files /
723 insertions, reviewed from a checkout of the PR head. Seven reviewers dispatched via
`code-review.mjs`; none went dark.

The diff does what #434 asked and, more importantly, does the part the issue only
*suggested*: qualifying the ten panel names would have left the zero-coverage verdict
reachable, because `budgetExhausted` produces an all-dark panel by construction. The void
is what actually closes the class. All twelve `AC-n` are satisfied. No blockers.

Two coverage gaps survive, both on **correct** production code and both **confirmed by
execution**, not predicted: the `agentType: requested` invariant that AC-2 turns on is
unguarded at two of its five return sites, and the lint's empty-`.name` guard has no
fixture. Neither is an unmet AC — AC-8 and AC-9 name what they require and the diff
delivers it — so they are warnings, not blockers.

Design fidelity: **not applicable** — the spec declares no `## Design` section, and
`check-lean-chain.sh` independently reports "spec declares no armed design render lane".

## Strengths

- The fix is scoped to the failure *class*, not the reported symptom. Both the spec and
  `code-review.mjs`'s own comment identify that `budgetExhausted` (`:306`) reaches an
  all-dark panel with every name correct, so the void ships alongside the names rather
  than instead of them.
- Returning the caller's spelling while dispatching the resolved one is the non-obvious
  half, and it is argued in-file (`code-review.mjs:349-355`) rather than merely done:
  Step 4b's budget-skipped path enumerates darkness by comparing the returned set against
  `args.reviewers`, so returning the resolved name would have traded this bug for a
  quieter one.
- The lint derives its expected prefix from the resolving root's own
  `.claude-plugin/plugin.json` instead of hardcoding `review-toolkit:` — which is what
  makes it correct in the installed-cache layout, where the root's basename is the
  version. Verified live against both layouts.
- `qualify-real-panel` runs the new class against a de-qualified copy of the **shipped**
  `SKILL.md`, so the guard is proven on the artifact that ships rather than only on a
  two-entry fixture; and `qualify-manifest-absent` fails in both directions — a denial
  fails, and a silent pass fails too.
- The D-9/D-8 incompatibility is recorded and demonstrated (`require_mutable` refusing
  `pr-add`/`comment-add`/`mark-completed` after `mark-failed`) rather than asserted, and
  the ratification record states plainly that the run typed the ratifying comment on the
  maintainer's behalf.

## Findings

| # | Severity | Reviewer | Location | Finding |
| --- | --- | --- | --- | --- |
| 1 | Warning | Unit Test Mutation (85) | `plugins/dev-pipeline/skills/run/workflows/code-review.mjs:426-427` | The `agentType: requested` invariant is unguarded on both hard-dispatch-throw returns. **Probe (executed):** replacing `requested` with `dispatched` on `:426`, and independently on `:427`, leaves `runtime-shim-selftest.mjs` at 86/86. Cases `B6`/`B7` do reach those lines, but through `runCodeReview`'s default `reviewers: ['review-toolkit:complexity-reviewer']`, so `dispatched === requested` there and the swap is invisible. Case Q pins the invariant only on the success return (`:430`) and the twice-dead fallback (`:454`). Remedy: one Case-Q sub-case pairing `reviewers: ['security-reviewer']` with `[{ throw: 'boom' }]` and with `['no sentinel', { throw: 'x' }]`, asserting the returned `agentType` is `security-reviewer`. |
| 2 | Warning | Unit Test Mutation (80) | `plugins/review-toolkit/scripts/check-reviewer-references.sh:214` | `[ -n "$n" ] || return 1` has no fixture exercising it. **Probe (executed):** replacing it with `:` leaves `check-reviewer-references-selftest.sh` at 19/19. `qualify-manifest-absent` removes the whole `.claude-plugin` directory, which trips the earlier `[ -f … ]` instead. The consequence if it regresses is fail-*silent*, which is the one posture this class exists to prevent: an empty or absent `.name` yields `expected=""`, which compares equal to a bare entry's empty `entry_prefix`, so QUALIFY accepts the #434 shape with no error and no notice. Remedy: a fixture root whose `plugin.json` omits `name`, asserting exit 0 plus the "no readable .claude-plugin/plugin.json" notice. |
| 3 | Warning | Cross-cutting | `plugins/dev-pipeline/skills/run/stages/8-code-review.md:246`, `:252` | The void is a fourth terminating path that the shared receipt block does not enumerate. Its header reads "Receipt + PR review (**every terminating path** — clean, exhausted, scope-blocker)", and the "**State:**" line at `:252` lists the clean and exhausted writes only. This is mechanical, not cosmetic: `review-rounds --set 1 --voided` sets `codeReviewRounds = 1`, which arms `statectl.sh:1072-1074`'s `require_comment_receipts 8 … code-review`, so a void that posts the `review-void-zero-coverage` comment but never records its URL via `comment-add` cannot close stage 8. The new `voided-review` liveness scenario *does* call `comment-add`, so the harness already treats the receipt as required — only the prose an executor follows omits it. |
| 4 | Suggestion | Maintainability | `docs/namespaces.md:6` | The new QUALIFY messages, `check-reviewer-references.sh`'s class-(e) header, and the fixture prose all cite "`docs/namespaces.md` rule 2" as the authority. Rule 2's letter covers "`.mjs` workflows and stage files"; a `SKILL.md` is neither, and the clause this diff deleted from `review-lead/SKILL.md:56` was precisely rule 2's same-plugin-skill carve-out. `stages/4-plan-review.md:49` already states the general form, so the convention is not unrecorded — just not at the place the lint points. One clause in `namespaces.md` closes it. |
| 5 | Suggestion | Test Coverage (70) + Unit Test Mutation (82) | `plugins/dev-pipeline/skills/run/workflows/code-review.mjs:53-55` | `QUALIFIED_BY_BARE`'s collision branch (`b in acc ? null : key`) is unreachable with today's `REVIEWER_MODEL` — no two qualified keys share a basename — so a mutant that always takes the last match is equivalent. Two reviewers reached this independently. A documented defensive default; worth a synthetic-table case only if the table ever grows a collision. |
| 6 | Suggestion | Orchestrator | `plugins/review-toolkit/skills/review-lead/SKILL.md`, Step 4b-void | The threshold is a governing sentence ("no selected reviewer produced a usable result") plus an enumeration of two signals. A third shape satisfies the sentence without matching either signal: a selected reviewer whose thunk rejected is dropped by `results.filter(Boolean)`, so it is neither present-as-`null` nor budget-skipped. Effectively unreachable today — every dispatch error inside `dispatchReviewer` is caught — so this is a wording tightening, not a defect. |

**Suppressed** (below the confidence bar, recorded for visibility):

- [Security, 40] `code-review.mjs:56` — `QUALIFIED_BY_BARE` is a plain object literal, so a
  reviewer literally named `constructor`/`toString` would resolve through
  `Object.prototype`. Names are repo-trusted, none collide, and nothing writes to the
  prototype. `Object.create(null)` would be hardening, not a fix.

## Acceptance criteria

Every `AC-n` is scored against the whole spec, per the round contract. All twelve are
**satisfied**; none is undeterminable.

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | The panel parenthetical carries `review-toolkit:` on all ten entries beside the two existing `design-toolkit:` ones (extracted and counted from `SKILL.md`); `:56`'s "referenced bare too" clause is replaced by the bare/qualified asymmetry. Routing tables, Verdicts template and running prose untouched. Both parsers still work: `check-reviewer-references.sh` returns **rc=0** on the real tree, and `_effective-registry.sh:26` strips the prefix via the same `grep -oE '[a-z][a-z0-9-]+-reviewer'`. |
| AC-2 | satisfied | Verified by executing the real body (Case Q) *and* by reading all six return sites: the five in `dispatchReviewer` plus `withCeiling`'s ceiling return, which uses the outer caller-passed `agentType`. Dispatch uses `dispatched`, `modelOverrides`/`REVIEWER_MODEL` key on `dispatched` (recovering `opus` for `security-reviewer`), one `log()` names the substitution, already-qualified and repo-local names pass through unchanged. Finding 1 is a test gap on this invariant, not a violation of it. |
| AC-3 | satisfied | `Step 4b-void` states the strictly-zero threshold across both Step-4b signals, mandates a "review did not run" report naming the dark set and reason, forbids answering "Ready to merge?", and says so again at the Rules bullet and the verdict paragraph. Partial-dark explicitly unchanged. |
| AC-4 | satisfied | `review-lean/SKILL.md` step 5c: post the coverage gap, write no record, do not spend the round; plus the non-negotiable "a round that reviewed nothing produces no record". Cites the step-4 precedent and `check-lean-chain.sh`'s absent-record violation, matching D-15. |
| AC-5 | satisfied | `stages/8-code-review.md` "Voided round" routes to draft + `needs-deep-review` with **no retry**, naming all three retry-proof causes. Finding 3 is an omission in the *shared receipt* block, not in this section. |
| AC-6 | satisfied | `cmd_review_rounds` gains `--voided` and one `jq` clause `(if $voided then .codeReviewVoided = true else . end)` in the same atomic bundle as `--set`, never written `false`; `state-schema.md` carries the field entry and adds `review-void-zero-coverage` to the `code-review` marker row's Statuses column. No `mark-failed`, so the run stays `in_progress` — confirmed by the liveness scenario reaching `mark-completed` ACCEPTED. The generated-validator regions are untouched (the Statuses column is documentation-only; only the first column feeds `parse_stage_markers`). |
| AC-7 | satisfied | Failure class (e) for panel entries plus (f) for `reviewers.add`; the prefix comes from `plugin_name_of()` reading the resolving root's `plugin.json` `.name`, never hardcoded — verified correct in both on-disk layouts (repo `plugins/*` and versioned installed cache). No cross-check against `REVIEWER_MODEL`. A design-toolkit-absent entry resolves in no root and is skipped, extending the existing exemption; an unreadable manifest prints the notice. Finding 2 is a missing fixture for one arm of that degrade, not a defect in it. |
| AC-8 | satisfied | Case Q executes the real `code-review.mjs` body: dispatched name qualified, dispatched model `opus`, returned `agentType` the caller's spelling, substitution logged, and the repo-local bare name bare end to end. `runtime-shim-selftest.mjs` **86 passed, 0 failed** (run locally). |
| AC-9 | satisfied | Five new cases — bare plugin-backed entry denies, wrong-plugin prefix denies, prefixed `reviewers.add` denies, underivable prefix degrades to exit 0 + notice, and the shipped panel de-qualified denies. Each greps the QUALIFY line rather than a bare non-zero exit. `check-reviewer-references-selftest.sh` **19 passed, 0 failed** (run locally). |
| AC-10 | satisfied | `(rr7)` the flag writes the field and a plain `--set` leaves it absent; `(rr8)` independence in both directions; `(rr9)` a later plain `--set` cannot reset a recorded void. |
| AC-11 | satisfied | `voided-review` scenario drives void marker → stage 9 → `mark-completed` ACCEPTED `(vr1)`, asserts separability from exhaustion `(vr2)`, and carries the non-vacuity half `(vr3)` mirroring `(xr2)`. OR-1's default taken, as the spec states. |
| AC-12 | satisfied | All three named sites updated, each stating its own layer's contract: Stage 8's dark-reviewer subsection, `review-lead`'s Step 4b + Rules + verdict paragraph, `review-lean`'s step 5c + rule. Finding 3 identifies a *fourth* site AC-12 does not name. |

Design fidelity: **not-applicable** — no `## Design` section in the spec, no armed render
lane, so no receipt, no `RS-n` rows, and nothing to hash-verify or re-render.

## Verdicts

| Reviewer | Verdict | Findings | Confidence |
| --- | --- | --- | --- |
| Scope Completeness | Pass | 0 | — |
| Security | Pass | 0 (1 suppressed) | — |
| Performance | Pass | 0 | — |
| Complexity | Pass | 0 | — |
| Maintainability | Pass | 0 | — |
| Test Coverage | Pass | 0 (1 suppressed) | — |
| Unit Test Mutation | Fail | 4 | 80-85 |

No reviewer went dark. `db-reviewer` and `pipeline-reviewer` were not selected (no DB or
queue surface). `a11y-reviewer` and the design-fidelity dimension were not routed: no
changed path matches `stageParams.webComponentGlobs`, which resolves to the shipped
default `apps/web/**/*.{tsx,jsx}` because the repo's config declares neither key.

## Build evidence

- CI at `4147030`: `lint-and-selftests` **pass** (13m13s — this job carries the PR-scoped
  mutation sweep, so the baseline-ordinal re-key the PR body deferred to CI is adjudicated
  green), `selftests (macos, bash 3.2)` **pass** (17m34s), `release-pr-gates` skipped.
- `pr-gates` is red on exactly one step, reproduced locally with the job's own env:
  `check-lean-chain.sh` → "no committed verdict record". That is the artifact this round
  writes; every other arm of that gate passes (spec with 15 `AC-n` references, bot-authored
  claim comment inside the PR-open window, ratified intent gap, design lane not applicable).
- Run locally at the reviewed head: `check-reviewer-references.sh` rc=0,
  `check-reviewer-references-selftest.sh` 19/19, `runtime-shim-selftest.mjs` 86/86.
- The spec was committed first (`64d2396`) and never amended; the only later doc edit adds
  the intent gap's ratification provenance. No post-hoc rewrite to match the diff.

**Verdict: approve.** No blocker. The three warnings are follow-up work — two are missing
guards on code that is correct today, one is a prose enumeration that a later executor of
the void path would trip over.
