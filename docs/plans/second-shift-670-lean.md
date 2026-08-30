# #670 — close-out's merged-PR reachability, and the seven sites that state its rule wrongly

`build-lean/SKILL.md:32` contradicts itself one sentence apart: milestone 5 "a MERGED PR
satisfies as well as an open one (#642)", and "milestone 5 requires an open PR". Found by #644's
ablation (a bare plugin-free session on PR #660's head), absent from that PR's three independent
review rounds, live on `main`.

Two things the pre-flight established that the ticket body does not say.

**The gate is broken, not just the prose.** #642 widened `resolve_open_pr` (`lean-gate.sh:4949`)
to accept OPEN-or-MERGED, but `cmd_5` then calls `cmd_mark` unconditionally and `cmd_mark`
(`:2798`) still resolves with `gh pr list --head "$LEAN_BRANCH" --state open`, returning rc=1 on a
merged PR → `block_milestone 5 "could not stamp the build identity on the PR"`. **Close-out is
still unreachable after a merge**, which is the defect #642 claimed to fix. The `(k7)` selftest
certifying AC-8 passes `--pr-file`, which `cmd_mark` also honors, so the fixture never reaches the
`--state open` call — the case is vacuous against the shape a consumer sends. The liveness suite
would have been blind too: its gh fake (`scenario-liveness-selftest.sh:1643-1650`) discriminates
on the JSON field list, not on `--state`.

**Seven sites carry the stale premise, not one.** #642's AC-9 mandated "every prose statement this
change falsifies is updated" and enumerated four files; the unclaim family was never in it.

## Acceptance Criteria

- **AC-1** (oracle — selftest): `cmd_mark` resolves its PR through `resolve_open_pr`, so an
  open-or-merged PR is found. On a **MERGED** PR it posts nothing — it reports the stamp as moot
  and returns 0 — and milestone 5 therefore passes. Driven through the `GH=<stub>` seam with **no
  `--pr-file`**, so the assertion crosses the `pr list` call a consumer actually makes. A case that
  passes `--pr-file` does not satisfy this AC.
- **AC-2** (oracle — scenario): `scenario-liveness-selftest.sh` carries a leg composing
  BUILD → REVIEW → the operator merges → `close-out` reaches its terminal
  `| milestone-5 | satisfied` write. Entailed and asserted in the leg, in three parts:

  1. the merged PR is resolved over the **live** `gh pr list --state all` call — no `--pr-file`
     anywhere in the composed path, which is the seam that let #642's `(k7)` certify post-merge
     reachability while crossing none of the code that denied it;
  2. **no gate-side `--state open` narrowing is made at all.** After this fix nothing in
     `lean-gate.sh` asks for open PRs; the sole surviving `--state open` line in the fake's log is
     the scheduler's own `resolve_pr` (`orchestrate-lean.sh:731`), classified by the `--jq` it
     always carries. A restored pre-#670 resolver adds a `pr list --state open` with no `--jq`,
     which is what this counts;
  3. the fake's `--state` arm really answers `[]` to an open narrowing where `--state all` gets the
     MERGED record — probed directly, in its own case, and labelled as a **fixture-capability**
     check rather than a claim about the run. It has to be: (2)'s zero says no lane call reaches
     that arm, so nothing else in the suite would notice it rotting, and the leg's power to kill a
     restored resolver rests entirely on it.

  A single log grep for `--state open` does **not** satisfy this AC: it passes in the world it
  names as the failure, because the scheduler's `--jq` query writes that string whatever the arm
  answers.
- **AC-3** (oracle — selftest): the existing `(k7)` case's title claims only what it tests —
  `resolve_open_pr`'s jq state-ordering through the `--pr-file` seam — and no longer asserts
  post-merge reachability, which AC-1's case now owns.
- **AC-4** (doc): no live site asserts that milestone 5 requires an open PR. Oracle, run from the
  repo root:

  ```
  git grep -n -i -E 'requires? an OPEN pr|milestone 5 requires|exit milestone (still )?requires' \
    -- ':!docs/plans/' ':!docs/skill-ablation.md' \
       ':!plugins/intake-toolkit/skills/plan-interview/tools/dup-scan-fixtures/'
  ```

  returns **zero** matches at head (measured). It returns exactly seven at `ff3f6f8` (measured),
  one per site below; the three exclusions are the frozen-record classes AC-5 scopes out, not
  conveniences.

  **The oracle cannot tell an assertion from a quotation**, and the fix is on the doc side rather
  than in the exclusion list. AC-5's own declined-coupling row has to name the falsified claim to
  argue about it; written as a verbatim quote it read to this sweep as an eighth live site.
  `docs/testing.md` therefore states it in indirect speech, and the verbatim text survives only
  where it is dated evidence — in the three excluded classes. Widening the exclusions to
  `':!docs/testing.md'` would have bought the same zero while blinding the sweep to a real
  regression in a live doc.

  | # | Site | Reader |
  | --- | --- | --- |
  | 1 | `plugins/dev-pipeline/skills/build-lean/SKILL.md:32` | the build session executing step 9 |
  | 2 | `.github/workflows/unclaim-on-close.yml:4-5` | a maintainer of this repo |
  | 3 | `plugins/second-shift/templates/consumer/second-shift-unclaim.sh:8` | **shipped to consumers** |
  | 4 | `plugins/second-shift/templates/consumer/second-shift-unclaim.yml:4` | **shipped to consumers** |
  | 5 | `plugins/second-shift/skills/onboard/SKILL.md:370` | spoken aloud at onboarding |
  | 6 | `schema/second-shift.config.schema.json:67` | **published schema** — surfaces in editor tooling |
  | 7 | `docs/onboarding.md:26` | a consumer following onboarding |

  Each re-derives its own justification (D-4): the session never owns the label's release in
  either case — the `issues: [closed]` workflow does. Sites 3, 4 and 6 additionally state the
  open/merged rule correctly where they state it at all.
- **AC-5** (doc): `docs/testing.md`'s *Couplings considered and declined* carries a row for the
  seven-site duplication — what is duplicated, why `LOCKSTEP` is wrong for it, and that the
  frozen-record classes (`docs/plans/`, `docs/skill-ablation.md`, the `dup-scan` corpus fixture)
  are deliberately excluded rather than overlooked.
- **AC-6** (critic): `Changelog:` trailer present, and the commit verb is `fix:` (D-10).
- **AC-7** (oracle): every `tools/mutation-catalog.tsv` row anchored in `lean-gate.sh` still
  applies after the edit — **26 rows, zero drift**, re-derived under the sweep's own `sed -E` and
  byte-identity test (`tools/mutation-sweep.sh:1853,1861`), `lean-gate-mark-session-guard`
  included (D-9). Oracle, from the repo root:

  ```
  g=plugins/dev-pipeline/skills/build-lean/lean-gate.sh
  awk -F'\t' -v g="$g" '$1 !~ /^#/ && $2 == g { print $3 }' tools/mutation-catalog.tsv |
    while IFS= read -r s; do
      sed -E -e "$s" "$g" | cmp -s - "$g" && echo "DRIFT: $s"
    done
  ```

  prints nothing. There is no `tools/mutation-catalog-selftest.sh` — the catalog's own suite is
  `tools/mutation-sweep-selftest.sh`, and the anchor check it wraps is a full sweep, which is why
  the obligation is discharged by re-deriving the seds directly.

## Out of scope, with reasons

- `docs/skill-ablation.md:169-171` — the ablation report quoting the defective sentence. A dated
  measurement record of what the file said on the day the bare session read it; correcting the
  quote destroys the evidence for the finding (D-8).
- `docs/plans/**` — six plan/verdict records quote it as evidence. The same class
  `check-lockstep-pairs.sh` excludes by name, "because the plan doc is SUPPOSED to drift".
- `plugins/intake-toolkit/.../dup-scan-fixtures/corpus-live.json:27` — a dup-scan corpus fixture
  holding a real issue body verbatim. Editing it changes what the dup-scan selftest measures.
- The `m5/identity-stamp` row in `tools/gate-ablation-classes.tsv` — still valid: a genuinely
  absent marker on an OPEN PR fires it, and AC-1 changes no refusal wording.

Design: none — this ticket renders nothing a user looks at; `design.provider` is unconfigured.

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Is #670 prose-only, or does it also fix `cmd_mark`'s `--state open`? | Fix the gate here too. The ticket asks the prose to be re-derived from what the gate asserts today; a prose-only slice would either restate #642's false claim or ship a sentence a sibling ticket immediately rewrites. The two are one subject. | user-answered |
| D-2 | Which prose sites does #670 cover? | DEPARTURE — the receipt names five sites and states the enumeration was verified complete; it is SEVEN. `schema/second-shift.config.schema.json:67` was hidden behind a truncated grep, and `docs/onboarding.md:26` was inspected and wrongly cleared — the clause sits 100 characters into the line. The decision's INTENT is untouched and still governs: every site carrying the premise, because they ship to consumers. Only its enumeration was wrong. Full list in AC-4. | user-answered |
| D-3 | How does the identity stamp behave when the PR is already merged? | `cmd_mark` resolves open-or-merged (reusing `resolve_open_pr`) so it can find the marker step 7 already posted; on a MERGED PR it does **not** post a new one — it reports the stamp as moot and returns 0. Grounding: SKILL.md step 7 states a marker posted after the review's push is invisible to the CI run that gates the merge, and `scripts/check-lean-chain.sh:151` runs on a `pull_request` event, so post-merge its only consumer has already run. Reachability is restored without inventing a write nothing reads. | user-answered |
| D-4 | What justification replaces "milestone 5 requires an open PR"? | The session never owns the label's release in either case: `unclaim-on-close.yml` binds it to the `issues: [closed]` event, and `second-shift-unclaim.sh`'s header states nothing in either lane releases it. Pre-merge the issue is open and the label is correct; post-merge the workflow has already fired. At SKILL.md:32 the true reason is already the sentence that follows — the fix is to delete the false clause and let it stand. | codebase-derived |
| D-5 | Anchor the shared fact, or record the coupling as declined? | DEPARTURE — the receipt's reasoning is adopted unchanged, but its text says "these five are five different arguments" and the count is seven (D-2). Declined-coupling row under `docs/testing.md`'s *Couplings considered and declined*. `check-lockstep-pairs.sh` compares whitespace-collapsed **verbatim** blocks, and these are seven different arguments addressed to different readers — a checklist instruction, a workflow rationale, two shipped-template headers, a spoken onboarding line, a JSON schema description, an onboarding doc; forcing them identical would flatten prose that is deliberately distinct. Sanctioned by the `writing-tests` skill's own routing for a real-but-unanchorable coupling. | user-answered |
| D-6 | What test tier guards the merged-PR close-out path? | Both: a per-tool `lean-gate-selftest.sh` case driving the `GH=<stub>` seam (`:2270-2277`) with a merged PR and **no** `--pr-file`, AND a `scenario-liveness-selftest.sh` leg for BUILD → REVIEW → operator merges → close-out reaching its terminal milestone-5 write. Per `writing-tests`: a new gate contract extends the liveness scenario, and the tier map routes a composed verdict path reaching a terminal write to a scenario. #642 guarded AC-8 per-tool only, which is how the vacuity survived. Entailed: the scenario's gh fake must start discriminating on `--state`, a shared-fixture change other legs see. | user-answered |
| D-7 | What happens to the mislabeled `(k7)` case? | Relabel it to claim only what it tests — `resolve_open_pr`'s jq state-ordering through the `--pr-file` seam — and move the reachability claim to the new live-path case. Deleting it would lose genuine seam coverage; leaving the title would let the next reader be fooled the same way. | user-answered |
| D-8 | Does `docs/skill-ablation.md` §2's quote get updated? | No — out of scope, deliberately frozen. A dated measurement record, the same class `check-lockstep-pairs.sh` excludes `docs/plans/` for. A build session must not "fix" the quote to match the corrected prose; doing so destroys the evidence for the finding. | codebase-derived |
| D-9 | Does editing `lean-gate.sh` re-anchor any mutation-catalog row? | Re-verify before commit. `tools/mutation-catalog.tsv:86` `lean-gate-mark-session-guard` is anchored inside `cmd_mark` on `if ! session_in_build_set "$msid"; then`, which this change does not touch — but CLAUDE.md and `writing-tests` make re-anchoring an ordinary-PR obligation whenever a guard's CODE moves, and catalog anchors are literal seds. Confirm rather than assume. Carried as AC-7. | codebase-derived |
| D-10 | Commit verb and bump level. | `fix:` (patch), plus a `Changelog:` trailer — this is a `plugins/**` PR. #642 already typed the merged-PR widening as the feature; #670 repairs it, so `feat:` would overstate. | codebase-derived |
| D-11 | Do the shipped-template edits require anything of consumers who already installed them? | No. Nothing compares an installed `.claude/tools/second-shift-unclaim.sh` against the shipped template — no drift guard exists — and the edits are comments, so an existing consumer's stale copy diverges in rationale only, with no behavioral difference. Site 6 (`schema/second-shift.config.schema.json`) is read from the marketplace at its pinned ref, so it updates with the release. Migration: none. | codebase-derived |
