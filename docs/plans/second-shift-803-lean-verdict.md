# lean review verdict — #803

verdict=approve
run_id: review-803-1
session_id: 7bcdd545-bac3-4e88-befe-1aa95534daad
rounds: 1
pr: #809
reviewed_head: 2e20a31ce647feea14667c546b166064d2b6423d
reviewed_patch_id: 6edfb712948f34efce5e25a4dac770a35ea3b44a
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
panel: review-toolkit:scope-completeness-reviewer
model: unknown
capabilities: pr-marker

# Review round 1 — PR #809 (issue #803)

Range read: `3912f458..2e20a31c` — the full branch diff (root round, nothing to inherit). Six
files, 888 insertions, docs-only. Panel: `review-toolkit:scope-completeness-reviewer` (approve, no
findings) plus the in-session lead pass.

## Verdict

**approve.** No blocker. Every load-bearing factual claim in the record reproduces against the
tree; the two adjudications the arm turns on are independently checkable from the committed
evidence; the three correctness lanes are green at the reviewed head.

## What was verified, not taken on trust

The arm's whole value rests on claims a reader has to be able to repudiate. Each was re-derived
at `2e20a31c`:

- **The subject pin.** `8d5d0897:review-lean/SKILL.md` is 127 lines. U-5 at 48–55 is the Review
  step naming `review-lead` as the implementation; R-3 at 110–114 is the inheritance rule. Both
  ranges match the ablated text exactly. Head is 190 lines, as D-3 states.
- **The one-variable justification — the strongest part of the construction.** The claim that the
  clone's own `review-toolkit` had to be rejected is exact: `cfba1022:review-lead/SKILL.md` is
  **446 lines**, contains **zero** matches for `inheritance contract governs`, and **zero** for
  R-3's own text. Loading it would indeed have re-created the confound one layer down. The
  shipping tree hash `549b0d17683b6196028995baafeb9a60869b73d2` matches `HEAD:plugins/review-toolkit`.
- **The referent R-3 is exposed by.** `review-lead/SKILL.md:533` is rule 5, *"The caller's
  inheritance contract governs"* — the exact line, not an approximate one.
- **The 2-of-3 finding adjudication.** r3's committed output carries exactly one blocker, and it
  is the one quoted in the adjudication section verbatim (`check-gate-buckets.sh:300`, `exit
  "$violations"` mod 256). Same file, different defect from the C2-a ground truth, so a miss under
  `docs/skill-ablation-pre-registration.md`'s frozen rule — which I read at that citation and
  which says what the record says it says. r1 and r2 both name the command-position regex at
  `check-gate-buckets.sh:109`, the omitted reserved words, the live `lean-gate.sh:420` site and the
  denominator consequence: same mechanism, same consequence, HIT.
- **Verbatim means verbatim.** Zero truncation markers in the capture record; the ellipses visible
  in a terminal are the reader's, not the file's.
- **The drift limitation is sourced, and pre-existing.** *"the controls disagree with each other —
  one raised two blockers the other two did not"* is at `docs/skill-ablation.md:695` **at the
  base** — the new subsection cites a bound the repo already carried rather than inventing one.
- **Registration ordering.** `docs/skill-ablation-addendum-2.md` lands in `ef23f4ba`, the first
  commit, committer date `2026-09-06T23:23:41Z`. The three run starts are `23:24:29Z`, `23:24:30Z`,
  `23:24:30Z` — all later. The second commit does not touch the addendum, so its "no results"
  property holds at the reviewed head, not merely at authoring time.
- **Arm 2b's numbers are quoted correctly.** Its `ablation-units.tsv` really does score U-5 (48–55)
  and R-3 (110–114) `no-effect` on a control of `HIT 3/3`, which is the caveat this arm was filed
  to remove.

## The one structural divergence

`README.md` does not carry what AC-3 assigns it. AC-3 names the README as the file recording the
realised invocation verbatim, the per-run apparatus table over D-14's eight columns, and the OR-3
`--allowedTools` observation. The README carries none of the three: its "The commands" section is a
six-step reproduction sketch with placeholders whose step 5 explicitly defers (`# 5. the run — see
ablated-control-654-review.md for the full env scrub`), and its one table is assembled-prompt
sha256s, not the apparatus.

