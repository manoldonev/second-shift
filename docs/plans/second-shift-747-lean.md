# second-shift #747 — arm 2a: `review-lean` vs. the built-in `/code-review`

#644's scope item 2 named **"`review-lean` vs. the built-in `/code-review`"**. What ran was a
plugin-free session on the generic instruction at
[`c2-review/prompt-template.txt`:5](skill-ablation/c2-review/prompt-template.txt) — no review
skill, built-in or otherwise. The substitution entered at registration time and is declared at
[`docs/skill-ablation.md`](../skill-ablation.md) §2, operator-ratified on #671.

The 0.80 recall **stands as measured**; it is a bare-vs-kit number. What exists nowhere in the tree
is `review-lean` against `/code-review`. This slice runs that comparator, on the frozen sample,
against the frozen oracle, under the invocation
[`docs/skill-ablation-addendum.md`](../skill-ablation-addendum.md) §B registered before any of it
ran.

The registration is **not edited here.** A challenger, a capture rule or a threshold changed after
a result exists is the post-hoc rubric §B exists to prevent, so this slice's only writes are
results and the report sections that carry them.

## Acceptance criteria

Derived at intake — #671 carries no numbered criteria of its own; these are the issue's AC set
verbatim in substance.

- **AC-1** — The three registered C2 samples run at their registered heads, unchanged: #654 @
  `cfba102`, #657 @ `f8f7c14`, #660 @ `642a6b1`.
- **AC-2** — The challenger is the built-in `/code-review`, invoked exactly as registered in
  `docs/skill-ablation-addendum.md` §B — same command, model tier and effort level for all three
  samples. The realised invocation is recorded with each transcript.
- **AC-3** — Scored against the same five ground-truth blockers and the frozen C2 rule at
  `docs/skill-ablation-pre-registration.md`:146-161, unchanged: a hit names the same mechanism
  **and** the same consequence; the same file with a different defect is a miss. Every near-miss is
  quoted verbatim and adjudicated in the report, so a reader can repudiate the call rather than take
  it on trust.
- **AC-4** — All three transcripts committed verbatim under `docs/plans/skill-ablation/c2-review/`,
  one file per session, under a name distinct from the existing `bare-<pr>-review.md` family. That
  directory's `README.md` gains a line describing the new family.
- **AC-5** — `docs/plans/skill-ablation/c2-review/scoring.tsv` carries the new arm's per-blocker
  adjudication alongside the existing `bare_result` column, and `docs/skill-ablation.md` §2 and §4's
  `dev-pipeline/review-lean` row carry the outcome — **either** a measured
  `review-lean`-vs-`/code-review` basis **or** an explicit no-basis record. §4 must no longer
  describe this comparison as simply unmeasured.
- **AC-6** — Blockers the challenger raises that are absent from the lane's own review rounds are
  recorded separately, as the predecessor did for the bare arm, and are not folded into recall.
- **AC-7** — `plugins/dev-pipeline/skills/review-lean/SKILL.md` is not edited.

## Out of scope

- **Executing the cut** — deferred to a successor of #671.
- **The attribution pass** — #748, which consumes this ticket's output as the comparator it
  localises against.
- **P10 independence** — a lane property, not prose, and registered as recorded-not-scored.
- **Editing `docs/skill-ablation-pre-registration.md`** — frozen, one commit, and what #644's AC-1
  is scored on.
- **Editing `docs/skill-ablation-addendum.md`** — the registration this slice is graded by. Editing
  it here, with results in hand, is the post-hoc rubric it exists to prevent (D-11). Where the
  registration turns out to be unevaluable, this slice records that as a finding and routes it,
  rather than amending it.
