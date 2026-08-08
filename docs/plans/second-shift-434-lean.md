# second-shift #434 — review-lead dispatches plugin reviewers by bare name

## Problem

`review-lead`'s dispatch-mode panel (`plugins/review-toolkit/skills/review-lead/SKILL.md:32`)
names the ten review-toolkit reviewers **bare**, while `code-review.mjs` passes `agentType`
to `agent()` verbatim. Every dispatch dies with `agent type '<name>' not found`.

The deaths return as `{ agentType, result: null, error }` — the shape Step 4b classifies as
died-after-retry. So the round does not abort: it renders every row `Dark (no output)`, notes
a coverage gap, and still answers **"Ready to merge?"** on zero reviewer coverage. Under
`review-lean` that answer becomes the round's committed record.

Two independent defects, and fixing only the first leaves the second live: the
`budgetExhausted` path (`code-review.mjs:306`) produces an all-dark panel **by construction**,
so a zero-coverage verdict stays reachable with every name correctly qualified.

## Scope

Binding input: `.claude/pipeline-state/434-ledger.md` (D-1 … D-18, OR-1).

All four of the issue's suggestions land (D-1). Additionally in scope, because the receipt
carries them: the `review-lean` hand-back (D-5), the Stage-8 short-circuit (D-8), and the
void's state marker (D-9).

**Not in scope.** No name change outside `review-lead/SKILL.md` — Stage 8 already qualifies
every reviewer, and `pr-revision` delegates selection to review-lead and inherits the fix
(D-13). `intake-review.mjs` is structurally immune and is deliberately left alone (D-14).
`check-model-tiers.sh` is **not** the enforcement site: its bare-tolerance is load-bearing,
because it compares `.mjs` table keys against agent **files**, whose basenames are bare on
disk (D-12). The name sweep inside `review-lead/SKILL.md` stops at the panel parenthetical:
the Routing sub-registry parse anchors `\*\*[a-z][a-z0-9-]+-reviewer\*\*`
(`check-reviewer-references.sh:184`), which `**review-toolkit:db-reviewer**` does not match,
so qualifying the routing tables empties that sub-registry and fires DRIFT (D-11). The
Verdicts template's first column carries human display labels, not dispatch names (D-16).

**Intent gap.** D-9 names `failureContext.reason` as the void's state marker. That mechanism
is structurally incompatible with D-8, which the same receipt also settles — see
`docs/plans/second-shift-434-lean-intent-gap.md`. AC-6 implements the goal D-9 states under
the mechanism D-8 permits.

## Acceptance criteria

**AC-1 — The panel parenthetical dispatches resolvable names.** In
`plugins/review-toolkit/skills/review-lead/SKILL.md`, the ten review-toolkit entries of the
plugin-shipped panel enumeration carry the `review-toolkit:` prefix, matching the two
`design-toolkit:` entries already on that line. The "plugin reviewers are referenced bare too
within this same-plugin content" clause is gone. Routing tables, the Verdicts template and
running prose are unchanged (D-2). `check-reviewer-references.sh` and `_effective-registry.sh`
still parse the line — both strip a `plugin:` prefix for free (D-10).

**AC-2 — `code-review.mjs` normalizes a bare name rather than dying on it.** A reviewer name
the caller passes bare that resolves to exactly one qualified `REVIEWER_MODEL` key is
**dispatched qualified** — so its model tier resolves too — while the entry returned to the
caller carries `agentType` **exactly as the caller passed it**, and one `log()` line names the
substitution (D-6). Returning the caller's spelling is load-bearing: Step 4b's budget-skipped
path enumerates darkness by comparing the returned set against the set it passed as
`args.reviewers`, and a returned name the caller never selected breaks that comparison. A name
already qualified, and a repo-local `reviewers.add` name that matches no table key, are both
dispatched unchanged — the latter exactly as today.

**AC-3 — An all-dark panel voids the round instead of answering.** `review-lead`'s Synthesis
Rules gain a void: when **strictly zero** selected reviewers produced a usable result,
counting both Step-4b dark signals — every selected reviewer present as died-after-retry,
**and** `budgetExhausted: true` with `reviewers: []` — the skill emits a "review did not run"
report naming the dark set and the reason, and does **not** answer "Ready to merge?" (D-3,
D-4). This deliberately overrides the `Always give a clear verdict` rule for this one case,
and says so at both sites: forcing "No" asserts that a review found problems, which is false
in the other direction. A **partial**-dark panel is unchanged — a `[Coverage gap]` note, no
verdict change.

