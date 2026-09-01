# lean review verdict — #769

verdict=approve
run_id: review-769-1
session_id: d7681a85-ce19-429c-8c0b-056d40df2541
rounds: 1
pr: #773
reviewed_head: a804b0411a3f7a218c2027eb9a086c3eba10444c
reviewed_patch_id: f3f14b663bc5832f7a558fea98599863eb5bd05e
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
panel: review-toolkit:scope-completeness-reviewer
model: opus
capabilities: pr-marker

# Review — #769 / PR #773, round 1

Range reviewed: `08853051..a804b041` — the whole branch diff (`G delta` printed the FULL range;
nothing verifiable to inherit, root round). Six files, 206 insertions / 17 deletions.
Read wider than the range where it was misleading: `plugins/review-toolkit/skills/review-lead/SKILL.md`
whole (the escalation set has to be scored against the full spawnable panel, not the hunk),
`plugins/review-toolkit/scripts/check-emit-deadline.sh` and `code-review.mjs`'s `BOUNDED_EXPLORATION`
(to falsify D-2's and D-11's grounding claims), and `tools/selftest-cache-inputs.tsv` plus the CI
log (to establish that the green sweep is not a cached one).
Reviewed from the PR head checkout at `a804b041`; head re-checked at the close of the round and
unchanged.

## Verdict

`approve` — no blockers. Two suggestions, two pre-existing notes.

All eleven ACs are `satisfied`. This is a prose-contract change with one comment-only `.mjs` edit;
the two claims that could have been decorative — that the substrate's retry is bit-identical, and
that the emit deadline alone is now a no-op — were both checked against the code rather than taken
from the spec.

## What was verified rather than read

**The "deadline alone is a no-op" premise (D-2) is true.** `code-review.mjs:318-330`'s
`BOUNDED_EXPLORATION` carries `HARD EMIT DEADLINE: by your 8th tool call at the latest`, and it is
appended on the generic dispatch branch (`code-review.mjs:476`). So a session re-dispatch that
added only a numbered deadline would be re-sending the prompt that died. That is what makes the
**narrowing** requirement load-bearing rather than a second belt — and the SKILL text says so in
those terms, generalized (`the reviewers whose dispatch nudge already carries one`) instead of
hardcoding a count that would rot.

**The `security-reviewer` escalation is grounded in a contract already in the file, not asserted.**
`review-lead` SKILL.md:243 — "Security defers when it is spawned. When the security conditional
fires, the lead pass's security section is not run." A dark `security-reviewer` therefore leaves
the dimension covered by nobody, which is materially different from a dark `complexity-reviewer`
whose dimension the lead pass collapsed. The new table row (`:393`) cites that sentence verbatim.

**The `check-emit-deadline.sh` citation resolves.** It exists at
`plugins/review-toolkit/scripts/check-emit-deadline.sh`, and its rules 1-4 do hold the turn number
in the agent frontmatter and doc, which is what `docs/testing.md:980-981` claims about it. The
"free to be later than the floor" phrasing is an inference from that lint rather than a quotation
of it — accurate in effect (rule 3 caps `D <= ceil(2N/3)`, so a per-agent number is bounded above,
not unbounded), and harmless either way, since a doc number *earlier* than a session floor is a
stricter emit deadline.

**The comment edit is comment-only.** Filtering the `code-review.mjs` hunk to non-`//` changed
lines leaves zero. The two `LOCKSTEP` blocks in that file (`:105-134` findings-schema, `:359-370`
progressive-emit) are both outside the edited range, and CI's contract-lockstep step is green.
`null-reviewer-selftest.mjs` Case F reads this file as text but pins dispatch tokens, none of which
sit in the edited comment.

**The green sweep is not a cached green.** CI `lint-and-selftests` at this head discovered 78
suites, excluded 1, ran 77, and cache-skipped exactly three — `lean-gate-selftest.sh`,
`cost-block-selftest.sh`, `check-lean-chain-selftest.sh`. None of the three declares any file this
diff touches in `tools/selftest-cache-inputs.tsv`, so no suite was served from cache past an edit
it grades.

## Findings

