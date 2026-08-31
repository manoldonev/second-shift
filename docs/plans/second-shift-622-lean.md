# #622 — the reviewer's unmet-AC blocker gets a structural surrogate

Phase-2 review-rules slice of #605; the promoted disposition of census row `pb-0426581f` (#610).

**Re-cut 2026-08-31.** The amendment gate and its recorded-authority carve-out — the ticket's
original AC-3 and AC-4 — moved to #753 unchanged. This spec is the **scorecard half** only. AC-3
and AC-4 are RETIRED here rather than renumbered, so every citation in the pre-flight receipt and
in the ticket body stays valid and nothing silently re-points. The operator ratified the remaining
scope as a bounded exception to #717's negative-net-diff rule; the two bounds that exception
carries are recorded under "Ratified exception" below.

## The problem

`review-lean`'s rule "an unmet `AC-n` is a blocker" is prose with no enforcement. Nothing scores
an `AC-n`: milestone 1 and `check-lean-chain.sh` assert only that the committed spec carries at
least one numbered `AC-n`, and the per-AC scoring the skill instructs lives as free prose inside
`--summary-file`. So a `verdict=approve` can sit beside an AC the round itself found unmet, or
beside an AC the round never looked at, and no reader anywhere can tell.

A gate cannot judge whether a diff satisfies `AC-3` — that is model judgment and stays with the
reviewer. What a gate *can* refuse is a **self-contradictory record**. That is the whole of this
slice.

## Acceptance Criteria

- AC-1: The verdict record carries a machine-readable per-AC scorecard over a **closed** score
  enum — `satisfied` / `unsatisfied` / `divergent-inert` / `undeterminable`. It is a table under a
  `## AC scorecard` heading with exactly the columns `AC-n | score | evidence`, every cell
  non-empty. Every `AC-n` the committed spec **declares** has exactly one row; a row scoring an
  `AC-n` the spec does not declare is refused, a second row for an id already scored is refused,
  and an unknown score value is an error rather than a miss. `lean-gate.sh verdict` refuses to
  write a record where `verdict=approve` coexists with a bare `unsatisfied` row, with an
  `undeterminable` row, or with a declared `AC-n` that has no row. Selftest covers each arm.
- AC-2: `divergent-inert` is the severity axis, and it is not free: a row scored that way must
  carry **both** a cited impact measurement and a filed follow-up reference, spelled `measured:
  <text>` and `follow-up: <ref>` inside its `evidence` cell, where `<ref>` is `#<n>`, a URL, or a
  tracker key. A row missing either is refused; `approve` stands with well-formed
  `divergent-inert` rows. Selftest covers both arms. (This is the #565 case: measured inert across
  the whole corpus is a warning with an owner, not a round.)
- AC-5: Both layers enforce, the pattern #613 shipped: `lean-gate.sh verdict` at write time, over
  the `--summary-file` body, so the reviewer learns in-session before the round is spent; and
  `lean-evidence.sh` — which `check-lean-chain.sh` already delegates its verdict arms to — over
  the committed record at the merge boundary. A hand-written record that never passed the writer
  is still refused at the boundary, proven by a selftest case that does not go through the writer.
  The validator is **single-sited** in `lean-evidence.sh` and invoked by `lean-gate.sh`; there is
  no second copy and no lockstep pair, because the two layers can reach one implementation.
- AC-6: Prose disposition per P5. The unmet-AC clause of the blocker sentence in
  `review-lean/SKILL.md` — the sentence beginning **"Approve on the diff, not on the spec's
  promises"** — is deleted; the amended-spec clause stays and travels to #753. The step-5 scoring
  instruction is re-pointed at the gate's format and extended with `divergent-inert` and its
  measurement-and-follow-up requirement, because that judgment is the model's and no gate replaces
  it. The `pb-0426581f` row in `docs/prose-blocker-triage.tsv` becomes a `promoted | guard-added |
  <enforcer key>` row under the surviving construct's post-edit census id, naming `pb-0426581f` as
  its predecessor, and a re-run of `bash tools/prose-blockers.sh check` reports zero
  undispositioned constructs.
- AC-7: The obligations existing guards impose are paid in this PR, each discharged **or shown
  inapplicable with the measurement that shows it**: `tools/gate-ablation-classes.tsv` (rows are
  keyed to `milestone-N | attempt|absent` firings in the progress record, so an obligation lands
  only if this contract adds one); `scripts/fail-open-sites.tsv` — NOT `tools/`, which the ticket
  body and the pre-flight receipt's D-13 both misname — whose guard `scripts/check-fail-open-shapes.sh`
  enumerates the single shape `… | grep -q`, so a row is owed only if the new code writes it; and
  `scenario-liveness-selftest.sh`, extended for the verdict path this contract touches with a
  non-vacuity case beside it.