**AC-4 — `review-lean` hands back a voided round.** On a void, the review session posts the
coverage gap as the PR comment, writes **no** verdict record, and does not spend the round
(D-5). Mirrors the existing step-4 precedent ("a run whose audit ledger was never established
is not yours to certify"): the gate's refusals stay the separation, and `check-lean-chain.sh`
already treats an absent verdict record as a violation, so a hand-back cannot merge (D-15).

**AC-5 — Stage 8 short-circuits a voided round to the human handoff.** A void routes straight
to the existing draft + `needs-deep-review` handoff, with **no retry** round (D-8). The stated
reason ships with it: after AC-1/AC-2 the remaining causes are `budgetExhausted` (a retry
cannot help), an infrastructure-wide reviewer failure (poor odds for a full fan-out), and a
future name regression (AC-7 catches that pre-commit).

**AC-6 — A voided round is countable in state.** `statectl review-rounds` accepts `--voided`,
writing `codeReviewVoided: true` in the same atomic bundle as `--set`, additive-only and
never written false — structurally the sibling of `--exhausted`. `state-schema.md` carries
the field entry, and `review-void-zero-coverage` joins the `code-review` marker row's
Statuses-emitted column. The run stays `in_progress` and reaches its terminal
`mark-completed` (D-9's goal; see the intent-gap record for why not `failureContext.reason`).

**AC-7 — A lint makes the drafting hazard pre-commit.** `check-reviewer-references.sh` gains
one failure class: a panel entry whose agent file resolves in a **plugin** root must carry
that plugin's prefix, and a `reviewers.add` name must **not** carry one — `docs/namespaces.md`
rule 2, encoded. The prefix is **derived** from the resolving root's
`.claude-plugin/plugin.json` `name`, never hardcoded. No cross-check against `REVIEWER_MODEL`'s
keys (D-7). The existing design-toolkit-absent exemption extends to this class for the same
reason it covers DANGLING — with the root unresolvable there is nothing to derive from — and
an unreadable `plugin.json` degrades to a printed notice, never a silent skip.

**AC-8 — AC-2 is a shim case.** `workflows/runtime-shim-selftest.mjs` executes the real
`code-review.mjs` body with a bare reviewer name and asserts all three halves: the dispatched
`agentType` is qualified, the dispatched `model` is the qualified key's tier, the returned
`agentType` is the caller's spelling, and the substitution was logged. A repo-local bare name
that matches no key stays bare end to end (D-17).

**AC-9 — AC-7 is a lint selftest case.** `check-reviewer-references-selftest.sh` gains
fixture cases covering both directions of the class — an unqualified plugin-backed panel entry
denies, a correctly qualified one passes, a prefixed `reviewers.add` name denies — plus the
shipped-panel cell, so the REAL `review-lead/SKILL.md` is asserted clean against the class
that would have caught this bug (D-17).

**AC-10 — AC-6 is a statectl acceptance case.** `statectl-selftest.sh` covers `--voided`
alongside the existing `review-rounds` cases: the flag writes the field, a plain `--set`
leaves it absent, and a later `--set` cannot reset a recorded void (D-9).

**AC-11 — AC-6 composes to a terminal write.** `scenario-liveness-selftest.sh` gains a
`voided-review` scenario driving void marker → stage 9 → `mark-completed` ACCEPTED, with the
non-vacuity half the `exhausted-review` scenario carries (stage 9 incomplete → still refused).
This is OR-1's stated **default**, taken rather than reversed: the marker has a state shadow,
which is exactly what a model-free harness can drive.

**AC-12 — The docs that AC-3/AC-5 make stale are updated in the same diff.**
`stages/8-code-review.md`'s Dark-reviewer-handling subsection states the void and its
no-retry short-circuit; `review-lead/SKILL.md`'s Step 4b and Rules state the void and the
deliberate override; `review-lean/SKILL.md` states the hand-back. Each is the operative
contract for its own layer, not a restatement of another's.