| # | severity | site | finding |
| --- | --- | --- | --- |
| S-1 | suggestion | `plugins/dev-pipeline/skills/review-lean/SKILL.md:102-104` | 5c's void trigger still reads "the provider's mandatory fidelity reviewer **went dark**", unqualified, while Step 4b-void case 2 now triggers on *still dark after the mandated re-dispatch*. Coherent in substance — 5c delegates the determination outright ("`review-lead` voids a round in either of two cases") and the same file's `--panel` paragraph was amended to name the re-dispatch — so the only residual is a session reading 5c in isolation handing back a round one re-dispatch early. D-9 decided this deliberately and the spec's Out-of-scope section names it; recorded, not required. (`scope-completeness-reviewer`, confidence 82.) |
| S-2 | suggestion | `plugins/review-toolkit/skills/review-lead/SKILL.md:390-397` | The escalation table's last row enumerates `db-reviewer`, `pipeline-reviewer`, `a11y-reviewer`, `unit-test-mutation-reviewer` and `reviewers.add` adds — exactly D-5's set — but the spawnable panel also contains **the design-fidelity reviewer on an UNARMED spec**, which no row names. It is covered, by the catch-all at `:397` ("Outside those first three rows…"), so the set is complete; it is complete by residue rather than by enumeration, which is the weaker of the two for a table a session reads under time pressure. |

## Pre-existing (not blocking this PR)

- **`review-lean` 5c case 1 vs `review-lead` Step 4b-void case 1 disagree on what an all-dark
  selected set means.** 5c: "**every** reviewer it selected went dark" → hand back. `review-lead`:
  an all-dark selected set on top of a *completed lead pass* is explicitly **not** a void, but a
  partial-coverage round that still answers the verdict. A round in that shape would be handed back
  by 5c and reported normally by `review-lead`. Unchanged by this diff — 5c's text is byte-identical
  to base — and outside #769's declared scope, but it is the same interlock family AC-5 tightened,
  so it is worth a ticket rather than a rediscovery.
- **`docs/prose-blocker-triage.tsv`'s line-pointer column drifts repo-wide and no gate reads it.**
  At base, `pb-d06a8f2a` pointed at `review-lead/SKILL.md:178` while the construct sat at `:196`;
  `pb-85e129b1` pointed at `:140` against `:166`. This PR moves one previously-exact row out of
  true (`pb-b703544b`, `:164` → construct now at `:168`) while correctly re-keying and re-pointing
  the row whose content it actually changed (`pb-802149ba` → `pb-57405123`, `:118`, exact).
  `prose-blockers.sh check` is id-keyed and exits 0 either way, so this is a locator-quality note
  about the file's convention, not an AC-9 miss.

## Strengths

- **The premise it overturns is falsified with a measurement, not an argument.** "The substrate
  already retried once" was the stated reason the old rule existed; the PR shows the retry is
  bit-identical and that an 87-second re-dispatch recovered the dimension, which is what makes the
  rule change a correction rather than a preference.
- **The escalation set is conditional where the evidence is conditional.** Converting a blanket
  visibility note into a blanket hard-No would have been the easy over-correction; grading it by
  which dimension is actually left uncovered — and grounding the `security-reviewer` row in the
  lead pass's own deferral clause — is the harder and right shape.
- **AC-5 widens an existing case instead of adding a third.** A pre-dispatch and a post-dispatch
  fidelity hole are the same hole, and the diff says so in one place rather than growing the void
  taxonomy.
- **The declined guard is declined honestly.** `docs/testing.md`'s new entry states the coupling is
  real, names why both available mechanizations are wrong here (a prose-presence grep passes the day
  the sentence is inverted; `LOCKSTEP` needs byte-identical blocks these three deliberately are
  not), and records "reviewer-guarded" as the disposition — rather than adding a guard that cannot
  fail for the reason it exists.
- **Incidental cleanup:** the replaced `code-review.mjs` comment cited `stages/8-code-review.md`,
  which no longer exists anywhere in the tree. The rewrite drops the dangling reference.

## Panel

| Reviewer | Verdict | Findings | Confidence |
| --- | --- | --- | --- |
| Scope Completeness | Pass (approve-with-nits) | 1 | 82 |
| Security | Lead pass — ✅ | 0 | — |
| Performance | Lead pass — ✅ | 0 | — |
| Complexity | Lead pass — ✅ | 1 (S-2) | 75 |
| Maintainability | Lead pass — ✅ | 0 | — |
| Test Coverage | Lead pass — ✅ | 0 | — |

`security-reviewer` not selected: no auth / tenancy / session / upload / query-construction surface
in a prose-and-comment diff, and the repo carries no `.claude/second-shift/review-context/`
directory — so neither arm of its trigger fired, and the lead pass owns the dimension.
`a11y-reviewer` + design-fidelity not routed: no changed path matched
`stageParams.webComponentGlobs` (`apps/web/**/*.{tsx,jsx}`, the default — the repo declares no
override), and the spec carries no `## Design` section, so the round is unarmed.
`db-reviewer`, `pipeline-reviewer`, `unit-test-mutation-reviewer`: triggers did not fire. No
reviewer went dark, so there is no coverage gap and no re-dispatch was owed.

