# lean review verdict — #769

verdict=approve
run_id: review-769-2
session_id: 20b8ffb7-600d-4268-8c14-2ac0a9e41401
rounds: 2
pr: #773
reviewed_head: 3c9524cc951111e59ee5444dac729def5c3a2210
reviewed_patch_id: 5b34b418c2b0dc36355b1158a9d57f5194ff55bd
inherited_patch_id: f3f14b663bc5832f7a558fea98599863eb5bd05e
inherited_from_verdict: f5ea3ac5bd0d437a4a8c819d09b1a5aa263c8470
fidelity: not-applicable
panel: review-toolkit:scope-completeness-reviewer
model: unknown
capabilities: pr-marker

# Review — #769 / PR #773, round 2

Range reviewed: `f5ea3ac5..HEAD` — the delta `G delta` printed, inheriting the coverage of patch
`f3f14b663bc5` (round 1's record, `docs/plans/second-shift-769-lean-verdict.md`). The delta is one
commit, the base merge `3c9524cc` of `origin/main` (#730): 3 files, 9 insertions / 8 deletions.

Read wider than the range throughout, because the delta is misleading here in a specific way: #730
edits the **same two files** #769 does (`review-lean/SKILL.md`, `review-lead/SKILL.md`), so the
merged text of a paragraph #769 authored is content no round has read. Every AC was re-measured at
`3c9524cc` rather than inherited on the strength of an unchanged file — and two of them (AC-7, AC-9)
had genuinely moved.

Reviewed from the PR head checkout at `3c9524cc`; head re-checked immediately before writing this
record and unchanged.

Prior round's findings read first (round 1, `approve`, 2 suggestions + 2 pre-existing notes). Both
suggestions still stand at this head and are carried forward below; neither was a blocker then or now.

## Verdict

`approve` — no blockers. Three suggestions, two pre-existing notes.

All eleven ACs are `satisfied` at `3c9524cc`. The base merge did **not** damage #769's contribution,
and its conflict resolution is better than either side it came from (see Strengths). The scope gate
returned one blocker-severity finding this round; it does not survive verification, and the
reasoning is recorded in full below so a human reader can overturn it.

## Why this round exists

The base merge is not content-neutral. `check-lean-chain.sh` at this head says so precisely:

> verdict record reviewed patch `f3f14b663bc5`, but this branch's diff against origin/main now
> hashes to `5b34b418c2b0` and the branch's own lines moved with it: 5 reviewed line(s) across
> 2 file(s)

Both sides of the merge edited #769's own `--panel` paragraph and its `prose-blocker-triage.tsv`
row, so the resolution had to author new content on the branch's lines. Round 1's record is
correctly void, and this one replaces it.

## The scope-gate finding, and why it is not a blocker

`scope-completeness-reviewer` returned `request-changes` with one `blocker` (confidence 82):
issue #769's "What it should say" says *"The deadline is the variable to change, not the tier and
not the budget."* Step 4b writes the tier half (`review-lead` SKILL.md:376) and says nothing about
the budget; the reviewer read that as a dropped scope item and pre-empted the mootness argument with
*"the tier is equally unsettable there and was still written."*

Verified against the issue, the tree and the harness. The finding does not hold, on two independent
grounds:

1. **The diff covers the item, because the item is a prohibition.** "Not the budget" is satisfied by
   changing no budget — and no budget is changed anywhere on this branch. The only surface on which a
   turn budget is settable is `code-review.mjs`'s executable code, which AC-11 pins to comment-only
   and which I verified mechanically (filtering `git diff origin/main...HEAD` on that file to changed
   non-comment lines yields zero). This is the diff satisfying a scope item, not a deferral claim.
2. **The clause is not live on the mandated mechanism, and the tier clause is** — which is exactly
   the asymmetry the reviewer denied. Step 4b:369 pins the re-dispatch to the **Agent tool**
   ("dispatch it once more yourself (Agent tool)"), whose parameter set is `subagent_type`, `model`,
   `prompt`, `description`, `run_in_background`, `isolation`. There is a **model** knob — so a
   session really can promote the tier, and `reviewers.modelOverrides` is a second live path, which
   is why SKILL.md:376 had to forbid it. There is **no turn-budget knob**. Writing "and neither is
   the budget" would forbid something the executing session cannot do.

The principle the issue's sentence states is also already in the repo, unchanged by this diff:
`code-review.mjs:306-307` and `:342-343` both carry "the variable is the deadline, not the budget",
with the half-cap `security-reviewer` measurement behind it.

Downgraded to **S-3** below: adding the clause would cost one clause and close the gap for a reader
who checks the issue against the skill. It changes no behavior, and `prose-blockers.sh`'s own census
would later have to disposition it as a construct no gate enforces.

## What was re-measured rather than inherited

**AC-7's paragraph is merged content, and the merge kept both sides.** #730 qualified the engine
name (`review-lead` → `review-toolkit:review-lead`) in the same `--panel` paragraph #769 rewrote.
`git diff f1fa7def..HEAD -- plugins/dev-pipeline/skills/review-lean/SKILL.md` is **exactly** the
AC-7 amendment and nothing else — the #769 semantics survived intact and the #730 qualification was
applied on top. Nothing was dropped in either direction.

**AC-9 is a different measurement than round 1 made.** The merge re-keyed three
`docs/prose-blocker-triage.tsv` rows, so round 1's green was over keys that no longer exist.
Re-run at this head: `bash tools/prose-blockers.sh check` → **rc 0**, "✓ zero undispositioned
constructs" (30 constructs over 52 files; 52 rows). That command's `check()` tests exactly the four
conditions AC-9 names — undispositioned, unpruned, unresolved, stale — so a wrong key would have
red it as undispositioned rather than passing quietly. All three pointers verified exact by hand:
`pb-dd909897` → `:48` (step 5), `pb-ea256f2d` → `:102` (5c), `pb-1c207e51` → `:118` (step 6).

**AC-10's oracle re-run at this head, cited not repeated.** `lint-and-selftests` at
`3c9524cc` — **success**: step 4 `shellcheck` ✓, step 9 sweep **77 scored, 74 run, 3 served from
cache, 0 failed**. The three cached suites are `lean-gate-selftest.sh`, `cost-block-selftest.sh` and
`check-lean-chain-selftest.sh`; I read their `tools/selftest-cache-inputs.tsv` rows and none declares
a file this diff touches, so no suite was served from cache past an edit it grades. `selftests
(macos, bash 3.2)` and `mutation-sweep-pr` also success at the same head. No new selftest was added.

**The merge introduced no wrap regression of its own.** `review-lean/SKILL.md` gains two lines over
100 chars at this head (`:48`, `:102`) — both are byte-identical to `f1fa7def`, i.e. main's, not this
branch's.

**AC-11 re-confirmed mechanically at this head**, not carried: zero changed non-comment lines in
`code-review.mjs`; both `LOCKSTEP` regions outside the edit; CI's contract-lockstep step (job step
11) green.

**The spec-amendment direction test.** AC-11 entered the spec in `7a3df6f4`, the same commit as the
implementation, and the spec discloses it. It *adds* an obligation (comment-only, and the comment
must state three named things) rather than relaxing one, and its content is independently verifiable
— which is the benign direction. Not "a spec amended to match the diff".

## Findings

| # | severity | site | finding |
| --- | --- | --- | --- |
| S-1 | suggestion | `plugins/dev-pipeline/skills/review-lean/SKILL.md:102-104` | *Carried from round 1, unfixed.* 5c's void trigger still reads "the provider's mandatory fidelity reviewer **went dark**", unqualified, while Step 4b-void case 2 now triggers on *still dark after the mandated re-dispatch*. Coherent in substance — 5c delegates the determination outright ("`review-toolkit:review-lead` voids a round in either of two cases") and the same file's `--panel` paragraph names the re-dispatch. Residual only: a session reading 5c in isolation could hand a round back before trying the re-dispatch the mandate requires. |
| S-2 | suggestion | `plugins/review-toolkit/skills/review-lead/SKILL.md:390-397` | *Carried from round 1, unfixed.* The escalation table's last row enumerates exactly D-5's set, but the spawnable panel also contains the design-fidelity reviewer on an **unarmed** spec, which no row names. It is covered by the catch-all at `:397`, so the set is complete by residue rather than by enumeration — the weaker of the two for a table read under time pressure. |
| S-3 | suggestion | `plugins/review-toolkit/skills/review-lead/SKILL.md:376` | *New this round, from the scope gate, downgraded — see the section above.* The issue's "not the tier and not the budget" is written as the tier half only. Extending `:376` to "The tier is not a variable, and neither is the budget" would close the gap for a reader checking the issue against the skill. Non-blocking: the Agent tool the mandate pins to exposes no turn-budget knob, no budget is changed anywhere on this branch, and `code-review.mjs:306-307,342-343` already state the principle. |

## Pre-existing (not this PR's)

- **5c case 1 and Step 4b-void case 1 still disagree about an all-dark selected set.** 5c: "**every**
  reviewer it selected went dark" → hand back. `review-lead`: an all-dark selected set on top of a
  *completed lead pass* is explicitly **not** a void, but a partial-coverage round that answers the
  verdict. Unchanged by this diff and outside #769's scope, but the same interlock family AC-5
  tightened — worth a ticket rather than a rediscovery.
- **`docs/prose-blocker-triage.tsv`'s line-pointer column drifts repo-wide and no gate reads it.**
  `check()` validates ids, not line numbers. `pb-b703544b` points at `:164` against a construct now at
  `:169` (it was `:168` at round 1's head; this merge nudged it one further). Locator quality only —
  `prose-blockers.sh check` is id-keyed and exits 0 either way.

## Merge-boundary state (recorded, not a blocker)

`pr-gates` is red on exactly one step — `lean chain reconciliation`, reporting round 1's record as
patch-stale. That is this round's reason for existing and this record resolves it. The two policy
steps ahead of it in the same job passed: frozen files ✓, `Changelog:` trailer ✓, as did pipeline
chain reconciliation. Every correctness lane is green at `3c9524cc`.

The branch is one commit behind `origin/main` (`9f8a38e7`, #772). That is a mergeability question for
the merge boundary, not a review finding.

## Strengths

- **The merge resolution authored a better provenance note than either side it merged.** Both
  parents re-keyed the `review-lean:118` row and each recorded only its own cause; the resolved row
  (`pb-1c207e51`) records both — "Re-keyed from `pb-802149ba` by two changes that landed together:
  the engine name is now qualified `review-toolkit:review-lead`, and the `--panel` definition now
  counts a reviewer recovered by review-lead Step 4b's mandated re-dispatch. Neither changed what it
  points at." That is the reconciliation the file's contract asks for, done at the one point where
  both causes were visible.
- **The `--panel` conflict was resolved on semantics, not on recency.** #730 touched that paragraph
  for a naming rule and #769 for its meaning; taking "the newer side" would have silently reverted
  AC-7. The merged text carries both.
- **The incoming `review-lead` rule 5 and #769's Step 4b are genuinely orthogonal**, which is not
  luck worth ignoring on a branch that merged a change to the same section: rule 5 governs round-2
  panel *selection*, Step 4b governs *recovery after darkness*. A reviewer narrowed away by rule 4 is
  a Step 4c not-selected, never a coverage gap — the two contracts do not overlap.

## Panel

| Reviewer | Verdict | Findings | Confidence |
| --- | --- | --- | --- |
| Scope Completeness | Request-changes → verified, downgraded to S-3 | 1 | 82 |
| Security | Lead pass — ✅ | 0 | — |
| Performance | Lead pass — ✅ | 0 | — |
| Complexity | Lead pass — ✅ | 0 | — |
| Maintainability | Lead pass — ✅ | 0 | — |
| Test Coverage | Lead pass — ✅ | 0 | — |

`security-reviewer` not selected: no auth / tenancy / session / upload / query-construction surface
in a prose-and-tsv delta, and the repo carries no `.claude/second-shift/review-context/` directory —
neither arm of its trigger fired, so the lead pass owns the dimension. `a11y-reviewer` +
design-fidelity not routed: no changed path matched `stageParams.webComponentGlobs`
(`apps/web/**/*.{tsx,jsx}` — the default, no override declared), and the spec carries no `## Design`
section, so the dimension is unarmed and `fidelity` is `not-applicable`. No reviewer went dark this
round.

## AC scorecard

| AC-n | score | evidence |
| --- | --- | --- |
| AC-1 | satisfied | `review-lead` SKILL.md:362 ("a coverage gap is what remains after the session has *tried*, which is why the re-dispatch below is mandatory before one may be recorded") and :369 ("**Re-dispatch once, in-session, before recording anything — signal 1 only** … dispatch it once more yourself (Agent tool) before writing a `[Coverage gap]` line for it"). Same agent, same tier at :376. The forbidding sentence is absent from the tree — a grep over `plugins/` and `docs/` finds it only inside the spec's own quotation of the old text. Not scoped to pipeline-driven rounds: :369 opens "The fan-out's own retry", carrying no "Under a pipeline-driven review" qualifier. Re-verified at 3c9524cc. |
| AC-2 | satisfied | `review-lead` SKILL.md:373 — turn-numbered emit deadline stated as a **floor**, "Where the agent's own doc already carries a turn-numbered deadline, the doc's number wins". :374 — narrowing to the reviewer's domain, with the reason it is the session's edge ("it dispatched against the whole range"). :376 — "**The tier is not a variable.**" All three at 3c9524cc. |
| AC-3 | satisfied | `review-lead` SKILL.md:378 — "**Signal 2 is out of scope for the mandate.** Under `budgetExhausted` nothing was dispatched, so there is no failed prompt to change and nothing to re-dispatch *differently*; that case keeps the `[Coverage gap]` accounting below, plus Step 4b-void." |
| AC-4 | satisfied | `review-lead` SKILL.md:388-395 — the table's four rows are exactly D-5's set: `scope-completeness-reviewer` hard No ("Step 4's rule, unchanged"), `security-reviewer` hard No with the grounding quoted from :243 ("Security defers when it is spawned"), armed-spec design fidelity → void, and the four named reviewers + `reviewers.add` adds → visibility. :388 states the set is fixed, not consumer-configurable (OR-1's shipped default). |
| AC-5 | satisfied | `review-lead` SKILL.md:407-410 — still **two** cases, not three; case 2 now carries `pre-dispatch` and `post-dispatch` sub-bullets, the latter reading "dispatched, went dark by `died-after-retry`, and was **still dark after** the Step 4b re-dispatch … the same hole the pre-dispatch case names". The armed-spec section at :214 states the pre-dispatch void and reads consistently with it. |
| AC-6 | satisfied | `review-lead` SKILL.md:380 — "**When the re-dispatch succeeds**, the reviewer is **not** a coverage gap: score its findings like any other reviewer and give its Verdicts row its real verdict. Record the recovery in one **Review Summary** line naming the reviewer, that it went dark, and that an in-session re-dispatch recovered it", with a worked example. Still-dark keeps `Dark (no output)` at :384. |
| AC-7 | satisfied | **Re-measured at 3c9524cc, not inherited** — the base merge edited this exact paragraph. `review-lean` SKILL.md:125-132 reads "the round actually **obtained a usable result from — whether from the fan-out or from a `review-toolkit:review-lead` Step 4b re-dispatch**", and "a reviewer that is **still** dark after the mandated re-dispatch is absent from it". `git diff f1fa7def..HEAD` on this file is exactly this amendment and nothing else, so the merge preserved #769's semantics while applying #730's name qualification. |
| AC-8 | satisfied | `docs/testing.md:966-982`, under "Couplings considered and declined": names the three sites (Step 4b, Step 4b-void case 2, `review-lean` 5c), states the coupling is real, records **no guard added**, and gives both reasons — a prose-presence grep is forbidden by `writing-tests` because "it passes on the day the sentence is deleted and re-added verbatim with its meaning inverted around it", and `LOCKSTEP` needs byte-identical blocks these three deliberately are not. Marks itself "Reviewer-guarded". |
| AC-9 | satisfied | **Re-measured at 3c9524cc** — the merge re-keyed three rows, so round 1's green was over keys that no longer exist. `bash tools/prose-blockers.sh check` → rc 0, "✓ zero undispositioned constructs" (30 constructs / 52 files / 52 rows). `check()` tests exactly the four conditions this AC names, and a wrong content-derived key reds as undispositioned rather than passing. Pointers verified by hand: `pb-dd909897`→`:48`, `pb-ea256f2d`→`:102`, `pb-1c207e51`→`:118`, all exact. |
| AC-10 | satisfied | CI oracle at this exact head, cited rather than re-run (command and head both match): job `lint-and-selftests` at `3c9524cc` **success** — step 4 `shellcheck` ✓; step 9 `run all selftests` "summary: 77 scored, 74 run, 3 served from cache, 0 failed". The 3 cached suites (`lean-gate`, `cost-block`, `check-lean-chain`) declare no file this diff touches in `tools/selftest-cache-inputs.tsv`, so the green is not a cached green. `selftests (macos, bash 3.2)` and `mutation-sweep-pr` also success at `3c9524cc`. No new selftest file added on the branch. |
| AC-11 | satisfied | **Re-confirmed mechanically at 3c9524cc.** Filtering `git diff origin/main...HEAD -- plugins/dev-pipeline/workflows/code-review.mjs` to changed non-comment lines yields **zero**. The rewritten comment (`:214-229`) states all three required things: that the one-shot retry is BIT-IDENTICAL, that the SESSION must re-dispatch once with a changed prompt (numbered deadline + narrowing), and that a surviving gap is a NOTE for most reviewers, a hard "Ready to merge? = No" for security, and a VOID for armed-spec fidelity. Both `LOCKSTEP` regions sit outside the edit and CI's contract-lockstep step is green. |