**Measured as inert, and that is why it is not a blocker.** All three obligations are discharged in
`ablated-control-654-review.md`, the sibling file in the same three-file directory, under headings
named for them — `## The realised invocation`, `## Apparatus`, `` ## `--allowedTools` — recorded,
per OR-3 ``. Every one of D-14's eight columns is present in that table (rc, capture bytes, sha256,
`classify-capture.sh` verdict, `result` event count, tool-call counts, `review-lead` invoked,
`review-lean` naming count at 0 in all three runs). The README's own bullet names that file and
lists exactly those four contents. So no fact AC-3 requires is unrecorded, unhashed or hard to
find; what moved is which of two adjacent documents holds it. Scored `divergent-inert` rather than
softened to `satisfied`, because the AC does name a file and that file does not do it.

## Warnings

1. **`docs/skill-ablation-addendum-2.md:205` — "4 days" does not reproduce.** Arm 2b's control ran
   `2026-09-03T18:29:51Z`; this one `2026-09-06T23:24:29Z`. That is 3 days 5 hours elapsed (4
   calendar days in local `+03:00`, Sep 3 → Sep 7). The claim's *function* — the two batches are
   not same-batch, so drift is uncontrolled — is unaffected, and the reported §2 subsection is
   already the more conservative "days and two CLI versions apart". Worth noting only because the
   registration file is the one place in this study whose numbers are meant to be pins.
2. **CLI `2.1.241` for arm 2b is asserted, not sourced in-repo.** #796 measures the
   `--allowedTools` leak on 2026-09-03 across arm 2b's runs but records no version string, and arm
   2b's own capture record carries none. The inference is almost certainly right; it is the one
   apparatus number in the new files with no committed origin. It changes nothing — the sighting is
   declined either way.
3. **"§C already recorded…" is loose attribution.** The control-to-control disagreement is recorded
   in `docs/skill-ablation.md` §2's *What bounds this arm* — a report about §C's arm — not in §C
   (`docs/skill-ablation-addendum.md`) itself. The fact is real and pre-existing; only the pointer
   is imprecise.
4. **§C's fallback 1 is applied outside its trigger.** Fallback 1 fires *when the control is void*;
   arm 2b's control was `HIT 3/3`, so it never fired there. This arm runs fallback 1's recipe
   anyway. That is a widening, but it resolves in the conservative direction — the 18th unit is
   explicitly declined a score — so it costs nothing.

## Strengths

- **The result is the honest one, and it is the harder one to write.** An arm that spent nine runs
  and returned a score would have been easier to report than one that spent three and returned
  `no basis`. The delivery bar it failed was registered before the runs, in a commit that does not
  touch the results, and the arm exits on it rather than negotiating with it.
- **Both void conditions are adjudicated separately.** Recording only the one that failed would
  have left a reader unable to tell "the construction was not delivered" from "the control could
  not review". The record states 2-of-3 on the finding condition and 0-of-3 on the delivery
  condition, and says in terms that the exit is owed to the second alone.
- **The nonce probe is the right instrument.** Verifying which `review-lead` the flag loads by
  planting a nonce in the frontmatter — and explicitly recording that the cheaper probe (asking the
  session for the path) returned the *wrong* answer — is the difference between an apparatus that
  was checked and one that was assumed. It also pre-empts the exact objection the clone's on-disk
  `plugins/` invites.
- **The two ablated prompts are assembled and hashed but not run.** That makes the *reason* they
  did not run checkable: the arm stopped at the control, not for want of a prompt.
- **The generalizing claim is scoped to what was measured.** "Making an implementation discoverable
  does not make a one-shot review session route to it" is supported by 3-of-3 non-invocation with
  the skill, all 18 agents and the `Skill` tool on offer; and the section that states it also states
  what a successor would have to change, without filing it.
- **#800's keeps are correctly left alone.** The record says plainly that they never depended on
  this measurement, and re-states the two independent reasons. Nothing is re-litigated on the
  strength of a void arm.

## Merge-boundary state (recorded, not a blocker)

`pr-gates` is red on *pipeline chain reconciliation* at `2e20a31c` — the expected pre-approve
state, since no verdict record exists yet. It clears when this record is pushed. The three
correctness lanes are green at the reviewed head and are cited rather than re-run: `lint-and-selftests`
pass (4m19s), `selftests (macos, bash 3.2)` pass (5m41s), `mutation-sweep-pr` pass (11s) — run
`34067620986`, head `2e20a31ce647feea14667c546b166064d2b6423d`.

## Scope completeness