- **`plugins/dev-pipeline/skills/review-lean/SKILL.md`** — AC-7.

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Whether the C2 clones carry the arm-1 substrate, i.e. `plugins/` deleted from the working tree | No. `docs/skill-ablation-addendum.md` §B "Target pinning" registers exactly two construction facts — the default branch hard-reset to the pinned base and `<branch>` at the pinned head — and no removal. §A's removal is scoped to arm 1 by its own heading and exists so a build PLAN cannot read the kit; here the kit files ARE the diff under review (`lean-gate.sh` on C2-a and C2-c), so deleting them would starve the challenger on its own subject, against every bias §B registers | codebase-derived |
| D-2 | Whether `plugins/` present re-opens the discovery leak §A closed | No. §A measured that `--setting-sources ''` yields `SECONDSHIFT:no` with every `SKILL.md` present, so no second-shift skill loads either way. The residual risk is a FILE-READING leak — the challenger reading `review-lean/SKILL.md` for context — so this slice MEASURES it per capture and reports it rather than assuming either way | codebase-derived |
| D-3 | The transcript file-name family | `codereview-<pr>-review.md`, one per session, alongside the existing `bare-<pr>-review.md`. AC-4 requires only that it be distinct; naming it for the challenger keeps the two arms readable side by side in one directory listing | codebase-derived |
| D-4 | What composes the challenger's finding set | The union registered at §B "The output shape": the report tool's input (the `ReportFindings` `tool_use` payload) and the findings in the final assistant text, deduplicated on same-mechanism-and-same-consequence — the frozen hit rule's own predicate. No severity filter and no scorer judgment about which findings were really blockers | codebase-derived |
| D-5 | The completeness gate on each capture | `tools/classify-capture.sh` (#779) runs before any finding is read out of a capture. Only exit 0 is scored; a `TRUNCATED` capture or a completed failure is discarded and the sample re-run, never recorded as a null result. §B registers this rule and applied it to its own re-validation | codebase-derived |
| D-6 | How the `scoring.tsv` schema grows | Two columns appended, `codereview_result` and `codereview_adjudication`, leaving `bare_result` and `adjudication` untouched in place. AC-5 says alongside; rewriting the bare arm's columns would re-key a committed measurement this slice did not take | codebase-derived |
| D-7 | Which recall governs C2's verdict if the challenger scores below the bare arm's 4/5 | The higher of the two, per §B "Scoring". Both numbers are reported, and the directional argument at `docs/skill-ablation.md`:131-136 is reported as FALSIFIED rather than quietly dropped | codebase-derived |
| D-8 | The comparison set for AC-6 | Every committed round record of the sample's own PR, not round 1 alone. The predecessor scored the bare arm's escapes against rounds 1, 2 and 3 of #660, and a narrower set would inflate the escape count | codebase-derived |
| D-9 | Disposition of §B's post-run assertion when a report names no range at all | Recorded as UNEVALUABLE for that sample, never as a pass and never as the registered discard. The assertion discards a run whose report names ANY OTHER range; silence is not another range. #777's spec already flagged this gap as unclosed by the amended capture; this slice reports what each report did say and routes it rather than re-registering it | codebase-derived |
| D-10 | Running the three samples concurrently on one machine | Accepted. Nothing in §B pins serialisation, each sample is an independent process against its own clone, and the registered pre-run and post-run assertions are per-sample. Recorded so a reader can repudiate it | codebase-derived |
| D-11 | What this slice does when the registration proves unevaluable or wrong | Report it, route it, and leave the registration unedited. Amending §B with results in hand is exactly the post-hoc rubric it exists to prevent, and #777 set the precedent that an amendment is its own ticket, landing before the arm it governs | codebase-derived |
| D-12 | Whether the run id of the earlier claim on this issue is reused | Yes. The issue carries a bot `lean-claimed` marker from run `20260901T193516Z-90957` whose worktree and progress record are gone. `check-lean-chain.sh` reads the FIRST in-window claim comment as the build run identity, so minting a fresh id would bind the merge boundary P10 check to a dead session instead of this one | codebase-derived |
| D-13 | What the finding set is when a capture carries more than one `result` event — a shape §B does not describe | The union over EVERY `result` body plus the report payload, deduplicated on the frozen hit rule's predicate. All three captures carry 2-5 `result` events with the primary finding set in the FIRST, so §B's literal "the findings in the final assistant text" would discard the bulk of every sample — the exact loss mode the amended capture exists to close. Resolved in §B's own registered bias direction, since the union can only enlarge the challenger's set, and reported in §2 rather than folded in silently. §B is not edited (D-11) | codebase-derived |
| D-14 | The evidentiary weight of the AC-6 escape set | Recorded as RAISED, not as CONFIRMED LIVE, and said so in §2. The predecessor verified its two escapes against `main` before filing; at 75 escapes that verification is not in any AC here and would be a slice of its own. The frozen table reads the false-blocker count only on a 5/5 run, which neither arm reached, so nothing downstream consumes it as a number | codebase-derived |

## Open Regions

None. Every input this slice consumes — challenger, invocation, capture rule, sample, oracle, hit
rule and threshold table — was fixed in a committed registration before it ran, and the two
judgments the registration left open (D-1, D-9) are resolved from its own text rather than parked.