- AC-8: Migration is fail-closed from the release this ships in, and the `Changelog:` trailer says
  so with a `Migration:` line. Only the record at the boundary is ever re-read — merged records
  are never re-graded — so the remedy for an in-flight consumer PR is one re-run of
  `lean-gate.sh verdict`. This PR's own verdict record satisfies the new format: a schema-changing
  PR is graded by the branch's own gate.

*(AC-3 and AC-4 — the amendment gate and the recorded-authority carve-out — are retired to #753.
The ids are not reused.)*

## Design

Design: none — this repo configures no `design.provider`; the change is shell gates, skill prose
and a TSV row, with no rendered surface.

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | What "promoted to a gate" means for a rule whose first half is model judgment | Split. The amended-spec half becomes a real gate. The unmet-AC half gets a STRUCTURAL surrogate: the verdict record carries a machine-readable per-AC scorecard covering every `AC-n` in the committed spec, and `verdict=approve` carrying any bare `unsatisfied` row — or omitting an `AC-n` the spec declares — is refused. The gate never judges satisfaction; it refuses a self-contradictory record and an unscored AC. | user-answered |
| D-2 | What carries the recorded authority that exempts an amendment | DEPARTURE — travels to #753 with the amendment gate. Kept here with its provenance intact because the resolution is unchanged and binding there, not re-decided; this slice touches neither `OVERRIDE_GATES` nor `OVERRIDE_SCOPES`. | user-answered |
| D-3 | The baseline an amendment is measured against — "after the fact" after WHAT | DEPARTURE — travels to #753 with the amendment gate. Resolution unchanged: the reviewed head of the most recent committed verdict record. | user-answered |
| D-4 | Force of the direction test (additive-and-stricter vs narrowing-to-fit) | DEPARTURE — travels to #753 with the amendment gate. Resolution unchanged: automatic exemption on a zero-deleted-line AC-block diff, with the stated proxy trade. | user-answered |
| D-5 | How a measured-inert divergence is recorded, and what the gate does with it | A fourth scorecard value `divergent-inert` beside satisfied / unsatisfied / undeterminable, requiring BOTH a cited impact measurement AND a filed follow-up issue reference. `approve` is permitted with such rows and refused on any bare `unsatisfied`. Adopted on delegation over the operator-override route because the measurement is the REVIEWER's own work — #565's reviewer walked all 63 corpus records — and routing it through an override would make the operator ratify a finding they did not measure, spending a command on every inert divergence. The required follow-up reference is the #465 lesson: a follow-up nobody owns is a follow-up nobody does. | user-delegated |
| D-6 | What an `undeterminable` AC row means on a `verdict=approve` | Refused. The reviewer determines it, scores it `divergent-inert` with a measurement, or hands back. Consistent with the repo's standing posture that an unevaluable answer is never a pass (`operator-override.sh`'s rc=2 is "UNKNOWN — never a negative"; `review-lean` 5c refuses to certify a review that could not run). | user-answered |
| D-7 | Where enforcement runs | DEPARTURE — the enforcement POINTS are exactly as interviewed: `lean-gate.sh verdict` refuses to WRITE a self-contradictory record, so the reviewer learns in-session before the round is spent, and `lean-evidence.sh` — which `check-lean-chain.sh` already delegates its verdict arms to — validates the committed record at the merge boundary. What departs is the receipt's clause "covering CI and milestone 4 together": milestone 4 does not call `lean-evidence.sh`, because #720 deleted its duplicate arms and made the boundary the sole reader of freshness and reconciliation. So milestone 4 gains nothing here — that is #720's rule applied, not a narrowing of this one. | user-answered |
| D-8 | Whether #605 F-C (zero CI has no defined handling) lands in this slice | Out of scope, and deliberately NOT filed as a follow-up. It is a different subject — whether an approve may stand with no build signal, not whether the ACs were met or amended. It stays recorded in #605's evidence section for whichever slice reaches it. | user-answered |
| D-9 | Migration for the 60+ verdict records already carrying the scorecard as free prose | Fail closed from the release it ships in, with a `Migration:` line in the Changelog trailer. Only the record currently at the boundary is ever re-read — merged records are never re-graded — so the blast radius is one re-run of `lean-gate.sh verdict` on an in-flight PR. A grace period would be a fail-open window on the exact arm the gate exists to close, which P2 forbids. | user-answered |
| D-10 | Disposition of the censused prose `pb-0426581f` once the gate ships | DEPARTURE — the disposition is unchanged (delete the blocker sentence per P5, cited by TEXT rather than by line because the anchor has moved three times; keep and EXTEND the scoring instruction with the `divergent-inert` value and its measurement-and-follow-up requirement; move the triage row to `promoted \| guard-added \| <enforcer key>`). What departs is the deletion's EXTENT: only the unmet-AC clause of that sentence goes. The amended-spec clause is #753's construct, and deleting it here would leave that rule with neither prose nor gate. | user-answered |
| D-11 | Predecessor and sequencing | Discharged. #610's PR #625 merged 2026-08-21; `docs/prose-blocker-triage.tsv` exists and carries the `pb-0426581f` row. | codebase-derived |
| D-12 | The refusal message's affordance | DEPARTURE — travels to #753 with the amendment gate; this slice records no override and prints no `operator-override.sh record …` command. | codebase-derived |
| D-13 | Artifact obligations this PR owes, each forced by an existing guard | Three, carried into AC-7 and each measured rather than assumed. (a) `tools/gate-ablation-classes.tsv`. (b) `scripts/fail-open-sites.tsv` — the receipt's corrected path; the ticket body's AC-7 still misnames it `tools/`. (c) `scenario-liveness-selftest.sh`. | codebase-derived |
| D-14 | Self-application on this very PR | A schema-changing PR is graded by the BRANCH's `lean-gate.sh` (#363), so #622's own verdict record must itself carry the structural scorecard. The lane dogfoods the gate it ships in the same run. | codebase-derived |
| D-15 | Duplicate scan | `dup-scan.sh --issue 622` returned rc=0 — no candidates at or above threshold 12. Sibling #624 judged by hand: same parent epic, different surface and different mechanism half — not a duplicate. | codebase-derived |
| D-17 | The scorecard's exact serialization | Resolved at build time under OR-1, bounded by D-1, D-5 and D-6. See "OR-1 disposal" below. | deferred |
| D-18 | What "declared" means, given the gate must enumerate the AC set rather than count mentions | An `AC-n` is DECLARED where its id opens a markdown bullet or a heading, optionally bolded or backticked. Milestone 1's `(^\|[^A-Za-z])AC-[0-9]+` count cannot be reused: it matches every prose mention, so a spec sentence citing `AC-3` would demand a row for an id nothing declares — and this spec's own retirement note names two such ids. Measured against the whole committed corpus: all 16 lean specs in `docs/plans/` declare every one of their ACs in that position, and none declares one anywhere else. A spec that mentions `AC-n` but declares none in that position is REFUSED rather than read as an empty set, which is the vacuity this arm would otherwise ship with. | codebase-derived |

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | The scorecard's exact serialization: section heading, column set, and how an impact measurement and a follow-up reference are spelled | reversible-default-and-flag |