## Merge-boundary state (recorded, not a blocker)

`pr-gates` is red on exactly one step — `lean chain reconciliation`, "no committed verdict record
(a file named `*-769-lean-verdict.md`)". That is this record's absence, which this round is what
resolves; the two policy steps ahead of it in the same job (frozen files, `Changelog:` trailer)
both passed before it failed. Every correctness lane is green at `a804b041`:
`lint-and-selftests` SUCCESS, `selftests (macos, bash 3.2)` SUCCESS, `mutation-sweep-pr` SUCCESS.

## AC scorecard

| AC-n | score | evidence |
| ---- | ----- | -------- |
| AC-1 | satisfied | `review-lead` SKILL.md:372 — "**Re-dispatch once, in-session, before recording anything — signal 1 only** … dispatch it once more yourself (Agent tool) **before writing a `[Coverage gap]` line for it**", reinforced at `:362` ("a coverage gap is what remains after the session has *tried*, which is why the re-dispatch below is mandatory before one may be recorded"). Same agent type and tier fixed at `:376`. The forbidding sentence is gone: a recursive grep over `*.md` and `*.mjs` outside `docs/plans/` for either half of it — "do not re-dispatch a dark reviewer yourself" and "already retried a dark reviewer once on-substrate" — returns nothing. Not scoped to pipeline-driven rounds: the mandate paragraph carries no "Under a pipeline-driven review" qualifier, which is exactly what the deleted sentence had (D-1, D-12). |
| AC-2 | satisfied | `:374` bullet 1 — turn-numbered emit deadline, "stated as a **floor**. Where the agent's own doc already carries a turn-numbered deadline, the doc's number wins" (D-11). `:375` bullet 2 — "**Narrowing to that reviewer's domain**, using the diff context you already hold. This is the part the substrate cannot do: it dispatched against the whole range". Both declared non-optional at `:373` ("neither is optional"). Tier stated as not a variable at `:376`, with the reason (a promoted model is a different review, not a recovery). D-2's premise independently confirmed against `code-review.mjs:318-330` + `:476`. |
| AC-3 | satisfied | Scoping is in the heading itself (`:372`, "— signal 1 only") and restated at `:378`: "**Signal 2 is out of scope for the mandate.** Under `budgetExhausted` nothing was dispatched, so there is no failed prompt to change and nothing to re-dispatch *differently*; that case keeps the `[Coverage gap]` accounting below, plus Step 4b-void." The reason AC-3 requires is present, not just the exclusion (D-3). |
| AC-4 | satisfied | `:388-395` — a four-row table headed "What a still-dark reviewer costs depends on which one it is", explicitly "fixed here, not consumer-configurable". Rows match D-5 one for one: `scope-completeness-reviewer` hard No citing Step 4 as unchanged; `security-reviewer` hard No naming the grounding ("the lead pass **did not run** its own security section precisely because this reviewer was spawned") — verified against `:243`; armed-spec design fidelity → void; `db-reviewer`/`pipeline-reviewer`/`a11y-reviewer`/`unit-test-mutation-reviewer`/`reviewers.add` → visibility. Not a blanket rule in either direction (D-4). See S-2 for the one member of the spawnable set covered by the `:397` catch-all rather than by a row. |
| AC-5 | satisfied | `:405-410` — still **two** cases, not three. Case 2 now reads "The design-fidelity dimension **produced nothing** on an armed spec … Two ways in, and the void does not distinguish them", with sub-bullets for pre-dispatch (toolkit-absent, detected at Routing) and post-dispatch (dispatched, `died-after-retry`, still dark after the Step 4b re-dispatch), plus "Do the re-dispatch first — a recovered fidelity reviewer is not a void, it is coverage." The armed-spec section at `:214` was amended to agree: "**Toolkit-absent is the pre-dispatch way in, not the only one** … voids the round on the same ground — see Step 4b-void case 2." Same dimension, same armed condition (D-8). |
| AC-6 | satisfied | `:380` carries all four required clauses: the recovered reviewer is "**not** a coverage gap"; "score its findings like any other reviewer and give its Verdicts row its real verdict"; "Record the recovery in one **Review Summary** line naming the reviewer, that it went dark, and that an in-session re-dispatch recovered it", with a worked example; and "It also counts as a returned result for `review-lean`'s `--panel` key." Still-dark reviewers keep `Dark (no output)` at `:385` (D-7). |
| AC-7 | satisfied | `review-lean` SKILL.md:125-133 — `--panel` is now "the reviewer agent types the round actually **obtained a usable result from — whether from the fan-out or from a `review-lead` Step 4b re-dispatch**", read "off those results and not off your selection". Anti-overclaim intent preserved verbatim: "a reviewer that is **still** dark after the mandated re-dispatch is absent from it, which is what makes the key worth reading." The armed-spec rationale D-6 gives is stated in place ("omitting it would have the armed-spec refusal below reject a round whose fidelity coverage the mandate had just recovered"). No gate change was needed or made: `lean-gate.sh`'s panel arm and its `lean-gate-panel-mandatory-reviewer` mutation-catalog row are untouched by this diff, and a recovered reviewer genuinely did return a result, so admitting it does not weaken the refusal. |
| AC-8 | satisfied | `docs/testing.md:966-981`, under `### Couplings considered and declined` (heading at `:891`; `awk` over 891-995 finds no intervening heading, so the entry is inside the section). Names all three sites, asserts the coupling is real ("loosen the mandate and 5c's trigger stops matching what `review-lead` can produce"), declines the guard, and gives both reasons AC-8 requires — the prose-presence grep "passes on the day the sentence is deleted and re-added verbatim with its meaning inverted around it, so it cannot fail for the reason it exists", and `LOCKSTEP` "needs byte-identical blocks — and these three deliberately are not". Disposition recorded as **reviewer-guarded** (D-10). |
| AC-9 | satisfied | `bash tools/prose-blockers.sh check` run by this review from the `a804b041` checkout: "census: 30 construct(s) over 52 file(s); record: 52 row(s)" … "✓ zero undispositioned constructs", rc=0. The one row the Step 4b/`--panel` edits re-keyed is reconciled in the same PR: `pb-802149ba` → `pb-57405123`, pointer updated to `review-lean/SKILL.md:118`, which matches the live census exactly, and the note records the re-key and its origin. Not run in CI (`ci.yml:171-172` records prose-blockers.sh as deliberately unwired there), so this is an execution at the reviewed head, not a cited run. See the pre-existing note on the file's locator column, which the check is id-keyed and does not read. |
| AC-10 | satisfied | Cited, not re-run — same commands, same head (`docs/testing.md`, "Citing a CI run instead of re-running it"). CI run 33541959137 at `a804b041`: `lint-and-selftests` job 99970127459 **SUCCESS**, whose shellcheck step is CLAUDE.md's exact recursive `find` over `*.sh` piped into `xargs -0 shellcheck -e SC1091,SC2015,SC2181`, and whose sweep step is `tools/run-selftests.sh --full --exclude tools/install-topology-selftest.sh` — "78 discovered, 1 excluded, 77 to run"; `selftests (macos, bash 3.2)` job 99970127292 **SUCCESS**; `mutation-sweep-pr` job 99970127555 **SUCCESS**. The cache does not weaken the citation: exactly three suites were served from it (`lean-gate`, `cost-block`, `check-lean-chain`), and no row of `tools/selftest-cache-inputs.tsv` declares any file in this diff as an input to any of them. No new selftest is added (`git diff --stat` adds no selftest file), and no guard is weakened — both `LOCKSTEP` regions of `code-review.mjs` are outside the edited hunk and CI's contract-lockstep step is green. |
| AC-11 | satisfied | `plugins/dev-pipeline/workflows/code-review.mjs:214-226`. **Comment-only, mechanically:** filtering the file's hunk to changed lines that are not `//` comments yields zero lines. Content states all three things AC-11 asks for — the substrate retry "is BIT-IDENTICAL (same prompt, same tier), so against the maxTurns-with-no-text death it is close to deterministic and both attempts die alike"; "the SESSION must re-dispatch once with a changed prompt — a turn-numbered emit deadline and a narrowing to that reviewer's domain, which is the part this file cannot do because it dispatched against the whole range"; and the graded consequence, "a NOTE for most reviewers, but a hard 'Ready to merge? = No' for security … and a VOID for design fidelity on an armed spec". The stale "a NOTE" framing is gone. S-10 intact. |

## Open Regions

| OR-n | region | disposition |
| ---- | ------ | ----------- |
| OR-1 | Whether the D-5 escalation set is consumer-configurable, so a repo-local `reviewers.add` domain reviewer could opt into hard-No | resolved — reversible-default-and-flag accepted. The shipped default is the fixed set, stated as fixed at `review-lead` SKILL.md:388, and adding a config key later is purely additive, so no consumer can have depended on its absence. Correctly flagged in the PR body rather than having paused the build. Not a blocker. |
