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
  `| milestone-5 | satisfied` write. Entailed and included: the suite's gh fake discriminates on
  `--state`, so an `--state open` call no longer receives the record an `--state all` call gets.
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

  returns **zero** matches. It returns exactly seven at `ff3f6f8` (measured), one per site below;
  the three exclusions are the frozen-record classes AC-5 scopes out, not conveniences.

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
  applies after the edit — `tools/mutation-catalog-selftest.sh` green, and the
  `lean-gate-mark-session-guard` sed re-checked by hand against the edited `cmd_mark` (D-9).

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
| D-2 | Which prose sites does #670 cover? | Every site carrying the premise. **AMENDED at build time — the pre-flight said five and verified the enumeration; it was seven.** `schema/second-shift.config.schema.json:67` was hidden by a truncated grep, and `docs/onboarding.md:26` was inspected and wrongly cleared — the clause sits 100 characters into the line. The decision's intent (all of them, because they ship to consumers) is unchanged and governs; only its enumeration was wrong. Enumerated in AC-4. | user-answered |
| D-3 | How does the identity stamp behave when the PR is already merged? | `cmd_mark` resolves open-or-merged (reusing `resolve_open_pr`) so it can find the marker step 7 already posted; on a MERGED PR it does **not** post a new one — it reports the stamp as moot and returns 0. Grounding: SKILL.md step 7 states a marker posted after the review's push is invisible to the CI run that gates the merge, and `scripts/check-lean-chain.sh:151` runs on a `pull_request` event, so post-merge its only consumer has already run. Reachability is restored without inventing a write nothing reads. | user-answered |
| D-4 | What justification replaces "milestone 5 requires an open PR"? | The session never owns the label's release in either case: `unclaim-on-close.yml` binds it to the `issues: [closed]` event, and `second-shift-unclaim.sh`'s header states nothing in either lane releases it. Pre-merge the issue is open and the label is correct; post-merge the workflow has already fired. At SKILL.md:32 the true reason is already the sentence that follows — the fix is to delete the false clause and let it stand. | codebase-derived |
| D-5 | Anchor the shared fact, or record the coupling as declined? | Declined-coupling row under `docs/testing.md`'s *Couplings considered and declined*. `check-lockstep-pairs.sh` compares whitespace-collapsed **verbatim** blocks, and these are seven different arguments addressed to different readers (a checklist instruction, a workflow rationale, two shipped-template headers, a spoken onboarding line, a JSON schema description, an onboarding doc); forcing them identical would flatten prose that is deliberately distinct. Sanctioned by `writing-tests`'s own routing for a real-but-unanchorable coupling. | user-answered |
| D-6 | What test tier guards the merged-PR close-out path? | Both: a per-tool `lean-gate-selftest.sh` case driving the `GH=<stub>` seam with a merged PR and **no** `--pr-file`, AND a `scenario-liveness-selftest.sh` leg for BUILD → REVIEW → merge → close-out's terminal milestone-5 write. Per `writing-tests`: a new gate contract extends the liveness scenario, and the tier map routes a composed verdict path reaching a terminal write to a scenario. #642 guarded AC-8 per-tool only, which is how the vacuity survived. Entailed: the scenario's gh fake must discriminate on `--state`. | user-answered |
| D-7 | What happens to the mislabeled `(k7)` case? | Relabel it to claim only what it tests — `resolve_open_pr`'s jq state-ordering through the `--pr-file` seam — and move the reachability claim to the new live-path case. Deleting it would lose genuine seam coverage; leaving the title would let the next reader be fooled the same way. | user-answered |
| D-8 | Does `docs/skill-ablation.md` §2's quote get updated? | No — out of scope, deliberately frozen. A dated measurement record, the same class `check-lockstep-pairs.sh` excludes `docs/plans/` for. A build session must not "fix" the quote to match the corrected prose; doing so destroys the evidence for the finding. | codebase-derived |
| D-9 | Does editing `lean-gate.sh` re-anchor any mutation-catalog row? | Re-verify before commit. `tools/mutation-catalog.tsv:86` `lean-gate-mark-session-guard` is anchored inside `cmd_mark` on `if ! session_in_build_set "$msid"; then`, which this change does not touch — but CLAUDE.md and `writing-tests` make re-anchoring an ordinary-PR obligation whenever a guard's CODE moves, and catalog anchors are literal seds. Confirm rather than assume. Carried as AC-7. | codebase-derived |
| D-10 | Commit verb and bump level. | `fix:` (patch), plus a `Changelog:` trailer — this is a `plugins/**` PR. #642 already typed the merged-PR widening as the feature; #670 repairs it, so `feat:` would overstate. | codebase-derived |
| D-11 | Do the shipped-template edits require anything of consumers who already installed them? | No. Nothing compares an installed `.claude/tools/second-shift-unclaim.sh` against the shipped template — no drift guard exists — and the edits are comments, so an existing consumer's stale copy diverges in rationale only, with no behavioral difference. Site 6 (`schema/second-shift.config.schema.json`) is read from the marketplace at its pinned ref, so it updates with the release. Migration: none. | codebase-derived |