`review-toolkit:scope-completeness-reviewer` returned **approve**, no findings. Its two suppressed
items were both correctly self-dismissed: U-5 and R-3 ending unscored is the registered protocol
rather than an omission, and the §2 bounds-statement correction it looked for is present at the
base already (landed at #807).

## AC scorecard

| AC-n | score | evidence |
| --- | --- | --- |
| AC-1 | satisfied | `ef23f4ba` is the first commit and adds `docs/skill-ablation-addendum-2.md`; the second commit does not touch it, so it holds no result at the reviewed head. It registers D-1/D-2 (construction, plugin bound), D-3 (pin, sample, range, assembly), D-4 (replicates, majority, n=5, indeterminate, void), D-5 (asymmetry), D-6 (licences), D-7 (sighting). Committer date `2026-09-06T23:23:41Z` precedes all three run starts (`23:24:29Z`, `23:24:30Z`, `23:24:30Z`). |
| AC-2 | satisfied | The routing-prose rule is registered in future-binding blockquote form, names U-5 and R-3 as the motivating instances, states it binds this arm and every future one, and states that arm 2b's `c2-review/ablation-units.tsv` stays frozen with the rule registered instead of the file re-labelled. `git diff` over that file is empty. |
| AC-3 | divergent-inert | The README carries neither the verbatim realised invocation, nor the D-14 apparatus table, nor the OR-3 record; its step 5 defers explicitly. measured: all three are present in `ablated-control-654-review.md` in the same directory under `## The realised invocation`, `## Apparatus` and the `--allowedTools` heading, with all eight D-14 columns populated and the `review-lean` integrity column 0 in every run, and the README's own bullet names that file as their location. No required fact is unrecorded or unhashed. follow-up: this round's PR #809 findings comment records the placement; no separate ticket is owed, the content being complete and indexed in-directory. |
| AC-4 | satisfied | Both conditions are adjudicated before any unit is scored and both outcomes are stated in the §2 subsection AC-7 adds, as a bar-versus-measured table: finding condition 2 of 3 clears, delivery condition 0 of 3 fails. The record states the exit is owed to the second alone. U-5 and R-3 are reported unscored and no `no-effect` is recorded for either. |
| AC-5 | satisfied | `ablated-control-654-review.md` is the only per-arm file; no `ablated-U-5-` or `ablated-R-3-` file exists, and the README says so and why. All three replicates appear verbatim under `## r1`, `## r2`, `## r3` with zero truncation markers. The r3 near-miss is quoted verbatim and adjudicated a miss against the frozen hit rule at the cited pre-registration lines, which I read and which match. |
| AC-6 | satisfied | `ablation-units.tsv` carries the line range at `8d5d0897`, valid and indeterminate run counts, hits, control majority, the `control_review_lead_invoked` column and the score, plus a basis column. U-5 and R-3 score `not-reached--no-basis` on `runs_valid` 0, so nothing is scored `no-effect` on fewer than 2 valid runs. Ranges match the pin. |
| AC-7 | satisfied | The subsection sits at line 583, after *Execution (#800)* at 555 and before *What bounds this arm* at 682. It reports the construction and the single variable, both AC-4 adjudications, the per-unit outcome, what it licenses under D-6, the D-7 sighting labelled a sighting with the drift limitation named (days apart, 2.1.241 to 2.1.263, and §C's control-to-control disagreement), the whole-plugin bound from D-2, and OR-3's outcome. The reported text drops "4" from "4 days", which is the more conservative reading and does not remove the limitation. |
| AC-8 | satisfied | §5 gains a `#803 is done, and it returns no basis` bullet in the same settled-by form as the #746, #747, #748 and #800 lines, recording the outcome, the 3-of-3 versus 0-of-3 split, that the keeps are unchanged, and the pointer to the registered rule. |
| AC-9 | satisfied | `git diff main..HEAD -- docs/plans/skill-ablation/c2-review/ plugins/dev-pipeline/skills/review-lean/SKILL.md` produces zero lines at the reviewed head. |
| AC-10 | satisfied | No path in the diff matches a plugin manifest, `CHANGELOG.md` or `marketplace.json`. Both commits use `docs(skill-ablation):` and both carry a `Changelog: none` trailer. |
| AC-11 | satisfied | The diff is six docs paths — no runner script, no selftest. `bash tools/prose-blockers.sh check` exits 0 with zero undispositioned constructs, and `docs/prose-blocker-triage.tsv` is absent from the diff; the corpus is `plugins/**` only and the diff touches no such path, so the census is structurally unmoved. |