**OR-1 disposal, flagged for the review round.** Nothing consumes the format until this PR ships
it, so the round is where it is disposed. The concrete shape taken:

```
## AC scorecard

| AC-n | score            | evidence                                                    |
| ---- | ---------------- | ----------------------------------------------------------- |
| AC-1 | satisfied        | closed enum + completeness, lean-evidence-selftest (sc1..sc6) |
| AC-2 | divergent-inert  | measured: 0 of 63 corpus records affected; follow-up: #<n>   |
```

Three columns rather than five, with the measurement and the follow-up as tagged sub-fields of
`evidence` rather than columns of their own: separate columns would force every `satisfied` row to
carry two filler cells under the "every cell non-empty" rule the sibling fidelity table already
establishes. The heading and the column names mirror `## Design fidelity evidence` deliberately —
a reviewer writing both reads one grammar.

## Ratified exception (#717)

This ticket predates #717's negative-net-diff stopping rule by nine days. The operator ratified it
as a **bounded** exception after the scope was cut in half. The two bounds are conditions on this
work, recorded here so they are checkable later:

1. **The severity axis must be exercised.** If `divergent-inert` ships and no verdict record in
   the corpus ever scores a row that way, it bought nothing and should be revisited rather than
   kept on principle.
2. **The prose it replaces must actually go.** A gate shipping beside the prose it was supposed to
   retire is the growth #717 names, not a substitution for it. AC-6 is that obligation.

## Out of scope

- The amendment gate, its direction test and its recorded-authority carve-out — #753.
- #605 F-C, "zero CI has no defined handling" — a different subject, recorded in #605.
- The classification register and its coverage guard (phase 2 of the parent epic).
- Mutation-sweep earn-your-keep work (#567).
