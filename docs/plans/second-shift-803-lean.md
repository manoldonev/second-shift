# second-shift #803 — re-measure U-5 and R-3 with `review-lead` loaded

Arm 2b (#748) returned a three-unit cut list for `review-lean/SKILL.md`. Executing it (#800) kept
two of the three — U-5 and R-3 — on the same bound the arm itself declared: **`review-lead` is
absent from every arm, including the control**, so a unit that matters only by routing to
`review-lead`, or only by being read by it, reads as `no-effect` in a study that never loads it.
U-5 routes to it; R-3 is its referent at
`plugins/review-toolkit/skills/review-lead/SKILL.md:533`, deferred to by name with no `LOCKSTEP`
marker pairing the two sites.

So both keeps rest on an inherited caveat rather than a measurement. This ticket re-measures those
two units against the same sample (**C2-a**, PR #654 @ `cfba102`) under the same frozen harness
with **exactly one variable moved**: `--plugin-dir plugins/review-toolkit`, which makes
`review-lead` discoverable. Nine runs — control n=3, U-5 n=3, R-3 n=3 — scored by arm 2b's rubric
so the numbers are readable beside it.

The generalizing question is not whether the scores move. It is whether a study that never loads
the implementation a unit routes to can produce a `no-effect` that means anything, and the answer
is registered as a **rule** before the runs so it cannot be a conclusion shaped by the result.

The two-line half of this ticket — §2's *What bounds this arm* naming only U-5 — landed at #807
(`3912f458`) and is not re-done here. What is left is the measurement, and only the measurement.

Pre-flight receipt: `.claude/pipeline-state/803-ledger.md`.

## Acceptance criteria

- AC-1: `docs/skill-ablation-addendum-2.md` exists and is added by the **first commit on this
  branch**, before any run of this arm. It registers, and contains **no result and no arm output**:
  the construction (D-1, D-2), the subject pin, sample, diff range and prompt assembly (D-3), the
  replicates / majority rule / n=5 split escalation / indeterminate handling / void condition (D-4),
  the control-versus-ablated validity asymmetry on `review-lead` invocation (D-5), the reading a
  `no-effect` and a `carrier` license (D-6), and the `review-lead`-as-a-whole sighting and its drift
  limitation (D-7). The ordering is checkable: every run start timestamp recorded under AC-3 is
  later than that commit's committer date.
- AC-2: `docs/skill-ablation-addendum-2.md` registers, in future-binding form, the routing-prose
  rule (D-9): **a unit whose function is routing to an implementation the harness does not load is
  apparatus-bound, and scores `not-reached — no basis`, never `no-effect`.** It names U-5 and R-3 as
  the instances that motivated it, states that it binds this arm and every future one, and states
  that arm 2b's `c2-review/ablation-units.tsv` stays frozen — the rule is registered rather than the
  old file re-labelled.
- AC-3: `docs/plans/skill-ablation/c2-review-reviewlead/README.md` records the **realised**
  invocation verbatim — the piped-prompt one-shot, the `env -u` scrub actually used, the throwaway
  clone at `cfba102`, `--setting-sources ''`, `--model opus`, `--output-format stream-json`, and
  `--plugin-dir plugins/review-toolkit` — plus a per-run apparatus table carrying every column D-14
  fixes: rc, capture bytes, sha256, `tools/classify-capture.sh` verdict, `result` event count,
  tool-call counts, whether `review-lead` was invoked, and the count of tool inputs naming
  `review-lean` (arm 2b's integrity column, which must be **0**). It also records, from the same
  captures, whether `--allowedTools` restricted this batch (OR-3). Raw captures are **not**
  committed; the measurement and its sha256 are what survives, per arm 2b.
- AC-4: The control is adjudicated against **both** void conditions before any unit is scored, and
  each outcome is stated explicitly in the §2 subsection AC-7 adds: the C2-a ground-truth blocker
  reproduced in ≥2 of 3 control runs (D-4), and `review-lead` actually invoked in ≥2 of 3 control
  runs (D-5). Failing either exits the arm `no basis` — U-5 and R-3 are then reported unscored, and
  no `no-effect` is recorded for either.
- AC-5: `docs/plans/skill-ablation/c2-review-reviewlead/` carries one capture-record file per arm —
  `ablated-control-654-review.md`, `ablated-U-5-654-review.md`, `ablated-R-3-654-review.md` — with
  every replicate's output verbatim under its own `## r<n>` heading, and every near-miss quoted and
  adjudicated against the frozen C2 hit rule (same mechanism **and** same consequence; same file
  with a different defect is a miss).
- AC-6: `docs/plans/skill-ablation/c2-review-reviewlead/ablation-units.tsv` gives the machine-readable
  per-unit result for U-5 and R-3: the line range at `8d5d0897`, valid and indeterminate run counts,
  hits, the control's majority, whether `review-lead` was invoked in that arm, and the score under
  D-4 — `carrier`, `no-effect` or `undetermined`, never `no-effect` on fewer than 2 valid runs.
- AC-7: `docs/skill-ablation.md` §2 gains a new subsection placed immediately after
  *Execution (#800)* and before *What bounds this arm*, reporting: the construction and the single
  variable that moved, AC-4's two adjudications, the per-unit scores, what those scores license
  under D-6 (a basis only — they do not re-open #800's keeps), the D-7 `review-lead`-as-a-whole
  sighting **labelled a sighting** with the cross-batch drift limitation named (4 days, CLI 2.1.241
  → 2.1.263, and §C's own control-to-control disagreement), and this construction's own bounds —
  that the whole `review-toolkit` plugin is loaded rather than `review-lead` alone (D-2), and OR-3's
  `--allowedTools` outcome.
- AC-8: `docs/skill-ablation.md` §5's successor list gains a line for this ticket recording its
  outcome, in the same settled-by form the #746 / #747 / #748 / #800 lines use.
- AC-9: Arm 2b's evidence is byte-frozen and the measured subject is untouched:
  `git diff main..HEAD -- docs/plans/skill-ablation/c2-review/ plugins/dev-pipeline/skills/review-lean/SKILL.md`
  is empty. Neither this arm's result nor its rule re-labels a file that describes what the pinned
  run produced.
- AC-10: No release artifact is touched — no `plugins/*/.claude-plugin/plugin.json` `version`, no
  `CHANGELOG.md`, no `.claude-plugin/marketplace.json` `metadata.version` (D-15). Every commit on
  the branch uses the `docs(skill-ablation):` conventional type and carries a `Changelog:` trailer.
- AC-11: No runner script and no selftest is checked in (D-13): the commands live in AC-3's
  evidence README. The change is docs-only, so it adds no row to `docs/prose-blocker-triage.tsv` —
  `bash tools/prose-blockers.sh check` is green and its census is unmoved, the corpus being
  `plugins/**` only.

## Out of scope

- The fourteen `not-reached` units of arm 2b, which §C routes to a successor owed a different
  metric. This is #800's OR-1 default, restated in this ticket's body.
- Any edit to `plugins/dev-pipeline/skills/review-lean/SKILL.md`. No line is cut or kept differently
  by this ticket in either outcome (D-6) — the deletion #800 declined stays declined.
- `plugins/review-toolkit/skills/review-lead/SKILL.md:533`, read as evidence, never edited.
- Arm 2b's `docs/plans/skill-ablation/c2-review/` and its `ablation-units.tsv` — a frozen description
  of what the pinned run produced (AC-9); D-9 registers the rule instead of re-labelling it.
- `--allowedTools` not restricting (#796) and the killed-control lane gap (#795): filed separately.
  This arm records its own encounter with each and fixes neither.
- P10 independence — a lane property no bare-arm review can exhibit or refute.
- The head text of `review-lean/SKILL.md` (190 lines at `origin/main`). The measured surface is the
  pin; moving subject and harness together makes a moved score unattributable (D-3).

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | What "with `review-lead` loaded" means in the harness | Keep arm 2b's frozen one-shot harness verbatim — piped prompt, `--setting-sources ''`, throwaway clone at `cfba102`, `--model opus`, stream-json capture — and add only `--plugin-dir plugins/review-toolkit`. `review-lead` stays DISCOVERABLE rather than pre-read, which is what makes U-5 measurable at all: U-5 is the only text naming it, so ablating U-5 removes the routing and the session must find it or not. One variable moves against arm 2b. Probed working 2026-09-07. | user-answered |
| D-2 | What the plugin brings beyond `review-lead` itself | The whole `review-toolkit` plugin — 3 skills (`review-lead`, `reviewer-baseline`, `mutation-review`) and 18 agents. It is the minimal loadable unit that makes `review-lead` functional, since `review-lead` dispatches the agents under `plugins/review-toolkit/agents/`; a trimmed plugin dir would be a fabricated artifact measuring nothing that ships. The additional surfaces are recorded as a bound of the construction, not smoothed over. | codebase-derived |
| D-3 | Which `review-lean` text is ablated | The pin `8d5d0897`, 127 lines — the measured surface, identical to arm 2b. Sample C2-a (#654 at `cfba102`), diff range `dfd68a47..cfba1022`, `prompt-template.txt` verbatim, assembly order unchanged. Head text (190 lines at `origin/main`) is NOT used: moving the subject and the harness together makes a moved score unattributable, which is the question this ticket asks. Consequence recorded: U-5's measured text was partly superseded at head by #755's scorecard block and #683's CI rule, so the result speaks about the measured surface. | user-answered |
| D-4 | Replicates, scoring rule, void condition | Mirror §C: control n=3, U-5 n=3, R-3 n=3. Same majority rule, same escalation to n=5 on any split, same indeterminate handling — re-run once, and an arm with fewer than 2 valid runs is `undetermined`, never `no-effect`. Void condition: the new control must reproduce the C2-a ground-truth blocker in at least 2 of 3, else the arm exits `no basis` per §C's fallback 2. A different n would make this arm's scores unreadable beside arm 2b's. | user-answered |
| D-5 | Loaded is not invoked — what a run that never invokes `review-lead` means | Record per run, from the stream-json tool events, whether `review-lead` was actually invoked. Asymmetric by registration: for the CONTROL, invocation proves the construction delivered — fewer than 2 of 3 control runs invoking it exits the arm `no basis` (construction not delivered), scoring nothing. For the ABLATED arms, non-invocation is the mechanism under test and never voids a run. Registered explicitly because it is easy to get backwards, and getting it backwards would discard the exact signal U-5's ablation exists to produce. | user-answered |
| D-6 | What a `no-effect` under this construction licenses | A basis only. It removes the inherited caveat; it does not re-open the deletion #800 declined. Grounded in #800's own record: R-3's keep also rests on `review-lead/SKILL.md:533` naming it with no LOCKSTEP pairing, so deleting it silently strands review-lead's rule 5; U-5's keep also rests on its head text interleaving with #755 and #683. Neither reason is one an ablation can overturn. Symmetric case registered now rather than after: a `carrier` result reinforces the keep and scopes §2's "No unit carries the 0.20" claim to the `review-lead`-absent construction. No line of `review-lean/SKILL.md` is edited by this ticket either way. | user-answered |
| D-7 | Whether §C's coarse 18th unit — `review-lead` as a whole — gets scored | Sighting only, not a score. The two controls differ by one thing, but they are 4 days and two CLI versions apart (2.1.241 for arm 2b, 2.1.263 now), so a cross-batch difference conflates `review-lead`'s presence with drift — and §C already recorded that its own controls disagreed with each other, making control-to-control variance a known unattributable term. Recorded side by side with that limitation named; no same-batch absent control is run. | user-answered |
| D-8 | Where this arm's rubric is registered before it runs | A NEW file, `docs/skill-ablation-addendum-2.md`. The existing addendum's own preamble fixes it — "New rules go in new files; this is the first of them" — and its `git log` ordering claim is checkable; its only post-arm commits are factual re-labels, never rules. It lands as the FIRST commit on the branch, before any run, per #748's precedent (`docs/skill-ablation`: pin the spec before any run is scored). It registers D-1 through D-7 and D-9. | user-answered |
| D-9 | What the arm emits about the generalizing question — routing prose under a non-loading harness | A registered rule, future-binding: a unit whose function is routing to an implementation the harness does not load is apparatus-bound and scores `not-reached — no basis`, never `no-effect`. It binds this arm and every future one, and it is registered BEFORE the runs so it cannot be a conclusion shaped by the result. Arm 2b's `ablation-units.tsv` stays frozen — it describes what the pinned run produced — and §2 carries the pointer instead. | user-answered |
| D-10 | Who launches the 9 sessions, given #795 | BUILD launches them, reproducing the batch that actually survived: detached with `start_new_session`, `caffeinate -dims` around the batch, the registered `env -u` scrub plus `RUN_ID`, `LEAN_RUN_MODEL` and `LEAN_ATTEND_MODE`, polling for a terminal `result` event. Only an exit-0 `COMPLETE` capture under `tools/classify-capture.sh` is scored. #795 stays open; the recipe is the mitigation. | user-answered |
| D-11 | Where the raw evidence lands | A sibling directory, `docs/plans/skill-ablation/c2-review-reviewlead/`, carrying its own README with the realised invocation, the control and per-unit capture files, and its own units tsv. Arm 2b's `c2-review/` stays byte-frozen, so no reader can mistake a file from one construction for the other. | user-answered |
| D-12 | Where the results are reported | `docs/skill-ablation.md` §2, a new subsection after *Execution (#800)*, plus a line on §5's successor list. Fixed by §C — "Each arm reports into `docs/skill-ablation.md`; a registration co-located with the results it scores is not a registration" — and by #800's D-4 precedent for the same section. | codebase-derived |
| D-13 | Whether a runner script is checked in | No. Commands are recorded in the evidence README, per the standing rule at `docs/plans/skill-ablation/README.md`: a checked-in script here would owe a selftest under CLAUDE.md, which is machinery to measure whether there is too much machinery. | codebase-derived |
| D-14 | Apparatus facts recorded regardless of outcome | Per run: rc, capture bytes, sha256, `classify-capture.sh` verdict, `result` event count, tool-call counts, whether `review-lead` was invoked, and arm 2b's integrity column — tool inputs naming `review-lean` must be 0, since the clone keeps `plugins/` on disk and a session reading the unablated file would defeat the line-range ablation. Also whether `--allowedTools` restricted this batch, since #796 recorded that it did not on CLI 2.1.241 and the CLI has moved. | codebase-derived |
| D-15 | Commit verb, trailer, frozen files | `docs(skill-ablation):` with `Changelog: none` — docs-only, patch bump per CLAUDE.md. No plugin `version`, no `CHANGELOG.md`, no `marketplace.json` edit; those are release-derived and CI rejects a feature PR that touches them. | codebase-derived |
| D-16 | Whether this ticket absorbs the fourteen `not-reached` units | No. It covers U-5 and R-3 only; the fourteen stay routed to a successor owed a different metric per §C. This is #800's OR-1 default, taken and restated in this ticket's body — see `docs/plans/second-shift-800-lean.md:75-79`. | codebase-derived |
| D-17 | What happens if the batch cannot complete inside the run | Parked under OR-1. | deferred |
| D-18 | Whether a `carrier` result obliges more than scoping §2's claim | Parked under OR-2. | deferred |
| D-19 | Whether the construction is forced back to parity if `--allowedTools` now restricts | Parked under OR-3. | deferred |

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | A 9-run batch with `review-lead`'s panel fan-out may exceed the practical window of the run that launches it | reversible-default-and-flag |
| OR-2 | Whether a `carrier` result on U-5 or R-3 obliges anything beyond scoping §2's headline claim | reversible-default-and-flag |
| OR-3 | #796 recorded that `--allowedTools` did not restrict on CLI 2.1.241; the CLI has since moved | reversible-default-and-flag |

**OR-1** takes the default that **n is never reduced mid-arm**. Reducing it would be a rubric chosen
after seeing how long the runs took — the post-hoc failure the registration exists to prevent. A
unit that cannot reach 2 valid runs reports `undetermined` under D-4 (AC-6) and the arm hands it
back rather than scoring it. Reversing costs a re-run of that unit alone.

**OR-2** takes the default that a `carrier` result changes the report and nothing else: §2's "No
unit carries the 0.20" is scoped to the `review-lead`-absent construction, #800's keep is
reinforced, and `ablation-units.tsv` stays frozen. Reversing costs a doc edit in a successor.

**OR-3** takes the default of **changing nothing to force parity**. If the allowlist now restricts,
that is recorded as a difference between this batch and arm 2b's realised condition (AC-3, AC-7),
not smoothed over by adding flags to reproduce the old leak.
